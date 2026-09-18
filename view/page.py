"""The page the view renders, out of the documents it serves.

Every position in the picture is a coordinate the layout computed, so this
module places what it is handed and decides nothing: two renders of one build
are byte-equal because nothing here reads a clock, a directory or an
environment.

The page carries no script and references one asset, the stylesheet the view
serves itself. A reader who wants a machine changed runs the command; the page
says so rather than offering a button, because an apply is a walk whose
recovery is running it again and a button would need a job model.
"""

from __future__ import annotations

from html import escape
from typing import Any

import routes

STYLESHEET = """
:root { color-scheme: light dark; }
body { font: 14px/1.5 system-ui, sans-serif; margin: 2rem; max-width: 76rem; }
h1 { font-size: 1.4rem; } h2 { font-size: 1.1rem; margin-top: 2rem; }
table { border-collapse: collapse; width: 100%; margin: 0.5rem 0 1.5rem; }
th, td { border: 1px solid #8884; padding: 0.3rem 0.5rem; text-align: left;
  vertical-align: top; font-variant-numeric: tabular-nums; }
th { font-weight: 600; background: #8881; }
code, .key { font-family: ui-monospace, monospace; }
.note { color: #8a8a8a; }
.error { color: #b3261e; font-weight: 600; }
.cell { fill: #8881; stroke: #8886; }
.cell.value { stroke-dasharray: 4 3; }
.edge { fill: none; stroke: #6a6a6a; }
.edge.contradicted { stroke: #b3261e; stroke-dasharray: 5 4; }
.label { font: 11px ui-monospace, monospace; fill: #8a8a8a; }
.boxed { font: 12px ui-monospace, monospace; }
svg { max-width: 100%; height: auto; border: 1px solid #8884; }
""".strip()


def page(target: str, documents: dict[str, Any]) -> str:
    """Return the whole page for one build.

    Args:
        target: What the view was started against, as it resolved.
        documents: The machines, values, graph and diagnostics documents.

    Returns:
        The page, as HTML: the build and what it realised, the machines with
        their entries and units, the graph as inline SVG placed from the
        computed coordinates, the values with their delivery sets, and every
        diagnostics row with all six of its fields.
    """
    diagnostics = documents["diagnostics"]
    body = [
        f"<h1>{escape(target)}</h1>",
        f"<p>{escape(diagnostics['statement'])}. "
        f"This view reads a build and changes nothing: an apply, a retirement and a rollback "
        f"are the operator's command. "
        f'<a href="{routes.LIVE}">What the machines hold now</a> asks them when you ask.</p>',
        _machines(documents["machines"]),
        _graph(documents["graph"]),
        _values(documents["values"]),
        _diagnostics(diagnostics),
        _served(),
    ]
    return _document("A deployment", body)


def live(target: str, answered: dict[str, Any]) -> str:
    """Return the page for what the machines answered, and when.

    Args:
        target: What the view was started against, as it resolved.
        answered: The live document, as `live.answers` returns it.

    Returns:
        The page, as HTML: every record the machine report answered with, the
        machines it could not ask, and the time the questions were put.
    """
    body = [
        f"<h1>{escape(target)}</h1>",
        f"<p>Asked at {escape(answered['taken'])}, because you asked. "
        f'Nothing here polls and nothing here changes a machine. <a href="{routes.PAGE}">'
        f"The build</a> is answered with no machine asked.</p>",
        _unasked(answered["unasked"]),
        _answers(answered["answers"]),
        _served(),
    ]
    return _document("What the machines hold", body)


def _document(title: str, body: list[str]) -> str:
    """Return one page, with the head every page carries."""
    return "\n".join(
        [
            "<!DOCTYPE html>",
            '<html lang="en">',
            "<head>",
            '<meta charset="utf-8">',
            f"<title>{escape(title)}</title>",
            f'<link rel="stylesheet" href="{routes.STYLE}">',
            "</head>",
            "<body>",
            *body,
            "</body>",
            "</html>",
            "",
        ]
    )


def _table(headings: list[str], rows: list[list[str]]) -> str:
    """Return one table, its cells escaped."""
    head = "".join(f"<th>{escape(heading)}</th>" for heading in headings)
    body = "".join(
        "<tr>" + "".join(f"<td>{escape(cell)}</td>" for cell in row) + "</tr>" for row in rows
    )
    return f"<table><thead><tr>{head}</tr></thead><tbody>{body}</tbody></table>"


def _machines(document: dict[str, Any]) -> str:
    """Return the machines and the entries placed on each."""
    parts = ["<h2>Machines</h2>"]
    for machine in document["machines"]:
        parts.append(
            f'<h3 class="key">{escape(machine["name"])}</h3>'
            f'<p class="note">{escape(_sealing(machine))}</p>'
        )
        parts.append(
            _table(
                ["entry", "realiser", "profile", "digest", "artifact", "units"],
                [
                    [
                        entry["key"],
                        entry["realiser"],
                        entry["profile"] or "none",
                        entry["digest"],
                        entry["artifact"] or "no artifact",
                        " ".join(entry["units"]) or "none",
                    ]
                    for entry in machine["entries"]
                ],
            )
        )
    return "\n".join(parts)


