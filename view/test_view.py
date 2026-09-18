"""The view's own tests, over built deployments fabricated on disk.

A build is a directory holding `plan.json`, `manifest.json`, `diagnostics.json`,
`diagnostics.txt` and one artifact link per placed entry, read back through the
command's own reader, so what these assertions are handed and what a folder's
build produces are the same interface. No test here runs nix and none dials a
machine: the live half is handed a recorder, which is what makes the questions
it puts assertable at all.

What is smoke and is not asserted here: that a reader finds the picture
legible. A pytest layer can assert that an edge's path element runs between two
cells and that two renders of one build are byte-equal; whether a human
understands the drawing is observed by opening it, and this file covers none of
that.
"""

from __future__ import annotations

import json
import shutil
import socket
import threading
import urllib.request
from datetime import datetime
from html.parser import HTMLParser
from pathlib import Path
from typing import Any

import pytest

import documents
import errors
import graph
import manifest
import page
import remote
import report
import routes
import server

SERVER = "site:server@alpha"
CLIENT = "check:client@beta"
SILENT = "check:client@gamma"
VALUE = "issuer:vars/session"
TOKEN = "/run/vars/issuer/session/token"
SEALED = "/var/lib/planner/sealed/issuer/session/token.age"
PUBLISHED = "sha256-3333333333333333"
REALISERS: dict[str, Any] = {
    "flakelet": {"holdings": {"urlPrefix": "plan:"}, "scopes": ["system"]},
    "image": {
        "holdings": {
            "digestAlphabet": "0123456789abcdef",
            "digestLength": 16,
            "separator": "_",
        },
        "scopes": ["system", "user"],
    },
}


def _wire(provider: str) -> dict[str, Any]:
    """One resolved read naming one provider, the shape a `reach = "one"` read has."""
    return {
        "delivered": True,
        "entry": provider,
        "reach": "one",
        "reads": ["url"],
        "values": {"url": "ssh://borg@vault.example:22/srv/borg"},
        "wire": {"instance": "site", "provides": "repo"},
    }


def _plan() -> dict[str, Any]:
    """The plan of the build every test below is shown, unless it states its own."""
    return {
        "machine:alpha": {"address": "10.0.0.10", "tags": ["cluster"]},
        "machine:beta": {"address": "10.0.0.11", "tags": ["cluster"], "scope": "user"},
        SERVER: {"key": PUBLISHED, "placement": {"machine": "alpha"}},
        CLIENT: {
            "key": PUBLISHED,
            "placement": {"machine": "beta"},
            "reads": {
                "repo": _wire(SERVER),
                "token": {
                    "delivered": True,
                    "entry": SERVER,
                    "reach": "one",
                    "reads": ["token"],
                    "values": {"token": {"path": TOKEN}},
                    "wire": {"instance": "issuer", "provides": "secret"},
                },
            },
        },
        VALUE: {
            "per": "instance",
            "delivery": ["alpha", "beta"],
            "files": {
                "token": {
                    "path": TOKEN,
                    "sealed": SEALED,
                    "secrecy": "secret",
                    "owner": "root",
                    "group": "root",
                    "mode": "0400",
                }
            },
        },
    }


def _entry(key: str, machine: str, address: str, *, realised: bool = True) -> dict[str, Any]:
    """One placed entry as a manifest states it, holding no artifact where it was realised
    into none."""
    instance, service = key.split("@")[0].split(":")
    stated: dict[str, Any] = {
        "realiser": "flakelet",
        "profile": None,
        "machine": machine,
        "address": address,
        "units": [f"{instance}-{service}-serve.service"] if realised else [],
        "key": PUBLISHED,
    }
    if realised:
        stated["path"] = f"entries/{instance}-{service}-{machine}"
    return stated


