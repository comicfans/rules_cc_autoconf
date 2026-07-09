"""Evaluate a meson-style Python expression into a single define result.

`expr_config` runs this once per `expr_defines(...)` check.  Each check names
the cache variables it `requires`; those are passed as `--dep name=file`
pointing at the result files produced by an upstream `autoconf` target.  The
expression body runs with those names bound to their result values, and the
value it assigns to the define name becomes this check's result.

The output file uses the same flat schema as the C++ checker so that
`meson_hdr` (or any autoconf consumer) can treat expr results and ordinary
check results uniformly.
"""

import argparse
import json

from meson_bridge.load import from_json


def main() -> None:
    parser = argparse.ArgumentParser(fromfile_prefix_chars="@")
    parser.add_argument("--expr_file", required=True, help="python expression file")
    parser.add_argument("--dep", action="append", default=[], help="name=file result inputs")
    parser.add_argument("--check", required=True, help="check json path")
    parser.add_argument("--results", required=True, help="output result json path")
    args = parser.parse_args()

    with open(args.check, "r") as f:
        check = json.load(f)

    with open(args.expr_file, "r") as f:
        expr = f.read()

    # Bind every required cache variable to its resolved value.
    env = {}
    for spec in args.dep:
        name, _, path = spec.partition("=")
        env[name] = from_json(name, path).value

    exec(expr, {}, env)

    define_name = check.get("define") or check["name"]
    value = env.get(define_name)

    result = {
        "success": value is not None,
        "type": check.get("type", "define"),
        "value": value,
    }

    with open(args.results, "w") as f:
        json.dump(result, f, indent=4)


if __name__ == "__main__":
    main()