def _sealing(machine: dict[str, Any]) -> str:
    """Return what the build recorded about one machine, in a sentence."""
    sealed = machine["sealed"]
    said = (
        "values sealed to its own recipient"
        if sealed
        else "values not sealed"
        if sealed is False
        else "no value delivered here, so the build records no sealing"
    )
    return f"{machine['address'] or 'no address'}, {machine['scope']} scope, {said}"


def _graph(document: dict[str, Any]) -> str:
    """Return the graph as inline SVG, placed from the computed coordinates."""
    at = {cell["key"]: cell for cell in document["cells"]}
    edges = "".join(
        f'<path class="edge{" contradicted" if edge["contradicted"] else ""}" '
        f'd="{escape(edge["path"])}"/>'
        f'<text class="label" x="{edge["labelX"]}" y="{edge["labelY"]}">'
        f"{escape(edge['slot'])}</text>"
        for edge in document["edges"]
        if edge["provider"] in at and edge["consumer"] in at
    )
    cells = "".join(
        f'<g><rect class="cell {cell["kind"]}" x="{cell["x"]}" y="{cell["y"]}" '
        f'width="{cell["width"]}" height="{cell["height"]}" rx="6"/>'
        f'<text class="boxed" x="{cell["x"] + 8}" y="{cell["y"] + 22}">'
        f"{escape(cell['key'])}</text>"
        f'<text class="label" x="{cell["x"] + 8}" y="{cell["y"] + 40}">'
        f"{escape(cell['machine'] or cell['kind'])}</text></g>"
        for cell in document["cells"]
    )
    return "\n".join(
        [
            "<h2>The typed edges between entries</h2>",
            '<p class="note">A column is dependency depth, the index of the strong component in '
            "the order the command applies in; a row is plan key order within the column; a "
            "dashed red edge is one that order had to contradict.</p>",
            f'<svg viewBox="0 0 {document["width"]} {document["height"]}" '
            f'width="{document["width"]}" height="{document["height"]}" '
            f'xmlns="http://www.w3.org/2000/svg">{edges}{cells}</svg>',
            _unrecognised(document["unrecognised"]),
        ]
    )


def _unrecognised(named: list[dict[str, Any]]) -> str:
    """Return the reads recorded in a shape the view does not know."""
    if not named:
        return ""
    return "<h3>Reads the view does not recognise</h3>" + _table(
        ["consumer", "slot", "what the reading said"],
        [[one["consumer"], one["slot"], one["said"]] for one in named],
    )


def _values(document: dict[str, Any]) -> str:
    """Return the values, their delivery sets and their files."""
    rows = [
        [
            value["key"],
            " ".join(value["delivery"]) or "delivered nowhere",
            file["name"],
            file["path"],
            file["secrecy"],
            f"{file['owner']}:{file['group']} {file['mode']}",
        ]
        for value in document["values"]
        for file in value["files"]
    ]
    return (
        "<h2>Generated values</h2>"
        '<p class="note">A path and never a byte: the plan carries where a value goes and the '
        "machines carry what it is.</p>"
        + _table(["value", "delivered to", "file", "path", "secrecy", "as"], rows)
    )


def _diagnostics(document: dict[str, Any]) -> str:
    """Return every row of the build with all six of its fields."""
    rows = [
        [
            row["id"],
            row["subject"],
            row["severity"],
            row["message"],
            row["evidence"],
            row["resolution"],
        ]
        for row in document["rows"]
    ]
    return "<h2>Diagnostics</h2>" + _table(
        ["identifier", "subject", "severity", "message", "evidence", "resolution"], rows
    )


def _unasked(machines: list[str]) -> str:
    """Return the machines the questions could not be put to."""
    if not machines:
        return '<p class="note">Every machine of this build answered.</p>'
    return (
        f'<p class="error">Unasked: {escape(" ".join(machines))}. '
        f"A machine that answered nothing holds nothing this view can state.</p>"
    )


def _answers(answered: list[dict[str, Any]]) -> str:
    """Return the records the report answered with, one row each."""
    rows = [
        [
            answer["kind"],
            str(answer["record"].get("machine", "")),
            str(answer["record"].get("key", "")),
            " ".join(answer["lines"]),
        ]
        for answer in answered
    ]
    return "<h2>What the machines hold</h2>" + _table(
        ["about", "machine", "key", "what it answered"], rows
    )


def _served() -> str:
    """Return the routes the view answers, named as routes."""
    return (
        '<h2>Routes</h2><p class="note">'
        + ", ".join(f"<code>{escape(route)}</code>" for route in routes.ALL)
        + ". No route writes anywhere.</p>"
    )