def _built(
    root: Path,
    *,
    plan: dict[str, Any] | None = None,
    entries: dict[str, dict[str, Any]] | None = None,
    values: dict[str, dict[str, Any]] | None = None,
    machines: dict[str, Any] | None = None,
    rows: list[dict[str, str]] | None = None,
    table: str = "",
) -> manifest.Deployment:
    """Write a built deployment at ``root`` and read it back as the command does."""
    held = _plan() if plan is None else plan
    placed = (
        {
            SERVER: _entry(SERVER, "alpha", "10.0.0.10"),
            CLIENT: _entry(CLIENT, "beta", "10.0.0.11"),
        }
        if entries is None
        else entries
    )
    delivered = (
        {VALUE: {"delivery": ["alpha", "beta"], "files": held[VALUE]["files"]}}
        if values is None and VALUE in held
        else (values or {})
    )
    root.mkdir(parents=True, exist_ok=True)
    (root / "plan.json").write_text(json.dumps(held))
    (root / "manifest.json").write_text(
        json.dumps(
            {
                "version": manifest.VERSION,
                "storeDir": "/nix/store",
                "entries": placed,
                "values": delivered,
                "machines": (
                    {"alpha": {"sealed": False, "scope": "system"}}
                    if machines is None
                    else machines
                ),
                "realisers": REALISERS,
            }
        )
    )
    (root / "diagnostics.json").write_text(json.dumps(rows or []))
    (root / "diagnostics.txt").write_text(table)
    for key, stated in placed.items():
        if "path" not in stated:
            continue
        artifact = root / "artifacts" / Path(stated["path"]).name
        (artifact / "units").mkdir(parents=True)
        instance, service = key.split("@")[0].split(":")
        (artifact / "meta.json").write_text(json.dumps({"name": f"{instance}-{service}"}))
        for unit in stated.get("units", []):
            (artifact / "units" / unit).write_text(f"[Unit]\nDescription={unit}\n")
        link = root / stated["path"]
        link.parent.mkdir(parents=True, exist_ok=True)
        link.symlink_to(artifact)
    return manifest.read(root)


class Recorder:
    """A runner recording the argv it was handed and answering as a machine would.

    ``silent`` names the addresses that answer nothing, which is a machine that
    could not be asked rather than a machine holding nothing. The payload of a
    step is dropped: a recorder keeping the bytes of a value would be a copy of
    the leak the argv does not carry.
    """

    def __init__(self, silent: tuple[str, ...] = ()) -> None:
        self.commands: list[list[str]] = []
        self.silent = silent

    def run(
        self, cmd: list[str], *, env: dict[str, str] | None = None, stdin: bytes | None = None
    ) -> object:
        self.commands.append(cmd)
        return env

    def output(
        self, cmd: list[str], *, env: dict[str, str] | None = None, stdin: bytes | None = None
    ) -> str:
        self.commands.append(cmd)
        asked = cmd[-1]
        if any(address in " ".join(cmd) for address in self.silent):
            raise remote.Refused(remote.destination(cmd), remote.UNREACHABLE, "")
        if remote.HELD in asked:
            return ""
        if "flakelet status" in asked:
            return json.dumps(
                [
                    {
                        "name": "site-server",
                        "generation": 3,
                        "units": {},
                        "locked_url": f"plan:{SERVER}",
                        "state": "running",
                        "last_error": None,
                    }
                ]
            )
        return f"{TOKEN}=present\n"


def _view(root: Path, *, recorder: Recorder | None = None, **built: Any) -> server.View:
    """A view over one fabricated build, with a recorder in place of the machines."""
    return server.View(deployment=_built(root, **built), runner=recorder or Recorder(), base_env={})


def _recorded(view: server.View) -> Recorder:
    """The recorder one view asks over, which is what a test reads the argv off."""
    runner = view.runner
    assert isinstance(runner, Recorder)
    return runner


def _document(view: server.View, route: str) -> dict[str, Any]:
    """The JSON one route answers with, decoded."""
    answered = view.answer(route)
    assert answered.status == 200, answered.body
    assert answered.kind == server.JSON
    decoded: dict[str, Any] = json.loads(answered.body)
    return decoded


