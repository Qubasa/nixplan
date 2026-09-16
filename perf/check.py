"""Compare planner evaluation measurements against the committed budgets.

The harness gates only on the counters nix reports identically across repeated
runs of one input on one interpreter version. Wall clock and ``cpuTime`` are
reported and never gate a build. Every budget is a cost per plan entry, so a
fixture that gains entries does not silently consume headroom.
"""

from __future__ import annotations

import argparse
import json
import math
from collections.abc import Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Literal

GATED_COUNTERS: tuple[str, ...] = (
    "nrThunks",
    "nrFunctionCalls",
    "nrPrimOpCalls",
    "values.number",
    "sets.bytes",
    "envs.bytes",
    "list.elements",
    "nrOpUpdateValuesCopied",
    "gc.totalBytes",
)
# What `measure.sh` writes beside its result files, one fixture key per line.
REQUESTED = "requested"
DEFAULT_MARGIN = 0.15
TOLERANCE = 1e-9

type Kind = Literal["FAIL", "INVALID", "INFO"]


@dataclass(frozen=True)
class Budget:
    """One fixture's budget, with the defaults the file states beside it resolved in."""

    fixture: str | None
    interpreter: str | None
    date: str | None
    margin: float
    per_entry: dict[str, float | None]


@dataclass(frozen=True)
class Budgets:
    """The budget file: one budget per fixture, and the growth bound over its sizes."""

    fixtures: dict[str, Budget]
    bound: float | None
    sizes: list[int] | None


@dataclass(frozen=True)
class Run:
    """One measured evaluation."""

    cpu_time: float | None
    wall_clock: float | None
    counters: dict[str, float]


@dataclass(frozen=True)
class Result:
    """Every run of one fixture at one size."""

    key: str
    fixture: str
    size: int | None
    interpreter: str
    entries: int
    runs: tuple[Run, ...]
    source: str


@dataclass(frozen=True)
class Finding:
    """One line of the report. Only ``FAIL`` gates the build."""

    kind: Kind
    message: str

    def __str__(self) -> str:
        return f"{self.kind}: {self.message}"


def figure(value: float) -> str:
    """Render a per-entry figure as it would be written into the budget file."""
    if abs(value - round(value)) < TOLERANCE:
        return json.dumps(round(value))
    return json.dumps(math.ceil(value * 10000) / 10000)


def per_entry(result: Result, counter: str) -> float:
    """Return the cost of one counter per plan entry, from the first run."""
    return float(result.runs[0].counters[counter]) / result.entries


def parse_result(path: Path) -> tuple[Result | None, list[Finding]]:
    """Read one result file, or report why it cannot be compared."""
    raw: dict[str, Any] = json.loads(path.read_text(encoding="utf-8"))
    missing = [name for name in ("fixture", "interpreter", "entries", "runs") if name not in raw]
    if missing:
        return None, [Finding("FAIL", f"result file {path.name} records no {', '.join(missing)}")]
    entries = raw["entries"]
    if entries < 1:
        return None, [Finding("FAIL", f"result file {path.name} records {entries} plan entries")]
    runs = tuple(
        Run(run.get("cpuTime"), run.get("wallClock"), dict(run.get("counters", {})))
        for run in raw["runs"]
    )
    if not runs:
        return None, [Finding("FAIL", f"result file {path.name} carries no runs")]
    size = raw.get("size")
    fixture = raw["fixture"]
    result = Result(
        key=fixture if size is None else f"{fixture}-{size}",
        fixture=fixture,
        size=size,
        interpreter=raw["interpreter"],
        entries=entries,
        runs=runs,
        source=path.name,
    )
    return result, []


def parse_budgets(path: Path) -> Budgets:
    """Read the budget file. A field an entry omits is the one the file states once."""
    raw: dict[str, Any] = json.loads(path.read_text(encoding="utf-8"))
    growth: dict[str, Any] = raw.get("growth") or {}

    def resolve(entry: dict[str, Any], field: str, fallback: Any = None) -> Any:
        stated = entry.get(field)
        stated = raw.get(field) if stated is None else stated
        return fallback if stated is None else stated

    return Budgets(
        fixtures={
            name: Budget(
                fixture=entry.get("fixture"),
                interpreter=resolve(entry, "interpreter"),
                date=resolve(entry, "date"),
                margin=float(resolve(entry, "margin", DEFAULT_MARGIN)),
                per_entry=dict(entry.get("perEntry") or {}),
            )
            for name, entry in (raw.get("fixtures") or {}).items()
        },
        bound=growth.get("bound"),
        sizes=growth.get("sizes"),
    )


