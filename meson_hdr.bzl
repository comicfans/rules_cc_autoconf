"""`meson_hdr` rule: generate a config header via the meson bridge.

Self-contained in the `meson_config` module -- it consumes only the public
`CcAutoconfInfo` provider from rules_cc_autoconf and never touches the autoconf
rule implementation.  Where `autoconf_hdr` runs the built-in C++ resolver, this
rule runs the python `meson_bridge`, which feeds the same check results into
meson's template machinery.
"""

load("@rules_cc_autoconf//autoconf:cc_autoconf_info.bzl", "CcAutoconfInfo")

def _collect_results(deps):
    """Merge transitive define/subst results and unquoted names from `deps`."""
    direct = [dep[CcAutoconfInfo] for dep in deps]
    infos = depset(direct, transitive = [info.deps for info in direct]).to_list()

    define_results = {}
    subst_results = {}
    unquoted = {}
    for info in infos:
        define_results.update(info.define_results)
        subst_results.update(info.subst_results)
        for name in info.unquoted_defines:
            unquoted[name] = True

    return define_results, subst_results, unquoted

def _meson_hdr_impl(ctx):
    define_results, subst_results, unquoted = _collect_results(ctx.attr.deps)

    selected = dict(define_results)
    if ctx.attr.mode in ("subst", "all"):
        selected.update(subst_results)

    args = ctx.actions.args()
    args.use_param_file("@%s", use_always = True)
    args.set_param_file_format("multiline")
    args.add("--output", ctx.outputs.out)
    args.add("--mode", ctx.attr.mode)

    inputs = []
    if ctx.file.template:
        args.add("--template", ctx.file.template)
        inputs.append(ctx.file.template)

    for name, result_file in selected.items():
        args.add("--define", "{}={}".format(name, result_file.path))
        inputs.append(result_file)

    for name in unquoted:
        args.add("--unquote", name)

    for key, value in ctx.attr.substitutions.items():
        args.add("--subst", "{}={}".format(key, value))

    ctx.actions.run(
        executable = ctx.executable._resolver,
        arguments = [args],
        inputs = depset(inputs),
        outputs = [ctx.outputs.out],
        mnemonic = "MesonHdr",
        progress_message = "MesonHdr %{label}",
        env = ctx.configuration.default_shell_env,
    )

    return [DefaultInfo(files = depset([ctx.outputs.out]))]

meson_hdr = rule(
    implementation = _meson_hdr_impl,
    doc = """\
Generate a configuration header from `autoconf` / `expr_config` results using
meson-style templates.

Like `autoconf_hdr`, but the template uses meson syntax (`#mesondef FOO`,
`@FOO@`) and rendering is performed by the python meson bridge rather than the
built-in resolver.
""",
    attrs = {
        "deps": attr.label_list(
            doc = "Targets providing `CcAutoconfInfo` (e.g. `autoconf` or `expr_config`).",
            providers = [CcAutoconfInfo],
        ),
        "mode": attr.string(
            doc = "What to render: `defines` (default), `subst`, or `all`.",
            default = "defines",
            values = ["defines", "subst", "all"],
        ),
        "out": attr.output(
            doc = "The generated header (typically `config.h`).",
            mandatory = True,
        ),
        "substitutions": attr.string_dict(
            doc = "Literal exact-string replacements applied to the output.",
            default = {},
        ),
        "template": attr.label(
            doc = "Meson-style template (`config.h.in`) to fill in.",
            allow_single_file = True,
            mandatory = False,
        ),
        "_resolver": attr.label(
            cfg = "exec",
            executable = True,
            default = Label("//meson_bridge:meson_bridge"),
        ),
    },
)
