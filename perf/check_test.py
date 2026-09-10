"""Tests for the budget checker, one per scenario of the performance capability."""

from __future__ import annotations

import contextlib
import io
import json
import tempfile
import unittest
from pathlib import Path

import check
from check import Kind

Doc = dict[str, object]
INTERPRETER = "2.35.2"


def counter_map(value: float) -> dict[str, float]:
    """Return the same measured total for every gated counter."""
    return {counter: value for counter in check.GATED_COUNTERS}


def budget_figures(value: float | None) -> dict[str, float | None]:
    """Return the same per-entry budget for every gated counter."""
    return {counter: value for counter in check.GATED_COUNTERS}


def run_doc(counters: dict[str, float], cpu: float = 0.01, wall: float = 0.1) -> Doc:
    """Build one run record in the shape measure.sh writes."""
    return {"cpuTime": cpu, "wallClock": wall, "counters": counters}


def result_doc(
    fixture: str,
    size: int | None,
    entries: int,
    runs: list[Doc],
    interpreter: str = INTERPRETER,
) -> Doc:
    """Build one result file in the shape measure.sh writes."""
    return {
        "fixture": fixture,
        "size": size,
        "interpreter": interpreter,
        "entries": entries,
        "runs": runs,
    }


def budget_doc(
    fixture: str,
    per_entry: dict[str, float | None],
    interpreter: str = INTERPRETER,
    margin: float = 0.15,
    drop: str | None = None,
) -> Doc:
    """Build one budget entry, optionally dropping one provenance field."""
    entry: Doc = {
        "fixture": fixture,
        "interpreter": interpreter,
        "date": "2026-09-04",
        "margin": margin,
        "perEntry": per_entry,
    }
    if drop is not None:
        del entry[drop]
    return entry