def load_results(directory: Path) -> tuple[list[Result], list[Finding]]:
    """Load every result file in a directory, sorted by file name."""
    results: list[Result] = []
    findings: list[Finding] = []
    paths = sorted(directory.glob("*.json"))
    if not paths:
        findings.append(Finding("FAIL", f"no result files under {directory}"))
    for path in paths:
        result, parse_findings = parse_result(path)
        findings.extend(parse_findings)
        if result is not None:
            results.append(result)
    return results, findings


def check_reproducibility(results: Sequence[Result]) -> tuple[set[str], list[Finding]]:
    """Refuse a gated counter that is not byte-equal across the runs it was given."""
    unstable: set[str] = set()
    findings: list[Finding] = []
    for result in results:
        for counter in GATED_COUNTERS:
            values = [run.counters.get(counter) for run in result.runs]
            if any(not isinstance(value, int) or isinstance(value, bool) for value in values):
                reason = f"is missing or not an integer in {result.source}: {values}"
            elif len(set(values)) > 1:
                reason = (
                    f"is not reproducible across its {len(values)} runs: {values}; no budget "
                    f"result derived from {result.key} is reported"
                )
            else:
                continue
            unstable.add(result.key)
            findings.append(
                Finding("FAIL", f"gated counter {counter} of fixture {result.key} {reason}")
            )
    return unstable, findings


def check_interpreter(
    results: Sequence[Result], fixtures: dict[str, Budget]
) -> tuple[set[str], list[Finding]]:
    """Invalidate, rather than fail, a comparison against another interpreter."""
    mismatched: set[str] = set()
    findings: list[Finding] = []
    for result in results:
        budget = fixtures.get(result.key)
        recorded = None if budget is None else budget.interpreter
        if recorded is None or recorded == result.interpreter:
            continue
        mismatched.add(result.key)
        findings.append(
            Finding(
                "INVALID",
                f"fixture {result.key} was measured on nix {result.interpreter} but its budgets "
                f"were recorded under nix {recorded}; the comparison is invalid and was skipped, "
                f"not failed",
            )
        )
    return mismatched, findings


def entry_provenance(name: str, budget: Budget) -> list[Finding]:
    """Refuse a budget entry that records no provenance or no figure."""
    findings = [
        Finding("FAIL", f"budget entry {name} records no {field}")
        for field, stated in (
            ("fixture", budget.fixture),
            ("interpreter", budget.interpreter),
            ("date", budget.date),
        )
        if stated is None
    ]
    return findings + [
        Finding(
            "FAIL",
            f"budget figure not recorded: entry {name}, field {counter}; measure the "
            f"fixture and write the figure into the budget file",
        )
        for counter in GATED_COUNTERS
        if budget.per_entry.get(counter) is None
    ]


def check_provenance(
    results: Sequence[Result], fixtures: dict[str, Budget]
) -> tuple[set[str], list[Finding]]:
    """Refuse an unknown fixture and any budget entry that cannot be compared against."""
    unusable: set[str] = set()
    findings: list[Finding] = []
    for result in results:
        if result.key not in fixtures:
            unusable.add(result.key)
            findings.append(
                Finding(
                    "FAIL",
                    f"result file {result.source} names fixture {result.key}, which the budget "
                    f"file does not list",
                )
            )
    for name in sorted(fixtures):
        entry_findings = entry_provenance(name, fixtures[name])
        if entry_findings:
            unusable.add(name)
        findings.extend(entry_findings)
    return unusable, findings


def ratchet_counter(result: Result, counter: str, budget: float, margin: float) -> Finding:
    """Compare one counter against its budget in both directions."""
    measured = per_entry(result, counter)
    shared = (
        f"gated counter {counter} of fixture {result.key} costs {figure(measured)} per plan entry"
    )
    if measured > budget * (1.0 + TOLERANCE):
        return Finding("FAIL", f"{shared}, above its budget of {figure(budget)}")
    if measured < budget * (1.0 - margin) * (1.0 - TOLERANCE):
        return Finding(
            "FAIL",
            f"{shared}, more than the {margin:.0%} margin below its budget of {figure(budget)}; "
            f'lower the budget of {result.key} to "{counter}": {figure(measured)}',
        )
    headroom = 0.0 if budget == 0 else (budget - measured) / budget
    return Finding(
        "INFO",
        f"{shared} with {headroom:.1%} of headroom below its budget of {figure(budget)}, "
        f"within the {margin:.0%} margin",
    )


