def _ac_define_expr(
        define,
        expr,
        requires = None,
        subst = None):
    checks = []

    for d in define:
        check = {
            "define": d,
            "name": "ac_cv_define_{}".format(d),
            "expr": expr,
            "type": "define",
        }

        if subst != None:
            check["subst"] = subst

        if requires:
            check["requires"] = requires

        checks.append(json.encode(check))

    return checks
