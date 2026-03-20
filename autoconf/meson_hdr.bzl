load(
    "//autoconf/private:autoconf_config.bzl",
    "collect_deps",
    "collect_transitive_results",
)
load("//autoconf/private:providers.bzl", "CcAutoconfInfo")

def _meson_hdr_impl(ctx):
    # Get toolchain defaults based on the defaults attribute
    defaults = struct(cache = {}, define = {}, subst = {})

    deps = collect_deps(ctx.attr.deps)
    dep_infos = deps.to_list()
    dep_results = collect_transitive_results(dep_infos)

    all_define_checks = defaults.define | dep_results["define"]
    all_subst_checks = defaults.subst | dep_results["subst"]

    template = [ctx.file.template] if ctx.file.template else []
    inputs = depset(template + all_subst_checks.values() + all_define_checks.values())

    inputs = depset(transitive = [inputs])

    # Pass all individual results files directly to resolver (it merges internally)
    # Include both defaults and transitive checks so resolver can merge them
    # Use separate flags for each bucket
    args = ctx.actions.args()
    args.use_param_file("@%s", use_always = True)
    args.set_param_file_format("multiline")

    # Add define results
    for results_file_path in all_define_checks.values():
        args.add("--define-result", results_file_path)

    # Add subst results
    for results_file_path in all_subst_checks.values():
        args.add("--subst-result", results_file_path)

    args.add("--output", ctx.outputs.out)
    if template:
        args.add("--template", ctx.file.template)
    args.add("--mode", ctx.attr.mode)

    # Add substitutions: --subst <name> <value>
    for name, value in ctx.attr.substitutions.items():
        args.add("--subst")
        args.add(name)
        args.add(value)

    ctx.actions.run(
        executable = ctx.executable._resolver,
        arguments = [args],
        inputs = inputs,
        outputs = [ctx.outputs.out],
        mnemonic = "CcAutoconfHdr",
        env = ctx.configuration.default_shell_env,
    )

    # Return a dict mapping define names to result files (from autoconf deps)
    # The merged output_results_json is still created for backward compatibility, but the provider
    # now carries the dict of define names to files
    return [
        DefaultInfo(
            files = depset([ctx.outputs.out]),
        ),
    ]

meson_hdr = rule(
    implementation = _meson_hdr_impl,
    doc = """
    TODO
""",
    attrs = {
        "deps": attr.label_list(
            doc = "List of `autoconf` targets which provide check results. Results from all deps will be merged together, and duplicate define names will produce an error. If not provided, an empty results file will be created.",
            providers = [CcAutoconfInfo],
        ),
        "mode": attr.string(
            doc = """Processing mode that determines what should be replaced within the file.""",
            default = "defines",
            values = ["defines", "subst", "all"],
        ),
        "out": attr.output(
            doc = "The output config file (typically `config.h`).",
            mandatory = True,
        ),
        "substitutions": attr.string_dict(
            doc = """A mapping of exact strings to replacement values.

            Each entry performs an exact text replacement in the template - the key
            string is replaced with the value string. No special patterns or wrappers
            are added.

            Example:
            ```python
            autoconf_hdr(
                name = "config",
                out = "config.h",
                template = "config.h.in",
                substitutions = {
                    "@MY_VERSION@": "1.2.3",
                    "@BUILD_TYPE@": "release",
                    "PLACEHOLDER_TEXT": "actual_value",
                },
                deps = [":checks"],
            )
            ```

            This would replace the exact string `@MY_VERSION@` with `1.2.3`,
            `@BUILD_TYPE@` with `release`, and `PLACEHOLDER_TEXT` with `actual_value`.""",
            default = {},
        ),
        "template": attr.label(
            doc = "Template file (`config.h.in`) to use as base for generating the header file. The template is used to format the output header, but does not generate any checks.",
            allow_single_file = True,
            mandatory = False,
        ),
        "_resolver": attr.label(
            cfg = "exec",
            executable = True,
            default = Label("//autoconf/private/meson_bridge:meson_bridge"),
        ),
    },
    toolchains = [
        config_common.toolchain_type("@rules_cc_autoconf//autoconf:toolchain_type", mandatory = False),
    ],
)
