#!/usr/bin/env python3
"""Syntax-check every Lua source file under main/, src/ and tools/ with LuaJIT.

    python tools/check_lua.py     # exit 0 when every file compiles, 1 otherwise

Defold's Lua source is not all `*.lua`: the engine parses `.script`,
`.gui_script` and `.render_script` files as plain Lua, so all four extensions are
compiled here (loadstring does not care about the file name). Compiling with
LuaJIT is the check that matters — Defold runs LuaJIT (Lua 5.1), so `goto`, `//`,
`math.type` and the 5.3 bitwise operators are all compile errors in the game even
though a modern Lua would accept them; checking with Lua 5.3+ would pass code the
editor rejects.

This is DoD step 1 in AGENTS.md. It only compiles (loadstring); it never runs the files.
"""
import os
import sys

try:
    from lupa.luajit21 import LuaRuntime
except Exception:
    try:
        from lupa import LuaRuntime
        print("WARNING: lupa has no LuaJIT build here; the `bit` module may be missing.")
    except Exception:
        print("Install lupa first:  pip install lupa")
        sys.exit(2)

ROOTS = ("main", "src", "tools")
LUA_EXTS = (".lua", ".script", ".gui_script", ".render_script")


def find_lua_files(root):
    found = []
    for base, dirs, files in os.walk(root):
        dirs.sort()
        for name in sorted(files):
            if name.endswith(LUA_EXTS):
                found.append(os.path.join(base, name))
    return found


def main():
    lua = LuaRuntime(unpack_returned_tuples=True)
    compile_ = lua.eval("function(src, name) return loadstring(src, name) end")

    # The whole point of this tool is the 5.1 dialect. If the runtime is not
    # LuaJIT/5.1 it would silently accept `//` and `goto`, so refuse to run.
    probe = compile_("local a = 1 // 1", "dialect-probe")
    if not (probe is None or (isinstance(probe, tuple) and probe[0] is None)):
        print("NOT LUA 5.1: this runtime accepts `//`; run it on LuaJIT (pip install lupa).")
        return 2

    files = []
    for root in ROOTS:
        if os.path.isdir(root):
            files.extend(find_lua_files(root))
        else:
            print("SKIP %s: no such directory" % root)
    files.sort()

    failed = 0
    for path in files:
        with open(path, "r", encoding="utf-8", errors="surrogateescape", newline="") as fh:
            src = fh.read()
        try:
            res = compile_(src, path)
        except Exception as exc:                       # decode/encode failure
            print("FAIL %s: %s" % (path, exc))
            failed += 1
            continue
        if res is None:
            ok, err = False, "loadstring returned nil"
        elif isinstance(res, tuple):
            ok, err = res[0] is not None, res[1]
        else:
            ok, err = True, None
        if ok:
            print("OK   %s" % path)
        else:
            print("FAIL %s: %s" % (path, err))
            failed += 1

    print("\n%d file(s), %d OK, %d FAIL" % (len(files), len(files) - failed, failed))
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