class Page(HTMLParser):
    """The served page, as tags, attributes and text, read with the standard library."""

    def __init__(self) -> None:
        super().__init__()
        self.tags: list[str] = []
        self.assets: list[str] = []
        self.text = ""

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        self.tags.append(tag)
        named = dict(attrs)
        for attribute in ("src", "href"):
            asset = named.get(attribute)
            if asset is not None and tag != "a":
                self.assets.append(asset)

    def handle_data(self, data: str) -> None:
        self.text += data


def _parsed(body: bytes) -> Page:
    """The page, parsed."""
    read = Page()
    read.feed(body.decode())
    return read


def test_a_built_deployment_is_shown_with_no_machine_asked(tmp_path: Path) -> None:
    """Every static route answers the build's own facts, and no machine is dialled."""
    recorder = Recorder()
    view = _view(tmp_path / "built", recorder=recorder)

    machines = _document(view, routes.MACHINES)
    values = _document(view, routes.VALUES)
    drawn = _document(view, routes.GRAPH)
    rows = _document(view, routes.DIAGNOSTICS)

    assert [machine["name"] for machine in machines["machines"]] == ["alpha", "beta"]
    assert [entry["key"] for machine in machines["machines"] for entry in machine["entries"]] == [
        SERVER,
        CLIENT,
    ]
    assert machines["machines"][0]["entries"][0]["units"] == ["site-server-serve.service"]
    assert [value["key"] for value in values["values"]] == [VALUE]
    assert {cell["key"] for cell in drawn["cells"]} == {SERVER, CLIENT, VALUE}
    assert rows["rows"] == []
    assert view.answer(routes.PAGE).status == 200
    assert recorder.commands == []


