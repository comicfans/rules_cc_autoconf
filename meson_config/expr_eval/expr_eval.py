from autoconf.private.meson_bridge.load import load_as_check_result, CheckResult
import argparse
import sys
import json

def main():
    parser = argparse.ArgumentParser(fromfile_prefix_chars='@')
    parser.add_argument("--expr_file", required = True, help = "expression")
    parser.add_argument("--dep", action = 'append', default = [],help = "key=file map" )
    parser.add_argument("--check", required = True, help = "check json path")
    parser.add_argument("--results", required = True, help = "output json path")

    args = parser.parse_known_args()



    with open(args[0].check,'r') as f:
        check = json.load(f)

    with open(args[0].expr_file, 'r') as f:
        expr = f.read()

    name_file = dict((s.split('=')[0],s.split('=',maxsplit=1)[1]) for s in args[0].dep)

    key_value = dict((name, load_as_check_result(file)) for (name,file) in name_file.items())

    # also adding their defines 
    defines = dict((v.define, v) for v in key_value.values() if v.define)

    merged = key_value | defines

    # create a environment, inject key as name, define value as value

    local_env = dict((k, v.value if v.value else None) for k,v in merged.items())

    exec(expr, {}, local_env)

    
    define_name = check["define"] if "define" in check else check["name"]
    result_json = {
        "define": define_name,
        "is_define": True,
        "success": True,
        "is_subst": False,
        "value": local_env.get(define_name)
    }

    print(f"try {define_name} , get {local_env}")

    j = {define_name: result_json}
    with open(args[0].results, 'w') as f:
        json.dump(j, f, indent = 4)

if __name__ == "__main__":
    main()