def requested_fixtures(results_dir: Path) -> set[str] | None:
    """Return the fixture keys the measurement was asked to produce, if it said.

    `measure.sh` writes the list before it measures anything, so a run asked for
    a subset covers that subset and a run that died covers the case it never
    wrote. A directory carrying no such list is held to the whole budget file.
    """
    stated = results_dir / REQUESTED
    if not stated.is_file():
        return None
    asked = stated.read_text(encoding="utf-8").splitlines()
    return {line.strip() for line in asked if line.strip()}


def gated_figures(fixtures: dict[str, Budget]) -> set[tuple[str, str]]:
    """Return every (fixture, counter) pair the budget file gates."""
    return {
        (name, counter)
        for name, budget in fixtures.items()
        for counter in GATED_COUNTERS
        if budget.per_entry.get(counter) is not None
    }


def covered_figures(fixtures: dict[str, Budget], asked: set[str] | None) -> set[tuple[str, str]]:
    """Return the gated figures of the fixtures a run was asked to produce."""
    return {figure for figure in gated_figures(fixtures) if asked is None or figure[0] in asked}


def check_coverage(
    compared: set[tuple[str, str]],
    fixtures: dict[str, Budget],
    asked: set[str] | None,
) -> list[Finding]:
    """Refuse a run that compared nothing against a figure it was asked to cover.

    A gate reporting no failures because it compared nothing is the failure this
    exists for. What it covers is the figures of the fixtures the run was asked
    for: a comparison the run skipped for a reason it printed is uncovered too,
    because a reason printed beside a green gate is still a green gate.
    """
    gated = gated_figures(fixtures)
    absent: dict[str, list[str]] = {}
    for name, counter in sorted(covered_figures(fixtures, asked) - compared):
        absent.setdefault(name, []).append(counter)
    return [
        Finding(
            "FAIL",
            f"the budget file gates {len([f for f in gated if f[0] == name])} figures of fixture "
            f"{name} and this run compared none of {', '.join(counters)}",
        )
        for name, counters in sorted(absent.items())
    ]


def check_ratchet(
    results: Sequence[Result], budgets: Budgets, skip: set[str]
) -> tuple[set[tuple[str, str]], list[Finding]]:
    """Run the two-sided ratchet, returning the figures it compared and its findings."""
    compared: set[tuple[str, str]] = set()
    findings: list[Finding] = []
    for result in results:
        entry = budgets.fixtures.get(result.key)
        if entry is None or result.key in skip:
            continue
        for counter in GATED_COUNTERS:
            budget = entry.per_entry.get(counter)
            if budget is None or counter not in result.runs[0].counters:
                continue
            compared.add((result.key, counter))
            findings.append(ratchet_counter(result, counter, budget, entry.margin))
    return compared, findings


def sized_series(
    results: Sequence[Result], skip: set[str], sizes: list[int] | None
) -> dict[str, list[Result]]:
    """Group every comparable sized result by fixture, ascending by size."""
    wanted = set(sizes) if sizes else None
    grouped: dict[str, list[tuple[int, Result]]] = {}
    for result in results:
        if result.size is None or result.key in skip:
            continue
        if wanted is not None and result.size not in wanted:
            continue
        grouped.setdefault(result.fixture, []).append((result.size, result))
    return {
        fixture: [result for _, result in sorted(series, key=lambda sized: sized[0])]
        for fixture, series in sorted(grouped.items())
    }


def growth_ratio(result: Result, base: Result, counter: str) -> float:
    """Return the per-entry cost of a counter relative to the smallest size."""
    base_cost = per_entry(base, counter)
    cost = per_entry(result, counter)
    if base_cost == 0.0:
        return 1.0 if cost == 0.0 else math.inf
    return cost / base_cost


