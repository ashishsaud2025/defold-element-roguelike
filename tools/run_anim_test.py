#!/usr/bin/env python3
"""Run tools/test_anim.lua against src/game/anim.lua.

    python tools/run_anim_test.py

Exit code 1 if any check fails. Pure Lua 5.1 code, no Defold API needed.
"""
import os
import sys

try:
    from lupa.luajit21 import LuaRuntime
except Exception:
    try:
        from lupa import LuaRuntime
    except Exception:
        print("Install lupa first:  pip install lupa")
        sys.exit(2)

src = open(os.path.join("tools", "test_anim.lua"), encoding="utf-8").read()
lua = LuaRuntime(unpack_returned_tuples=True)
try:
    r = lua.execute(src)
except Exception as e:
    print("ANIM TEST CRASHED:", e)
    sys.exit(1)

checks = r["checks"]
failures = [r["failures"][i] for i in range(1, len(r["failures"]) + 1)]
print("checks  :", checks)
print("failures:", len(failures))
for f in failures:
    print("  -", f)
print("RESULT:", "PASS" if not failures else "FAIL")
sys.exit(0 if not failures else 1)
