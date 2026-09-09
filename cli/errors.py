"""The one refusal the command makes.

One exception type rather than one per module: every refusal is the same act, the
command declining to apply a deployment and naming the entry, the field and the
value at fault, and a caller that wants to tell two apart reads the message
rather than catching a subclass.
"""

from __future__ import annotations


class ApplyError(RuntimeError):
    """A deployment the command will not apply, named by entry, field and value."""
