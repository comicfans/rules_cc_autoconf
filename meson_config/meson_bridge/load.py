import json
from dataclasses import dataclass
from typing import Optional

@dataclass
class CheckResult:
    name: str
    define: Optional[str]
    value: Optional[str]
    success: bool
    is_define: bool
    unquote: bool


def load_as_check_result(file)->CheckResult:
    with open(file, 'r') as f:
        obj = json.load(f)
        names = list(obj.keys())
        assert len(names) == 1
        name = names[0]
        kv = obj[name]
        ret = CheckResult(None, None, None, None,None, None)

        for key,value in kv.items():
            setattr(ret, key, value)

        if "define" not in kv.keys():
            setattr(ret, "define", name)

        return ret

