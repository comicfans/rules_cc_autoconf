import sys
import argparse
import json
import os
from pathlib import Path
from typing import Optional

from mesonbuild.build import ConfigurationData
from mesonbuild.mesonlib import do_conf_file, dump_conf_header

from autoconf.private.meson_bridge.load import CheckResult, load_as_check_result


def to_meson_conf(define_result: list[CheckResult]):

    conf = ConfigurationData()

    for check in define_result:

        if not (check.success or False):
            continue

        if check.is_define or False:
            value = check.value
            if value is None:
                continue

            if not isinstance(value, str):
                conf.values[check.define] =(check.value, '')
            else:
                if check.unquote or False:
                    value = '\\"'.join(value.split('"'))
                conf.values[check.define] =(check.value, '')
        else:
            # not a define, but package info
            conf.values[check.define] =(check.value, "")

    return conf


def main():


    parser = argparse.ArgumentParser(fromfile_prefix_chars='@')
    
    parser.add_argument('--define-result', action='append', help='define result json files')
    
    parser.add_argument('--output', required=True, help='output file')

    parser.add_argument('--template', required=False, help='template file')
    
    parser.add_argument('--mode', nargs='+', help='operate mode')
    
    args = parser.parse_args()

    check_results = [load_as_check_result(v) for v in args.define_result]

    conf = to_meson_conf(check_results)

    if args.template:
        do_conf_file(args.template , args.output, conf, "meson")
    else:
        dump_conf_header(args.output, conf, "c", None)



if __name__ == "__main__":

    main()
