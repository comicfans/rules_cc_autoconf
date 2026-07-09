"""Render a config header from rules_cc_autoconf results using meson.

This is the "bridge" the module is named for: it feeds check results produced
by ordinary `autoconf` / `expr_config` targets into meson's own
`ConfigurationData` and template machinery, so meson-style templates
(`#mesondef FOO`, `@FOO@`) can be filled in from autoconf-style checks.

Inputs (all via `--define name=file` etc.) are the flat result files described
in `meson_bridge.load`.  String define values are quoted the way a C string
literal must be unless the define was declared unquoted.
"""

import argparse
import json

from meson_bridge.load import from_json

from mesonbuild.build import ConfigurationData
from mesonbuild.mesonlib import do_conf_file, dump_conf_header


def main() -> None:
    parser = argparse.ArgumentParser(fromfile_prefix_chars="@")
    parser.add_argument("--define", action="append", default=[], help="name=file define results")
    parser.add_argument("--unquote", action="append", default=[], help="define names to render unquoted")
    parser.add_argument("--subst", action="append", default=[], help="literal key=value replacements")
    parser.add_argument("--output", required=True, help="output header file")
    parser.add_argument("--template", required=False, help="meson-style template (config.h.in)")
    parser.add_argument("--mode", default="defines", help="defines|subst|all")
    args = parser.parse_args()

    unquoted = set(args.unquote)

    conf = ConfigurationData()
    for spec in args.define:
        name, _, path = spec.partition("=")
        result = from_json(name, path)
        if not result.success:
            continue

        value = result.value
        if value is None:
            # Valueless define (`#define FOO`).
            conf.values[name] = (True, "")
            continue

        if isinstance(value, bool):
            if value:
                conf.values[name] = (True, "")
            # A false boolean stays undefined.
            continue

        if isinstance(value, str) and name not in unquoted:
            value = '"{}"'.format(value)

        conf.values[name] = (value, "")

    if args.template:
        do_conf_file(args.template, args.output, conf, "meson")
    else:
        dump_conf_header(args.output, conf, "c", None)

    # Literal, exact-string substitutions applied after meson processing.
    literal = {}
    for spec in args.subst:
        key, _, value = spec.partition("=")
        literal[key] = value

    if literal:
        with open(args.output, "r") as f:
            text = f.read()
        for key, value in literal.items():
            text = text.replace(key, value)
        with open(args.output, "w") as f:
            f.write(text)


if __name__ == "__main__":
    main()