class CheckerTest(unittest.TestCase):
    """Every case writes a real result and budget pair into a temporary directory."""

    def setUp(self) -> None:
        holder = tempfile.TemporaryDirectory()
        self.addCleanup(holder.cleanup)
        root = Path(holder.name)
        self.results = root / "results"
        self.results.mkdir()
        self.budgets = root / "budgets.json"

    def write_result(self, name: str, doc: Doc) -> None:
        (self.results / f"{name}.json").write_text(json.dumps(doc), encoding="utf-8")

    def write_budgets(self, fixtures: dict[str, Doc], bound: float = 1.25) -> None:
        document: Doc = {
            "margin": 0.15,
            "growth": {"bound": bound, "sizes": [4, 16, 64, 256], "note": "test"},
            "fixtures": fixtures,
        }
        self.budgets.write_text(json.dumps(document), encoding="utf-8")

    def check(self) -> list[check.Finding]:
        return check.run_checks(self.results, self.budgets).findings

    def failures(self) -> list[str]:
        return [f.message for f in self.check() if f.kind == "FAIL"]

    def notes(self, kind: Kind = "INFO") -> list[str]:
        return [f.message for f in self.check() if f.kind == kind]

    def exit_code(self) -> int:
        with contextlib.redirect_stdout(io.StringIO()):
            return check.main(["--results", str(self.results), "--budgets", str(self.budgets)])

    def printed(self) -> str:
        buffer = io.StringIO()
        with contextlib.redirect_stdout(buffer):
            check.main(["--results", str(self.results), "--budgets", str(self.budgets)])
        return buffer.getvalue()

    def test_a_counter_is_not_reproducible(self) -> None:
        counters = counter_map(80)
        drifted = dict(counters)
        drifted["nrThunks"] = 81
        self.write_result(
            "worked",
            result_doc("worked", None, 8, [run_doc(counters), run_doc(drifted)]),
        )
        self.write_budgets({"worked": budget_doc("worked", budget_figures(10))})

        failures = self.failures()
        self.assertTrue(any("nrThunks" in m and "not reproducible" in m for m in failures))
        self.assertFalse([m for m in self.notes() if "per plan entry" in m])
        self.assertEqual(1, self.exit_code())

    def test_wall_clock_regresses(self) -> None:
        counters = counter_map(80)
        runs = [
            run_doc(counters, cpu=0.010, wall=0.100),
            run_doc(counters, cpu=0.011, wall=0.300),
        ]
        self.write_result("worked", result_doc("worked", None, 8, runs))
        self.write_budgets({"worked": budget_doc("worked", budget_figures(10))})

        self.assertEqual([], self.failures())
        self.assertTrue(
            any("wall clock" in m and "+0.2000s" in m for m in self.notes()),
            self.notes(),
        )
        self.assertEqual(0, self.exit_code())

    def test_the_interpreter_changes(self) -> None:
        self.write_result("worked", result_doc("worked", None, 8, [run_doc(counter_map(800))]))
        self.write_budgets(
            {"worked": budget_doc("worked", budget_figures(10), interpreter="2.34.0")}
        )

        self.assertEqual([], self.failures())
        invalid = self.notes("INVALID")
        self.assertTrue(any("2.34.0" in m and "2.35.2" in m for m in invalid), invalid)
        self.assertEqual(0, self.exit_code())

    def test_a_fixture_grows(self) -> None:
        self.write_result("worked", result_doc("worked", None, 16, [run_doc(counter_map(160))]))
        self.write_budgets({"worked": budget_doc("worked", budget_figures(10))})

        self.assertEqual([], self.failures())
        self.assertEqual(0, self.exit_code())

    def test_cost_per_entry_rises(self) -> None:
        self.write_result("worked", result_doc("worked", None, 8, [run_doc(counter_map(88))]))
        self.write_budgets({"worked": budget_doc("worked", budget_figures(10))})

        failures = self.failures()
        expected = (
            "gated counter nrThunks of fixture worked costs 11 per plan entry, "
            "above its budget of 10"
        )
        self.assertIn(expected, failures)
        self.assertEqual(1, self.exit_code())

    def test_a_budget_has_no_recorded_provenance(self) -> None:
        self.write_result("worked", result_doc("worked", None, 8, [run_doc(counter_map(80))]))
        for field in check.REQUIRED_BUDGET_FIELDS:
            with self.subTest(field=field):
                self.write_budgets({"worked": budget_doc("worked", budget_figures(10), drop=field)})
                self.assertIn(f"budget entry worked records no {field}", self.failures())
                self.assertEqual(1, self.exit_code())

    def test_an_optimisation_lands(self) -> None:
        self.write_result("worked", result_doc("worked", None, 8, [run_doc(counter_map(400))]))
        self.write_budgets({"worked": budget_doc("worked", budget_figures(100))})

        failures = self.failures()
        pasteable = [m for m in failures if '"nrThunks": 50' in m]
        self.assertTrue(pasteable, failures)
        self.assertIn("lower the budget of worked", pasteable[0])
        self.assertEqual(1, self.exit_code())

    def test_a_small_improvement(self) -> None:
        self.write_result("worked", result_doc("worked", None, 8, [run_doc(counter_map(760))]))
        self.write_budgets({"worked": budget_doc("worked", budget_figures(100))})

        self.assertEqual([], self.failures())
        self.assertTrue(any("5.0% of headroom" in m for m in self.notes()), self.notes())
        self.assertEqual(0, self.exit_code())

    def write_series(self, fixture: str, quadratic: bool, fixtures: dict[str, Doc]) -> None:
        """Write one result per size whose per-entry cost is flat or grows with size."""
        for size in (4, 16, 64, 256):
            total = size * size if quadratic else 3 * size
            self.write_result(
                f"{fixture}-{size}",
                result_doc(fixture, size, size, [run_doc(counter_map(total))]),
            )
            fixtures[f"{fixture}-{size}"] = budget_doc(fixture, budget_figures(total / size))

    def write_fleet_series(self, quadratic: bool) -> None:
        """Write the fleet series alone, which is the one-sized-fixture case."""
        fixtures: dict[str, Doc] = {}
        self.write_series("fleet", quadratic, fixtures)
        self.write_budgets(fixtures)

    def test_a_quadratic_in_set_valued_resolution(self) -> None:
        self.write_fleet_series(quadratic=True)

        failures = self.failures()
        self.assertEqual(len(check.GATED_COUNTERS), len(failures), failures)
        expected = (
            "gated counter nrThunks of fixture fleet grew by 64.000 per plan entry from size 4 "
            "to size 256, above the bound of 1.25"
        )
        self.assertIn(expected, failures)

    def test_linear_growth_passes(self) -> None:
        self.write_fleet_series(quadratic=False)

        self.assertEqual([], self.failures())
        ratios = [m for m in self.notes() if m.startswith("growth of fixture fleet at size 256")]
        self.assertTrue(ratios, self.notes())
        self.assertIn("nrThunks=1.000", ratios[0])
        self.assertEqual(3, len([m for m in self.notes() if m.startswith("growth of fixture")]))
        self.assertEqual(0, self.exit_code())

    def test_one_fixture_grows_and_another_does_not(self) -> None:
        fixtures: dict[str, Doc] = {}
        self.write_series("fleet", quadratic=False, fixtures=fixtures)
        self.write_series("mesh", quadratic=True, fixtures=fixtures)
        self.write_budgets(fixtures)

        failures = self.failures()
        self.assertEqual(len(check.GATED_COUNTERS), len(failures), failures)
        self.assertTrue(all("of fixture mesh grew by" in m for m in failures), failures)
        self.assertEqual(1, self.exit_code())

    def test_a_sized_fixture_measured_once_is_reported(self) -> None:
        self.write_result("mesh-4", result_doc("mesh", 4, 9, [run_doc(counter_map(90))]))
        self.write_budgets({"mesh-4": budget_doc("mesh", budget_figures(10))})

        self.assertEqual([], self.failures())
        self.assertTrue(
            any("two comparable sizes of fixture mesh" in m for m in self.notes()), self.notes()
        )
        self.assertEqual(0, self.exit_code())

    def test_a_budget_figure_is_null(self) -> None:
        self.write_result("worked", result_doc("worked", None, 8, [run_doc(counter_map(80))]))
        figures = budget_figures(10)
        figures["sets.bytes"] = None
        self.write_budgets({"worked": budget_doc("worked", figures)})

        failures = self.failures()
        self.assertTrue(
            any(
                "budget figure not recorded" in m and "entry worked, field sets.bytes" in m
                for m in failures
            ),
            failures,
        )
        self.assertEqual(1, self.exit_code())

    def test_a_measurement_is_absent(self) -> None:
        """A budget the run measured nothing for is a failure, not a silent pass."""
        self.write_result("worked", result_doc("worked", None, 8, [run_doc(counter_map(80))]))
        self.write_budgets(
            {
                "worked": budget_doc("worked", budget_figures(10)),
                "fleet-4": budget_doc("fleet", budget_figures(10)),
                "fleet-16": budget_doc("fleet", budget_figures(10)),
            }
        )

        failures = self.failures()
        self.assertTrue(any("fixture fleet-4" in m for m in failures), failures)
        self.assertTrue(any("fixture fleet-16" in m for m in failures), failures)
        self.assertFalse(any("fixture worked" in m for m in failures), failures)
        self.assertEqual(1, self.exit_code())

    def test_every_gated_figure_was_measured(self) -> None:
        """A run that compared the whole gate says how much of it that was."""
        self.write_result("worked", result_doc("worked", None, 8, [run_doc(counter_map(80))]))
        self.write_result("mesh-4", result_doc("mesh", 4, 9, [run_doc(counter_map(90))]))
        self.write_budgets(
            {
                "worked": budget_doc("worked", budget_figures(10)),
                "mesh-4": budget_doc("mesh", budget_figures(10)),
            }
        )

        report = check.run_checks(self.results, self.budgets)
        self.assertEqual([], self.failures())
        self.assertEqual(2 * len(check.GATED_COUNTERS), report.gated)
        self.assertEqual(report.gated, report.compared)
        self.assertIn(
            f"{report.compared} of {report.gated} gated figures compared", self.printed()
        )
        self.assertEqual(0, self.exit_code())


if __name__ == "__main__":
    unittest.main()