def fixture_growth(fixture: str, series: Sequence[Result], bound: float) -> list[Finding]:
    """Bound how fast one sized fixture's per-entry cost may grow across its sizes."""
    smallest, largest = series[0], series[-1]
    findings: list[Finding] = []
    for result in series[1:]:
        ratios = " ".join(
            f"{counter}={growth_ratio(result, smallest, counter):.3f}" for counter in GATED_COUNTERS
        )
        findings.append(
            Finding(
                "INFO",
                f"growth of fixture {fixture} at size {result.size} against size "
                f"{smallest.size}: {ratios}",
            )
        )
    for counter in GATED_COUNTERS:
        ratio = growth_ratio(largest, smallest, counter)
        if ratio > bound * (1.0 + TOLERANCE):
            findings.append(
                Finding(
                    "FAIL",
                    f"gated counter {counter} of fixture {fixture} grew by {ratio:.3f} per plan "
                    f"entry from size {smallest.size} to size {largest.size}, above the bound "
                    f"of {bound}",
                )
            )
    return findings


def check_growth(results: Sequence[Result], budgets: Budgets, skip: set[str]) -> list[Finding]:
    """Bound the per-entry cost of every fixture measured at more than one size."""
    bound = budgets.bound
    if bound is None:
        return [Finding("FAIL", "the budget file states no growth bound")]
    grouped = sized_series(results, skip, budgets.sizes)
    findings: list[Finding] = []
    for fixture, series in grouped.items():
        if len(series) < 2:
            findings.append(
                Finding(
                    "INFO",
                    f"the growth bound needs two comparable sizes of fixture {fixture}, "
                    f"{len(series)} was usable",
                )
            )
            continue
        findings.extend(fixture_growth(fixture, series, bound))
    if not findings:
        return [
            Finding("INFO", "the growth bound found no sized fixture with two comparable sizes")
        ]
    return findings


def timings(runs: Sequence[Run]) -> str:
    """Render the advisory wall clock and cpuTime series of one fixture."""
    parts: list[str] = []
    for label, values in (
        ("wall clock", [run.wall_clock for run in runs]),
        ("cpuTime", [run.cpu_time for run in runs]),
    ):
        present = [value for value in values if value is not None]
        if not present:
            parts.append(f"{label} was not recorded")
            continue
        series = ", ".join(f"{value:.4f}s" for value in present)
        parts.append(f"{label} per run: {series} (change {present[-1] - present[0]:+.4f}s)")
    return "; ".join(parts)


@dataclass(frozen=True)
class Report:
    """Every finding, and how much of the gate the run actually compared."""

    findings: list[Finding]
    compared: int
    gated: int


def run_checks(results_dir: Path, budgets_path: Path) -> Report:
    """Run every check in order and return the whole report."""
    budgets = parse_budgets(budgets_path)
    fixtures = budgets.fixtures
    asked = requested_fixtures(results_dir)
    results, findings = load_results(results_dir)
    if not fixtures:
        findings.append(Finding("FAIL", f"the budget file {budgets_path} lists no fixtures"))
    unstable, reproducibility = check_reproducibility(results)
    mismatched, interpreter = check_interpreter(results, fixtures)
    unusable, provenance = check_provenance(results, fixtures)
    compared, ratchet = check_ratchet(results, budgets, unstable | mismatched | unusable)
    covers = covered_figures(fixtures, asked)
    findings.extend(reproducibility)
    findings.extend(interpreter)
    findings.extend(provenance)
    findings.extend(check_coverage(compared, fixtures, asked))
    findings.extend(ratchet)
    findings.extend(check_growth(results, budgets, unstable))
    findings.extend(
        Finding("INFO", f"fixture {result.key} {timings(result.runs)}, advisory, never gated")
        for result in results
    )
    return Report(findings=findings, compared=len(compared), gated=len(covers))


def parse_args(argv: Sequence[str] | None) -> argparse.Namespace:
    """Parse the command line."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--results", required=True, type=Path, help="directory of result files")
    parser.add_argument("--budgets", required=True, type=Path, help="the budget file")
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    """Print the report and return 0 when no gated counter failed."""
    args = parse_args(argv)
    report = run_checks(args.results, args.budgets)
    for finding in report.findings:
        print(finding)
    failures = [finding for finding in report.findings if finding.kind == "FAIL"]
    invalid = [finding for finding in report.findings if finding.kind == "INVALID"]
    print(
        f"check.py: {len(failures)} failures, {len(invalid)} invalid comparisons, "
        f"{report.compared} of {report.gated} gated figures compared"
    )
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
