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
from typing import Literal, TypedDict, cast

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
REQUIRED_BUDGET_FIELDS: tuple[str, ...] = ("fixture", "interpreter", "date", "margin")
# What `measure.sh` writes beside its result files, one fixture key per line.
REQUESTED = "requested"
DEFAULT_MARGIN = 0.15
TOLERANCE = 1e-9

type Kind = Literal["FAIL", "INVALID", "INFO"]


class RawRun(TypedDict, total=False):
    """One measured evaluation as ``measure.sh`` writes it."""

    cpuTime: float
    wallClock: float
    counters: dict[str, float]


class RawResult(TypedDict, total=False):
    """One fixture and size as ``measure.sh`` writes it."""

    fixture: str
    size: int | None
    interpreter: str
    entries: int
    runs: list[RawRun]


class RawGrowth(TypedDict, total=False):
    """The growth block of the budget file."""

    bound: float
    sizes: list[int]
    note: str


class RawBudgetEntry(TypedDict, total=False):
    """One fixture's budget entry."""

    fixture: str
    interpreter: str
    date: str
    margin: float
    perEntry: dict[str, float | None]
    note: str


class RawBudgets(TypedDict, total=False):
    """The budget file."""

    margin: float
    growth: RawGrowth
    fixtures: dict[str, RawBudgetEntry]


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
    raw = cast(RawResult, json.loads(path.read_text(encoding="utf-8")))
    missing = [name for name in ("fixture", "interpreter", "entries", "runs") if name not in raw]
    if missing:
        return None, [Finding("FAIL", f"result file {path.name} records no {', '.join(missing)}")]
    entries = raw["entries"]
    if entries < 1:
        return None, [Finding("FAIL", f"result file {path.name} records {entries} plan entries")]
    runs = tuple(
        Run(
            cpu_time=run.get("cpuTime"),
            wall_clock=run.get("wallClock"),
            counters=dict(run.get("counters", {})),
        )
        for run in raw["runs"]
    )
    if not runs:
        return None, [Finding("FAIL", f"result file {path.name} carries no runs")]
    size = raw.get("size")
    fixture = raw["fixture"]
    return (
        Result(
            key=fixture if size is None else f"{fixture}-{size}",
            fixture=fixture,
            size=size,
            interpreter=raw["interpreter"],
            entries=entries,
            runs=runs,
            source=path.name,
        ),
        [],
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
                unstable.add(result.key)
                findings.append(
                    Finding(
                        "FAIL",
                        f"gated counter {counter} of fixture {result.key} is missing or not an "
                        f"integer in {result.source}: {values}",
                    )
                )
            elif len(set(values)) > 1:
                unstable.add(result.key)
                findings.append(
                    Finding(
                        "FAIL",
                        f"gated counter {counter} of fixture {result.key} is not reproducible "
                        f"across its {len(values)} runs: {values}; no budget result derived "
                        f"from {result.key} is reported",
                    )
                )
    return unstable, findings


def check_interpreter(
    results: Sequence[Result], fixtures: dict[str, RawBudgetEntry]
) -> tuple[set[str], list[Finding]]:
    """Invalidate, rather than fail, a comparison against another interpreter."""
    mismatched: set[str] = set()
    findings: list[Finding] = []
    for result in results:
        recorded = fixtures.get(result.key, {}).get("interpreter")
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


def entry_provenance(name: str, entry: RawBudgetEntry) -> list[Finding]:
    """Refuse a budget entry that records no provenance or no figure."""
    findings: list[Finding] = []
    for field in REQUIRED_BUDGET_FIELDS:
        if entry.get(field) is None:
            findings.append(Finding("FAIL", f"budget entry {name} records no {field}"))
    per_entry_figures = entry.get("perEntry") or {}
    for counter in GATED_COUNTERS:
        if per_entry_figures.get(counter) is None:
            findings.append(
                Finding(
                    "FAIL",
                    f"budget figure not recorded: entry {name}, field {counter}; measure the "
                    f"fixture and write the figure into the budget file",
                )
            )
    return findings


def check_provenance(
    results: Sequence[Result], fixtures: dict[str, RawBudgetEntry]
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
        return Finding(
            "FAIL",
            f"{shared}, above its budget of {figure(budget)}",
        )
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


def gated_figures(fixtures: dict[str, RawBudgetEntry]) -> set[tuple[str, str]]:
    """Return every (fixture, counter) pair the budget file gates."""
    return {
        (name, counter)
        for name, entry in fixtures.items()
        for counter in GATED_COUNTERS
        if (entry.get("perEntry") or {}).get(counter) is not None
    }


def check_coverage(
    compared: set[tuple[str, str]],
    fixtures: dict[str, RawBudgetEntry],
    asked: set[str] | None,
) -> list[Finding]:
    """Refuse a run that compared nothing against a figure it was asked to cover.

    A gate reporting no failures because it compared nothing is the failure this
    exists for. What it covers is the figures of the fixtures the run was asked
    for: a comparison the run skipped for a reason it printed is uncovered too,
    because a reason printed beside a green gate is still a green gate.
    """
    covered = {figure for figure in gated_figures(fixtures) if asked is None or figure[0] in asked}
    absent: dict[str, list[str]] = {}
    for name, counter in sorted(covered - compared):
        absent.setdefault(name, []).append(counter)
    return [
        Finding(
            "FAIL",
            f"the budget file gates {counters_of(fixtures, name)} figures of fixture {name} and "
            f"this run compared none of {', '.join(counters)}",
        )
        for name, counters in sorted(absent.items())
    ]


def counters_of(fixtures: dict[str, RawBudgetEntry], name: str) -> int:
    """Return how many figures the budget file gates for one fixture."""
    return len([figure for figure in gated_figures(fixtures) if figure[0] == name])


def check_ratchet(
    results: Sequence[Result], budgets: RawBudgets, skip: set[str]
) -> tuple[set[tuple[str, str]], list[Finding]]:
    """Run the two-sided ratchet, returning the figures it compared and its findings."""
    fixtures = budgets.get("fixtures", {})
    default_margin = budgets.get("margin", DEFAULT_MARGIN)
    compared: set[tuple[str, str]] = set()
    findings: list[Finding] = []
    for result in results:
        entry = fixtures.get(result.key)
        if entry is None or result.key in skip:
            continue
        margin = entry.get("margin", default_margin)
        for counter in GATED_COUNTERS:
            budget = (entry.get("perEntry") or {}).get(counter)
            if budget is None or counter not in result.runs[0].counters:
                continue
            compared.add((result.key, counter))
            findings.append(ratchet_counter(result, counter, budget, margin))
    return compared, findings


def sized_series(
    results: Sequence[Result], skip: set[str], sizes: list[int] | None
) -> dict[str, list[Result]]:
    """Group every comparable sized result by fixture, ascending by size."""
    wanted = set(sizes) if sizes else None
    grouped: dict[str, list[Result]] = {}
    for result in results:
        if result.size is None or result.key in skip:
            continue
        if wanted is not None and result.size not in wanted:
            continue
        grouped.setdefault(result.fixture, []).append(result)
    return {
        fixture: sorted(series, key=lambda result: cast(int, result.size))
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


def check_growth(results: Sequence[Result], budgets: RawBudgets, skip: set[str]) -> list[Finding]:
    """Bound the per-entry cost of every fixture measured at more than one size."""
    growth = budgets.get("growth")
    if growth is None or growth.get("bound") is None:
        return [Finding("FAIL", "the budget file states no growth bound")]
    bound = growth["bound"]
    grouped = sized_series(results, skip, growth.get("sizes"))
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


def timing_series(label: str, values: Sequence[float | None]) -> str:
    """Render an advisory timing series and its change across runs."""
    present = [value for value in values if value is not None]
    if not present:
        return f"{label} was not recorded"
    runs = ", ".join(f"{value:.4f}s" for value in present)
    change = present[-1] - present[0]
    return f"{label} per run: {runs} (change {change:+.4f}s, advisory, never gated)"


def report_timings(results: Sequence[Result]) -> list[Finding]:
    """Report wall clock and cpuTime for every fixture without gating on either."""
    findings: list[Finding] = []
    for result in results:
        findings.append(
            Finding(
                "INFO",
                f"fixture {result.key} "
                f"{timing_series('wall clock', [run.wall_clock for run in result.runs])}",
            )
        )
        findings.append(
            Finding(
                "INFO",
                f"fixture {result.key} "
                f"{timing_series('cpuTime', [run.cpu_time for run in result.runs])}",
            )
        )
    return findings


@dataclass(frozen=True)
class Report:
    """Every finding, and how much of the gate the run actually compared."""

    findings: list[Finding]
    compared: int
    gated: int


def run_checks(results_dir: Path, budgets_path: Path) -> Report:
    """Run every check in order and return the whole report."""
    budgets = cast(RawBudgets, json.loads(budgets_path.read_text(encoding="utf-8")))
    fixtures = budgets.get("fixtures", {})
    asked = requested_fixtures(results_dir)
    results, findings = load_results(results_dir)
    if not fixtures:
        findings.append(Finding("FAIL", f"the budget file {budgets_path} lists no fixtures"))
    unstable, reproducibility = check_reproducibility(results)
    mismatched, interpreter = check_interpreter(results, fixtures)
    unusable, provenance = check_provenance(results, fixtures)
    compared, ratchet = check_ratchet(results, budgets, unstable | mismatched | unusable)
    covers = {figure for figure in gated_figures(fixtures) if asked is None or figure[0] in asked}
    findings.extend(reproducibility)
    findings.extend(interpreter)
    findings.extend(provenance)
    findings.extend(check_coverage(compared, fixtures, asked))
    findings.extend(ratchet)
    findings.extend(check_growth(results, budgets, unstable))
    findings.extend(report_timings(results))
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
