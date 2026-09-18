"""The view's server: the routes, the startup and the program.

The target is resolved once, before the port is open, through the command's
own `manifest.resolve`, so a flake reference builds in the foreground where
the operator can see it and no request of the view is ever a build. Every
static route then answers out of the deployment read at startup: no route runs
nix, no route dials a machine, and the one route that asks the machines asks
through the machine report when a reader asks for it.

Nothing the view accepts writes anywhere. It answers `GET` and `HEAD` and
refuses every other method, it binds the loopback interface, and an
instruction to listen anywhere else is refused: an unauthenticated picture of
a fleet's live state is not a surface to publish on a network.
"""

from __future__ import annotations

import argparse
import json
import sys
from collections.abc import Mapping
from dataclasses import dataclass
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any

import documents
import graph
import live
import manifest
import page
import remote
import routes
from errors import ApplyError
from manifest import Deployment

LOOPBACK = ("127.0.0.1", "::1", "localhost")
HOST = "127.0.0.1"
PORT = 8099
JSON = "application/json; charset=utf-8"
HTML = "text/html; charset=utf-8"
CSS = "text/css; charset=utf-8"
READ_ONLY = "the view reads a build and changes nothing, so it answers GET only"
PUBLISHED = (
    "the view binds the loopback interface, because an unauthenticated picture of a fleet's "
    "live state is not a surface to publish on a network"
)
DOCUMENTS = {
    routes.MACHINES: "machines",
    routes.VALUES: "values",
    routes.GRAPH: "graph",
    routes.DIAGNOSTICS: "diagnostics",
}


@dataclass(frozen=True)
class Answered:
    """One answered request: its status, its content type and its bytes."""

    status: int
    kind: str
    body: bytes


@dataclass(frozen=True)
class View:
    """A built deployment, read once, and the channel the live route asks over.

    The deployment is the one resolved before the port was opened, so every
    static route is a function of it and of nothing a request carries. The
    runner is what the live route asks with, which is the command's own
    channel for an operator and a recorder for a test.
    """

    deployment: Deployment
    runner: remote.Runner
    ssh_key: Path | None = None
    user: str = "root"
    base_env: Mapping[str, str] | None = None

    @property
    def target(self) -> str:
        """The build this view is of, as the resolution answered it."""
        return str(self.deployment.root)

    @property
    def static(self) -> dict[str, Any]:
        """The documents that need no machine: machines, values, graph, diagnostics."""
        return {
            "machines": documents.machines(self.deployment),
            "values": documents.values(self.deployment),
            "graph": graph.graph(self.deployment),
            "diagnostics": documents.diagnostics(self.deployment),
        }

    def answer(self, route: str) -> Answered:
        """Answer one route.

        Args:
            route: The path of the request, without a query.

        Returns:
            The status, the content type and the bytes. A route the view does
            not answer is a refusal naming every route it does.
        """
        if route == routes.STYLE:
            return Answered(200, CSS, page.STYLESHEET.encode())
        if route == routes.PAGE:
            return Answered(200, HTML, page.page(self.target, self.static).encode())
        if route == routes.LIVE:
            return Answered(200, HTML, page.live(self.target, self.asked()).encode())
        if route == routes.LIVE_DOCUMENT:
            return _json(self.asked())
        if route in DOCUMENTS:
            return _json(self.static[DOCUMENTS[route]])
        return _json({"unanswered": route, "routes": list(routes.ALL)}, status=404)

    def asked(self) -> dict[str, Any]:
        """Ask the machines what they hold, once, now, because a reader asked."""
        return live.answers(
            self.deployment,
            self.runner,
            ssh_key=self.ssh_key,
            user=self.user,
            base_env=self.base_env,
        )


def _json(document: Any, *, status: int = 200) -> Answered:
    """Return one document as the bytes a route answers with."""
    body = json.dumps(document, indent=2, sort_keys=True) + "\n"
    return Answered(status, JSON, body.encode())


def read(target: str) -> Deployment:
    """Resolve and read one built deployment, before anything listens.

    Raises:
        ApplyError: If the target is neither a directory a build wrote nor a
            reference that builds one, or if what it names cannot be read,
            naming what was missing.
    """
    return manifest.read(manifest.resolve(target))