def test_a_route_is_asked_while_nothing_can_build_or_dial(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """With no nix and no ssh on the path, every static route still answers."""
    empty = tmp_path / "empty"
    empty.mkdir()
    view = _view(tmp_path / "built")
    monkeypatch.setenv("PATH", str(empty))
    assert shutil.which("nix") is None
    assert shutil.which("ssh") is None

    for route in routes.STATIC:
        answered = view.answer(route)
        assert answered.status == 200, route
        assert answered.body

    assert SERVER.encode() in view.answer(routes.PAGE).body


def test_every_placed_entry_appears_under_the_machine_it_is_placed_on(tmp_path: Path) -> None:
    """Each machine carries its own entries in plan key order, with every field."""
    view = _view(
        tmp_path / "built",
        entries={
            CLIENT: _entry(CLIENT, "beta", "10.0.0.11"),
            SERVER: _entry(SERVER, "alpha", "10.0.0.10"),
            "site:extra@alpha": _entry("site:extra@alpha", "alpha", "10.0.0.10"),
        },
    )

    machines = _document(view, routes.MACHINES)["machines"]

    placed = {
        machine["name"]: [entry["key"] for entry in machine["entries"]] for machine in machines
    }
    assert placed == {"alpha": ["site:extra@alpha", SERVER], "beta": [CLIENT]}
    entry = machines[0]["entries"][1]
    assert entry["realiser"] == "flakelet"
    assert entry["units"] == ["site-server-serve.service"]
    assert entry["digest"] == PUBLISHED
    assert entry["artifact"].endswith("artifacts/site-server-alpha")
    assert machines[1]["scope"] == "user"


def test_a_value_is_shown_with_its_delivery_set_and_its_files(tmp_path: Path) -> None:
    """A value shows both machines, every file's record, and no content."""
    view = _view(tmp_path / "built")

    values = _document(view, routes.VALUES)["values"]

    assert [value["delivery"] for value in values] == [["alpha", "beta"]]
    assert values[0]["files"] == [
        {
            "name": "token",
            "path": TOKEN,
            "sealed": SEALED,
            "secrecy": "secret",
            "owner": "root",
            "group": "root",
            "mode": "0400",
        }
    ]
    assert "content" not in json.dumps(values)


def test_an_entry_realised_into_nothing_is_shown_as_holding_no_artifact(tmp_path: Path) -> None:
    """An entry declaring no unit appears, holding no artifact rather than an empty path."""
    view = _view(
        tmp_path / "built",
        entries={
            SERVER: _entry(SERVER, "alpha", "10.0.0.10"),
            CLIENT: _entry(CLIENT, "beta", "10.0.0.11", realised=False),
        },
    )

    machines = _document(view, routes.MACHINES)["machines"]

    unrealised = next(
        entry for machine in machines for entry in machine["entries"] if entry["key"] == CLIENT
    )
    assert unrealised["artifact"] is None
    assert unrealised["realised"] is False
    assert b"no artifact" in view.answer(routes.PAGE).body


def test_a_single_valued_read_is_one_edge_from_its_provider(tmp_path: Path) -> None:
    """A read naming one provider is one labelled edge from that provider."""
    view = _view(tmp_path / "built")

    drawn = _document(view, routes.GRAPH)

    between = [
        (edge["provider"], edge["consumer"], edge["slot"])
        for edge in drawn["edges"]
        if edge["provider"] == SERVER
    ]
    assert between == [(SERVER, CLIENT, "repo"), (SERVER, CLIENT, "token")]
    assert drawn["unrecognised"] == []


def test_a_read_of_every_provider_is_one_edge_per_provider(tmp_path: Path) -> None:
    """A read of every provider of a capability is one edge per provider named."""
    providers = ["site:server@alpha", "site:server@beta", "site:server@gamma"]
    plan = {
        "machine:alpha": {"address": "10.0.0.10"},
        "check:client@delta": {
            "key": PUBLISHED,
            "placement": {"machine": "delta"},
            "reads": {
                "clients": {
                    "delivered": True,
                    "reach": "all",
                    "reads": ["publicKey"],
                    "entries": {key: {"publicKey": key} for key in providers},
                }
            },
        },
        **{
            key: {"key": PUBLISHED, "placement": {"machine": key.split("@")[1]}}
            for key in providers
        },
    }
    entries = {key: _entry(key, key.split("@")[1], "10.0.0.10") for key in providers}
    entries["check:client@delta"] = _entry("check:client@delta", "delta", "10.0.0.13")
    view = _view(tmp_path / "built", plan=plan, entries=entries, values={})

    drawn = _document(view, routes.GRAPH)

    into = [
        (edge["provider"], edge["slot"])
        for edge in drawn["edges"]
        if edge["consumer"] == "check:client@delta"
    ]
    assert into == [(key, "clients") for key in providers]


def test_a_read_recorded_in_a_shape_the_view_does_not_know_is_named(tmp_path: Path) -> None:
    """A read in neither shape names its consumer and its slot instead of vanishing."""
    plan = _plan()
    plan[CLIENT]["reads"]["mystery"] = {"delivered": True, "provider": SERVER}
    view = _view(tmp_path / "built", plan=plan)

    drawn = _document(view, routes.GRAPH)

    assert [(one["consumer"], one["slot"]) for one in drawn["unrecognised"]] == [
        (CLIENT, "mystery")
    ]
    assert "mystery" in drawn["unrecognised"][0]["said"]
    # The slots beside it are still read, so one unreadable record is not a
    # consumer that reads nothing.
    assert {edge["slot"] for edge in drawn["edges"] if edge["consumer"] == CLIENT} == {
        "repo",
        "token",
    }
    assert b"mystery" in view.answer(routes.PAGE).body


def test_one_deployment_renders_one_page(tmp_path: Path) -> None:
    """Two showings of one build are identical, and every position is the build's own."""
    view = _view(tmp_path / "built")

    first = view.answer(routes.PAGE).body
    second = view.answer(routes.PAGE).body

    assert first == second
    drawn = _document(view, routes.GRAPH)
    for cell in drawn["cells"]:
        assert cell["x"] == graph.MARGIN + cell["column"] * (graph.CELL_WIDTH + graph.COLUMN_GAP)
        assert cell["y"] == graph.MARGIN + cell["row"] * (graph.CELL_HEIGHT + graph.ROW_GAP)
    # x is dependency depth and y is plan key order within the column: the value
    # is written before its readers, and the provider is applied before them.
    at = {cell["key"]: cell["column"] for cell in drawn["cells"]}
    assert at[VALUE] < at[CLIENT]
    assert at[SERVER] < at[CLIENT]
    assert drawn["cycles"] == []
    for column in drawn["columns"]:
        assert column == sorted(column)


def test_a_page_carries_no_script_and_no_asset_it_did_not_serve(tmp_path: Path) -> None:
    """The page carries no script, and every asset it names is a route the view answers."""
    view = _view(tmp_path / "built")

    read = _parsed(view.answer(routes.PAGE).body)

    assert "script" not in read.tags
    assert read.assets == [routes.STYLE]
    for asset in read.assets:
        assert view.answer(asset).status == 200
    for named in (SERVER, CLIENT, VALUE, "site-server-serve.service", TOKEN):
        assert named in read.text, named
    drawn = _document(view, routes.GRAPH)
    body = view.answer(routes.PAGE).body.decode()
    for edge in drawn["edges"]:
        assert edge["path"] in body


def test_a_row_is_shown_with_its_evidence_and_its_resolution(tmp_path: Path) -> None:
    """A row is shown with all six fields, and the two are the strings the build recorded."""
    row = {
        "id": "entry-config-file-unreadable-by-user",
        "subject": SERVER,
        "severity": "warning",
        "message": "the unit cannot open the file it is shown",
        "evidence": "declared owner root:root at 0400, unit runs as nobody",
        "resolution": "state an ownership the unit's account admits",
    }
    view = _view(tmp_path / "built", rows=[row], table="warning site:server@alpha unreadable")

    shown = _document(view, routes.DIAGNOSTICS)

    assert shown["rows"] == [row]
    text = _parsed(view.answer(routes.PAGE).body).text
    for field in row.values():
        assert field in text, field


def test_a_deployment_the_planner_refused_shows_its_rows_and_no_artifact(tmp_path: Path) -> None:
    """A refused build is shown: its rows, and the statement that no entry was realised."""
    row = {
        "id": "slot-unwired",
        "subject": CLIENT,
        "severity": "error",
        "message": "the slot repo is unwired",
        "evidence": "no wire names it",
        "resolution": "wire the slot in the composing root",
    }
    view = _view(tmp_path / "built", entries={}, values={}, rows=[row], table="error unwired")

    shown = _document(view, routes.DIAGNOSTICS)

    assert shown["rows"] == [row]
    assert shown["refused"] is True
    assert shown["realised"] == 0
    assert "no entry was realised" in shown["statement"]
    answered = view.answer(routes.PAGE)
    assert answered.status == 200
    assert "no entry was realised" in _parsed(answered.body).text


def test_the_live_view_asks_the_questions_the_report_asks(tmp_path: Path) -> None:
    """The argv the live route produces are the report's own, one question per machine."""
    view = _view(tmp_path / "built")
    asking = Recorder()

    answered = _document(view, routes.LIVE_DOCUMENT)
    report.status(view.deployment, asking, base_env={})

    assert _recorded(view).commands == asking.commands
    held = [cmd for cmd in _recorded(view).commands if remote.HELD in cmd[-1]]
    assert len(held) == len({cmd[-2] for cmd in held}) == 2
    assert [answer["kind"] for answer in answered["answers"]].count("entry") == 2
    assert answered["unasked"] == []
    # The record and never a parsed sentence: the fields are the report's own.
    entry = next(answer for answer in answered["answers"] if answer["kind"] == "entry")
    assert entry["record"]["reached"] == report.ANSWERED
    assert entry["record"]["generation"] == 3


def test_a_machine_that_answered_nothing_is_shown_as_unasked(tmp_path: Path) -> None:
    """One machine answering nothing is unasked, and the others' answers are shown."""
    view = _view(tmp_path / "built", recorder=Recorder(silent=("10.0.0.11",)))

    answered = _document(view, routes.LIVE_DOCUMENT)

    assert answered["unasked"] == ["beta"]
    reached = {
        answer["record"]["machine"]: answer["record"]["reached"]
        for answer in answered["answers"]
        if answer["kind"] == "entry"
    }
    assert reached == {"alpha": report.ANSWERED, "beta": report.UNREACHED}
    assert b"beta" in view.answer(routes.LIVE).body


def test_a_live_answer_carries_when_it_was_taken(tmp_path: Path) -> None:
    """The answer carries the moment it was taken, and nothing was asked before."""
    view = _view(tmp_path / "built")
    assert _recorded(view).commands == []

    answered = _document(view, routes.LIVE_DOCUMENT)

    taken = datetime.fromisoformat(answered["taken"])
    assert taken.tzinfo is not None
    assert _recorded(view).commands != []
    asked = len(_recorded(view).commands)
    _document(view, routes.LIVE_DOCUMENT)
    assert len(_recorded(view).commands) == 2 * asked
    assert answered["taken"] in _parsed(view.answer(routes.LIVE).body).text


def test_no_route_of_the_view_changes_a_machine_or_the_build(tmp_path: Path) -> None:
    """Every route is a reading: no write, and no method that could be anything else."""
    root = tmp_path / "built"
    view = _view(root)
    before = _digest(root)

    with _serving(view) as at:
        for route in routes.ALL:
            with urllib.request.urlopen(f"{at}{route}") as answered:
                assert answered.status == 200, route
        for method in ("POST", "PUT", "PATCH", "DELETE"):
            assert _status(at, routes.PAGE, method) == 405
        assert _status(at, "/apply", "GET") == 404

    assert _digest(root) == before
    for cmd in _recorded(view).commands:
        said = " ".join(cmd)
        for verb in ("nix copy", "flakelet deploy", "flakelet remove", "portablectl attach"):
            assert verb not in said, said
        for verb in ("portablectl detach", "systemctl start", "rollback", "cat >"):
            assert verb not in said, said


def test_a_view_asked_to_listen_beyond_the_loopback_interface_is_refused(tmp_path: Path) -> None:
    """An address that is not the loopback one is refused, and nothing is bound."""
    view = _view(tmp_path / "built")
    port = _free_port()

    with pytest.raises(errors.ApplyError) as raised:
        server.serving(view, host="0.0.0.0", port=port)

    assert "loopback" in str(raised.value)
    assert "network" in str(raised.value)
    with socket.socket() as probe:
        probe.settimeout(1)
        assert probe.connect_ex(("127.0.0.1", port)) != 0


def test_the_documents_answer_with_no_second_reading(tmp_path: Path) -> None:
    """Each document is the one function of the build the server serves, not a copy."""
    deployment = _built(tmp_path / "built")
    view = server.View(deployment=deployment, runner=Recorder(), base_env={})

    assert _document(view, routes.MACHINES) == documents.machines(deployment)
    assert _document(view, routes.VALUES) == documents.values(deployment)
    assert _document(view, routes.GRAPH) == graph.graph(deployment)
    assert _document(view, routes.DIAGNOSTICS) == documents.diagnostics(deployment)
    assert page.page(view.target, view.static) == page.page(view.target, view.static)


def _digest(root: Path) -> list[tuple[str, int]]:
    """Every file under one build, by path and size, to compare a tree with itself."""
    return sorted(
        (str(path.relative_to(root)), path.stat().st_size)
        for path in root.rglob("*")
        if path.is_file()
    )


def _free_port() -> int:
    """A port nothing is listening on, released before it is returned."""
    with socket.socket() as held:
        held.bind(("127.0.0.1", 0))
        return int(held.getsockname()[1])


class _Serving:
    """A real server on the loopback interface, for the length of one block."""

    def __init__(self, view: server.View) -> None:
        self.view = view

    def __enter__(self) -> str:
        self.server = server.serving(self.view, port=0)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        host, port = self.server.server_address[:2]
        return f"http://{host!s}:{port!s}"

    def __exit__(self, *raised: object) -> None:
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=5)


def _serving(view: server.View) -> _Serving:
    return _Serving(view)


def _status(at: str, route: str, method: str) -> int:
    """The status one method against one route answers with."""
    request = urllib.request.Request(f"{at}{route}", method=method, data=b"")
    try:
        with urllib.request.urlopen(request) as answered:
            return int(answered.status)
    except urllib.error.HTTPError as refused:
        return int(refused.code)
