"""Every route the view answers, spelled in one place.

A route's leading segment names no top-level entry of this repository, and the
page names its own stylesheet by the route that serves it rather than by a
path inside this source. The reason is the path scan: a repository-rooted
token counts as a path exactly when its first segment is a top-level entry,
and the scan reads raw file text, so a route whose first segment were the name
of a top-level directory would be a path the scan demands resolve to a file
that is not there.
"""

from __future__ import annotations

PAGE = "/"
STYLE = "/page.css"
LIVE = "/live"
MACHINES = "/documents/machines.json"
VALUES = "/documents/values.json"
GRAPH = "/documents/graph.json"
DIAGNOSTICS = "/documents/diagnostics.json"
LIVE_DOCUMENT = "/documents/live.json"

STATIC = (PAGE, STYLE, MACHINES, VALUES, GRAPH, DIAGNOSTICS)
ASKING = (LIVE, LIVE_DOCUMENT)
ALL = STATIC + ASKING
