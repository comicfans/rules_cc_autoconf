load("@rules_cc//cc:find_cc_toolchain.bzl", "use_cc_toolchain")
load("//autoconf:autoconf_hdr.bzl", "autoconf_hdr")
load("//autoconf:cc_autoconf_info.bzl", "CcAutoconfInfo")

def _expr_config_impl(ctx):
    all_info = _checks_to_build_info(ctx)

    # Create individual CcAutoconfCheck actions for each cache variable
    # All checks sharing the same cache variable are processed together
    # (checks is already grouped by cache_name from _flatten_checks)
    for check_name, action in all_info.actions.items():
        check_result_file = action.output
        args, deps = _action_arg_dep(ctx, action, all_info)

        if action.check.get("expr"):
            expr_file = ctx.actions.declare_file(action.check["name"] + "_expr.py")
            ctx.actions.write(output = expr_file, content = action.check.get("expr"))

            args.add("--expr_file", expr_file.path)
            ctx.actions.run(
                executable = ctx.executable._expr_eval,
                arguments = [args],
                inputs = deps,
                outputs = [check_result_file],
                mnemonic = "CcAutoconfCheck",
                progress_message = "CcAutoconfCheck %{label} - " + check_name,
                env = all_info.env | ctx.configuration.default_shell_env,
                tools = all_info.toolchain_info.cc_toolchain.all_files,
            )
        else:
            ctx.actions.run(
                executable = ctx.executable._checker,
                arguments = [args],
                inputs = deps,
                outputs = [check_result_file],
                mnemonic = "CcAutoconfCheck",
                progress_message = "CcAutoconfCheck %{label} - " + check_name,
                env = all_info.env | ctx.configuration.default_shell_env,
                tools = all_info.toolchain_info.cc_toolchain.all_files,
            )

    # Return provider with three separate buckets
    return [
        CcAutoconfInfo(
            owner = ctx.label,
            deps = all_info.deps,
            cache_results = all_info.cache_results,
            define_results = all_info.define_results,
            subst_results = all_info.subst_results,
        ),
        OutputGroupInfo(
            autoconf_checks = depset([action.input for action in all_info.actions.values()]),
            autoconf_results = depset(all_info.cache_results.values() + all_info.define_results.values() + all_info.subst_results.values()),
        ),
    ]

def _expr_define(
        define,
        expr,
        requires = None):
    checks = []

    for d in define:
        check = {
            "define": d,
            "name": "ac_cv_define_{}".format(d),
            "expr": expr,
            "type": "define",
        }

        if requires:
            check["requires"] = requires

        checks.append(json.encode(check))

    return checks

def meson_hdr(**kwargs):
    kwargs["_resolver"] = "//meson_bridge:meson_bridge"
    autoconf_hdr(**kwargs)

expr_config = rule(
    implementation = _expr_config_impl,
    doc = """\
Run both python and autoconf-like checks and produce results.

this behave similar to autoconf, additionally support expr_define to be
used as check, allow meson style config script used in autoconf


Example:

```python
load("@meson_config//:defs.bzl", "expr_define", "script_config")

script_config(
    name = "config",
    checks = [
        checks.AC_CHECK_HEADER("stdio.h"),
        checks.AC_CHECK_FUNC("rand"),
        expr_define(define = ["VAR1", "VAR2"],
                      requires = ["ac_cv_header_stdio_h","ac_cv_func_rand"],
                      expr = \"\"\"
if ac_cv_header_stdio_h and ac_cv_func_rand:
    VAR1 = "BOTH"
if not ac_cv_func_rand:
    VAR2 = "NO_RAND"
\"\"\"
        ),
        checks.AC_CHECK_DECL("foo", requires = ["VAR1", "VAR2"])
    ],
)

```

this allow any valid python script being embedded as part of config script
and result being used by other checks. The results can then be used by `autoconf_hdr`
or `autoconf_srcs` or `meson_hdr` to generate headers or wrapped source files.
""",
    attrs = {
        "checks": attr.string_list(
            doc = "List of JSON-encoded checks from checks (e.g., `checks.AC_CHECK_HEADER('stdio.h')`).",
            default = [],
        ),
        "deps": attr.label_list(
            doc = "Additional `autoconf` or `package_info` dependencies.",
            providers = [CcAutoconfInfo],
        ),
        "_checker": attr.label(
            cfg = "exec",
            executable = True,
            default = Label("@autoconf//autoconf/private/checker:checker_bin"),
        ),
        "expr_eval": attr.label(
            cfg = "exec",
            executable = True,
            default = Label("//expr_eval:expr_eval"),
        ),
    },
    fragments = ["cpp"],
    toolchains = use_cc_toolchain(),
    provides = [CcAutoconfInfo],
)
