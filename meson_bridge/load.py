"""Read the flat result JSON files produced by rules_cc_autoconf checks.

The schema is the one written by the C++ checker and by `expr_eval`:

    {"success": bool, "type": "define"|"decl"|..., "value": <json value|null>}

The consumer name (cache variable / define name) is not stored in the file --
it is supplied out of band (via the `--dep name=file` / `--define name=file`
arguments), so `from_json` takes the name explicitly.
"""

import json
from dataclasses import dataclass
from typing import Any, Optional


@dataclass
class CheckResult:
    name: str
    value: Any
    success: bool
    type: Optional[str] = None


def from_json(name: str, path: str) -> "CheckResult":
    with open(path, "r") as f:
        obj = json.load(f)

    return CheckResult(
        name=name,
        value=obj.get("value"),
        success=bool(obj.get("success", False)),
        type=obj.get("type"),
    )