def handler(view: View) -> type[BaseHTTPRequestHandler]:
    """Return the request handler answering for one view.

    Returns:
        A handler answering `GET` and `HEAD` out of ``view`` and refusing
        every other method, which is how the view offers no route that
        applies, retires, rolls back or builds.
    """

    class Handler(BaseHTTPRequestHandler):
        server_version = "planner-view"

        def do_GET(self) -> None:
            route = self.path.split("?")[0]
            self._send(_answering(view, route), body=True)

        def do_HEAD(self) -> None:
            route = self.path.split("?")[0]
            self._send(_answering(view, route), body=False)

        def do_POST(self) -> None:
            self._send(_refused(), body=True)

        def do_PUT(self) -> None:
            self._send(_refused(), body=True)

        def do_PATCH(self) -> None:
            self._send(_refused(), body=True)

        def do_DELETE(self) -> None:
            self._send(_refused(), body=True)

        def _send(self, answered: Answered, *, body: bool) -> None:
            self.send_response(answered.status)
            self.send_header("Content-Type", answered.kind)
            self.send_header("Content-Length", str(len(answered.body)))
            if answered.status == 405:
                self.send_header("Allow", "GET, HEAD")
            self.end_headers()
            if body:
                self.wfile.write(answered.body)

        def log_message(self, format: str, *args: Any) -> None:
            print(f"planner-view: {format % args}", file=sys.stderr)

    return Handler


def _answering(view: View, route: str) -> Answered:
    """Answer one route, and report a machine that refused as the machine's own."""
    try:
        return view.answer(route)
    except ApplyError as refused:
        return _json({"refused": str(refused)}, status=502)


def _refused() -> Answered:
    """Refuse a method that is not a reading."""
    return _json({"refused": READ_ONLY, "routes": list(routes.ALL)}, status=405)


def serving(view: View, *, host: str = HOST, port: int = PORT) -> ThreadingHTTPServer:
    """Return a server bound for ``view``, refusing any address but the loopback one.

    Raises:
        ApplyError: If ``host`` is not the loopback interface, naming the
            reason, so nothing is bound and no connection is accepted.
    """
    if host not in LOOPBACK:
        raise ApplyError(f"{host} is not the loopback interface: {PUBLISHED}")
    return ThreadingHTTPServer((host, port), handler(view))


def parser() -> argparse.ArgumentParser:
    """Return the program's argument parser."""
    root = argparse.ArgumentParser(
        prog="planner-view",
        description=(
            "Show one built deployment in a browser: the machines, the entries placed on them, "
            "their units, the generated values, the typed edges between entries and every "
            "diagnostics row. It reads a build and never changes a machine, a build or a file."
        ),
        epilog=(
            f"A target is a directory a build wrote, holding manifest.json beside plan.json, or "
            f"a flake reference naming an attribute that builds one. It is resolved once before "
            f"the port is open, so no request is ever a build. {PUBLISHED}. The routes are "
            f"{', '.join(routes.ALL)}."
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    root.add_argument("target", help="a built deployment directory, or a flake reference")
    root.add_argument("--port", type=int, default=PORT, help=f"the port to listen on ({PORT})")
    root.add_argument("--host", default=HOST, help=f"the loopback address to bind ({HOST})")
    root.add_argument(
        "--ssh-key", metavar="PATH", help="the private key the live view connects with"
    )
    root.add_argument("--user", default="root", metavar="USER", help="the login on each machine")
    return root


def main(argv: list[str] | None = None) -> int:
    """Run the view over one target until it is interrupted.

    Returns:
        The exit status: zero, or one for a refusal reported on stderr.
    """
    args = parser().parse_args(argv)
    try:
        view = View(
            deployment=read(args.target),
            runner=remote.Subprocess(),
            ssh_key=Path(args.ssh_key) if args.ssh_key else None,
            user=args.user,
        )
        server = serving(view, host=args.host, port=args.port)
    except ApplyError as refused:
        print(f"planner-view: {refused}", file=sys.stderr)
        return 1
    print(f"planner-view: http://{args.host}:{args.port}{routes.PAGE}", file=sys.stderr)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        server.shutdown()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
