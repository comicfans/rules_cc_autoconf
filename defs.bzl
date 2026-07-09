"""Public API of the `meson_config` module.

`expr_config` accepts a mix of ordinary `checks.AC_CHECK_*` checks and
`expr_defines(...)` computed defines -- exactly like `autoconf`, plus python
expressions.  It is a macro: the plain checks are routed to a standard
`autoconf` target and the `expr_defines` to the `_expr_config` rule (wired as a
consumer of that target).  Each expression is evaluated against the resolved
check results.

This keeps the whole feature isolated in the `meson_config` module: the expr
rule is pure post-processing over the public `CcAutoconfInfo` provider and
never runs the compiler or the autoconf checker, and the plain checks reuse the
stock `autoconf` rule unchanged.  Nothing in the autoconf implementation is
touched.
"""

load("@rules_cc_autoconf//autoconf:autoconf.bzl", _autoconf = "autoconf")
load("@rules_cc_autoconf//autoconf:cc_autoconf_info.bzl", "CcAutoconfInfo")
load("//:meson_hdr.bzl", _meson_hdr = "meson_hdr")

def _transitive_infos(deps):
    """Return a depset of `CcAutoconfInfo` for `deps` and their transitive deps."""
    direct = [dep[CcAutoconfInfo] for dep in deps]
    return depset(direct, transitive = [info.deps for info in direct])

def _name_to_file(infos):
    """Flatten every cache/define/subst result into one name -> File map."""
    mapping = {}
    for info in infos:
        mapping.update(info.cache_results)
        mapping.update(info.define_results)
        mapping.update(info.subst_results)
    return mapping

def _expr_config_impl(ctx):
    deps = _transitive_infos(ctx.attr.deps)
    name_to_file = _name_to_file(deps.to_list())

    cache_results = {}
    define_results = {}

    for check_json in ctx.attr.checks:
        check = json.decode(check_json)
        expr = check.get("expr")
        if not expr:
            fail(
                "`expr_config` only accepts `expr_defines(...)` checks. Regular " +
                "checks belong on an `autoconf` target passed through `deps`. " +
                "Offending check on `{}`: {}".format(ctx.label, check.get("name")),
            )

        name = check["name"]
        define = check.get("define")

        check_spec = ctx.actions.declare_file("{}/{}.check.json".format(ctx.label.name, name))
        ctx.actions.write(
            output = check_spec,
            content = json.encode_indent(check, indent = " " * 4) + "\n",
        )

        expr_file = ctx.actions.declare_file("{}/{}.expr.py".format(ctx.label.name, name))
        ctx.actions.write(output = expr_file, content = expr)

        result_file = ctx.actions.declare_file("{}/{}.result.cache.json".format(ctx.label.name, name))

        args = ctx.actions.args()
        args.use_param_file("@%s", use_always = True)
        args.set_param_file_format("multiline")
        args.add("--check", check_spec)
        args.add("--expr_file", expr_file)
        args.add("--results", result_file)

        dep_files = []
        for required in check.get("requires", []):
            if required not in name_to_file:
                fail("expr check `{}` on `{}` requires `{}`, but no dep provides it.\nAvailable: {}".format(
                    name,
                    ctx.label,
                    required,
                    sorted(name_to_file.keys()),
                ))
            required_file = name_to_file[required]
            dep_files.append(required_file)
            args.add("--dep", "{}={}".format(required, required_file.path))

        ctx.actions.run(
            executable = ctx.executable._expr_eval,
            arguments = [args],
            inputs = depset([check_spec, expr_file] + dep_files),
            outputs = [result_file],
            mnemonic = "MesonExprEval",
            progress_message = "MesonExprEval %{label} - " + name,
        )

        cache_results[name] = result_file
        if define:
            define_results[define] = result_file

    return [
        CcAutoconfInfo(
            owner = ctx.label,
            deps = deps,
            cache_results = cache_results,
            define_results = define_results,
        ),
    ]

_expr_config = rule(
    implementation = _expr_config_impl,
    doc = """\
Low-level rule behind the `expr_config` macro: evaluate `expr_defines(...)`
against the results of upstream `autoconf` targets.

Prefer the `expr_config` macro, which also accepts plain `checks.AC_CHECK_*`
checks. This rule only accepts `expr_defines(...)` entries; the referenced
cache variables are resolved from `deps`, each expression is evaluated, and the
resulting value is exposed as a define through `CcAutoconfInfo` -- ready for
`meson_hdr` or `autoconf_hdr`.
""",
    attrs = {
        "checks": attr.string_list(
            doc = "JSON-encoded expr checks produced by `expr_defines(...)`.",
            default = [],
        ),
        "deps": attr.label_list(
            doc = "`autoconf` targets whose results the expressions read from.",
            providers = [CcAutoconfInfo],
        ),
        "_expr_eval": attr.label(
            cfg = "exec",
            executable = True,
            default = Label("//expr_eval:expr_eval"),
        ),
    },
    provides = [CcAutoconfInfo],
)

def expr_defines(defines, expr, requires = None):
    """Author one or more computed defines backed by a python expression.

    Args:
        defines: List of define names the expression assigns.
        expr: Python source evaluated with `requires` bound to their values;
            it should assign each name in `defines`.
        requires: Cache variables the expression reads (resolved from `deps`).

    Returns:
        A list of JSON-encoded checks for `expr_config`'s `checks` attribute.
    """
    checks = []
    for name in defines:
        check = {
            "define": name,
            "name": "ac_cv_define_{}".format(name),
            "expr": expr,
            "type": "define",
        }
        if requires:
            check["requires"] = requires
        checks.append(json.encode(check))
    return checks

def expr_config(name, checks = [], deps = [], **kwargs):
    """Run a mix of `AC_CHECK_*` checks and `expr_defines(...)` in one target.

    Plain checks are handed to a stock `autoconf` target (named
    `<name>_base`); the `expr_defines(...)` entries are evaluated by the
    `_expr_config` rule, which consumes that target so expressions can read
    the plain checks' cache variables.  The public `name` target provides the
    combined `CcAutoconfInfo` (transitively including the plain checks).

    Args:
        name: Target name.
        checks: Mixed list of `checks.AC_CHECK_*(...)` and `expr_defines(...)`.
        deps: Additional `autoconf` / `CcAutoconfInfo` dependencies.
        **kwargs: Common attributes (e.g. `visibility`, `tags`) for `name`.
    """
    regular = []
    exprs = []
    for check in checks:
        if "expr" in json.decode(check):
            exprs.append(check)
        else:
            regular.append(check)

    expr_deps = list(deps)
    if regular:
        base_name = "{}_base".format(name)
        _autoconf(
            name = base_name,
            checks = regular,
            deps = deps,
        )
        expr_deps = [":" + base_name]

    _expr_config(
        name = name,
        checks = exprs,
        deps = expr_deps,
        **kwargs
    )

meson_hdr = _meson_hdr
