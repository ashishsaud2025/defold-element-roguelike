#!/usr/bin/env python3
"""Run the headless smoke test (tools/smoke_test.lua) against the project.

    pip install lupa            # once (provides LuaJIT with the `bit` module)
    python tools/run_smoke_test.py                 # normal run (placeholder art)
    ART_TEST=1 python tools/run_smoke_test.py      # with actor art enabled (PowerShell: $env:ART_TEST=1)
    SPRITE_MAX=128 python tools/run_smoke_test.py  # prove the sprite-cap check works (should FAIL)

Run it from the project root. A mock Defold API stands in for the engine, so this does NOT
check rendering, blending, z-order or the editor's file parsing. Exit code 1 if any error is reported.
"""
import os, sys
try:
    from lupa.luajit21 import LuaRuntime
except Exception:
    try:
        from lupa import LuaRuntime
        print("WARNING: lupa has no LuaJIT build here; the `bit` module may be missing.")
    except Exception:
        print("Install lupa first:  pip install lupa"); sys.exit(2)

os.environ.setdefault("PROJECT_ROOT", os.getcwd())
src = open(os.path.join("tools", "smoke_test.lua"), encoding="utf-8").read()
lua = LuaRuntime(unpack_returned_tuples=True)
try:
    r = lua.execute(src)
except Exception as e:
    print("SMOKE TEST CRASHED:", e); sys.exit(1)

errs = [r["errors"][i] for i in range(1, len(r["errors"]) + 1)]
print("results       :", r["results"], "(WIN,WIN,DEAD,DEAD,DEAD expected)")
print("selfcheck     :", r["selfcheck"])
print("live objects  : baseline %d -> after %d (max %d, created %d)" % (r["baseline"], r["after"], r["maxlive"], r["created"]))
print("wall clipping :", r["wall_viol"], "first:", r["wall_first"])
print("sprite flips  : mirrored %d / normal %d" % (r["flip_true"], r["flip_false"]))
print("pathing       :\n" + r["path"])
fxm = [r["fx_missing"][i] for i in range(1, len(r["fx_missing"]) + 1)]
print("skill fx      : %d problem(s); max live one-shot anims %d (cap 90)" % (len(fxm), r["max_anims"]))
for m in fxm: print("  - FX:", m)
print("fx per skill  :", r["fx_report"][:600], "...")
spell = [r["spell_fail"][i] for i in range(1, len(r["spell_fail"]) + 1)]
print("spellcraft    : %d check(s) passed, %d failed" % (int(r["spell_pass"]), len(spell)))
if "ui_msg_max" in r:
    print("ui msg size   : worst frame = %d bytes (engine limit 2048)" % int(r["ui_msg_max"]))
if "ui_worst" in r:
    order = ["TITLE", "COMBOS", "CREDITS", "HOME", "HOME_EDIT", "ROOM", "REWARD", "CAULDRON", "DEAD", "WIN"]
    parts = []
    for st in order:
        try:
            v = r["ui_worst"][st]
        except Exception:
            v = None
        if v is not None:
            parts.append("%s=%d" % (st, int(v)))
    print("ui msg per state: %s (engine limit 2048)" % ", ".join(parts))
for m in spell: print("  - SPELL:", m)
print("errors        :", len(errs))
for e in errs: print("  -", str(e)[:300])
ok = not errs and not fxm and not spell and int(r["spell_pass"]) > 0 and r["max_anims"] <= 90 and r["baseline"] == r["after"] and r["wall_viol"] == 0 and "STUCK" not in r["path"]
# With art on, the sprite must actually be mirrored in both directions during a run;
# with ART_TEST=0 (shape fallback) there is no hflip at all.
if os.environ.get("ART_TEST") != "0" and not (r["flip_true"] > 0 and r["flip_false"] > 0):
    print("FLIP CHECK FAILED: expected the player/enemies to face both ways")
    ok = False
print("\nRESULT:", "PASS (mock only)" if ok else "FAIL")
if not ok:
    sys.exit(1)

# ===== HUD harness: gui_script under a stub gui.* API =====
try:
    hud_src = open(os.path.join("tools", "hud_test.lua"), encoding="utf-8").read()
except FileNotFoundError:
    print("hud harness   : tools/hud_test.lua not found")
    sys.exit(1)
lua2 = LuaRuntime(unpack_returned_tuples=True)
try:
    h = lua2.execute(hud_src)
except Exception as e:
    print("HUD HARNESS CRASHED:", e)
    sys.exit(1)
herrs = [h["errors"][i] for i in range(1, len(h["errors"]) + 1)]
print("hud harness   : %d check(s) passed, %d failed" % (int(h["checks"]), len(herrs)))
for e in herrs:
    print("  - HUD:", str(e)[:300])
print("\nHUD RESULT:", "PASS" if not herrs else "FAIL")
sys.exit(0 if not herrs else 1)
