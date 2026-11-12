#!/usr/bin/env python3
"""UI layout validator (Phase C).

Static, no engine. Loads src/ui/layout.lua headlessly and parses main/hud.gui for
node ids. Checks:
  - every button rect is inside 960x640 and meets minimum size (all nine screens),
  - no two buttons overlap on any screen (all nine screens),
  - every screen panel is inside 960x640,
  - every referenced node id exists in main/hud.gui,
  - every static text in a layout spec fits its container (mono advance math),
  - every card rect in REWARD stays inside the screen and never overlaps another.
"""
import io
import os
import re
import sys

_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(_root)

from lupa.luajit21 import LuaRuntime

problems = []

lua = LuaRuntime()
lua.execute('package.path = package.path .. ";./?.lua;./src/?.lua"')
L = lua.execute('return dofile("src/ui/layout.lua")')
if L is None:
    print("validate_ui: layout.lua failed to load")
    sys.exit(1)

ALL_SCREENS = ("TITLE", "COMBOS", "CREDITS", "PICK_START", "ROOM", "REWARD",
                "CAULDRON", "DEAD", "WIN")

# ---- rect sanity + overlap (Lua side) ----
def collect(table_obj):
    try:
        out = []
        n = len(table_obj)
        for i in range(1, n + 1):
            v = table_obj[i]
            if v is not None:
                out.append(v)
        return out
    except TypeError:
        return [table_obj]

for name in ALL_SCREENS:
    for p in collect(L.audit_screen(name)):
        problems.append(str(p))

for p in collect(L.audit_text_fit()):
    problems.append(str(p))

# ---- card rects: inside 960x640, no overlap ----
for i in range(1, 4):
    card = L.SCREENS.REWARD.cards[i]
    if card.x < 0 or card.y < 0 or card.x + card.w > L.DESIGN_W or card.y + card.h > L.DESIGN_H:
        problems.append("REWARD: card%d leaves 960x640" % i)
    for j in range(i + 1, 4):
        other = L.SCREENS.REWARD.cards[j]
        if (card.x < other.x + other.w and other.x < card.x + card.w
                and card.y < other.y + other.h and other.y < card.y + card.h):
            problems.append("REWARD: card%d overlaps card%d" % (i, j))

# ---- referenced ids exist in hud.gui (or are registered as created at init) ----
gui_text = io.open("main/hud.gui", encoding="utf-8").read()
gui_set = set(re.findall(r'id:\s*"([^"]+)"', gui_text))
created_ids = set(str(x) for x in collect(L.CREATED_IDS))

required = set()
screens = L.SCREENS
for name in ALL_SCREENS:
    btable = L.SCREENS[name].buttons
    if btable is not None:
        for b in collect(btable):
            required.add(b.id)
# ALL_NODES ids in hud.gui_script
script = io.open("main/hud.gui_script", encoding="utf-8").read()
m = re.search(r"local ALL_NODES = \{(.*?)\}", script, re.S)
required.update(re.findall(r'"([a-z0-9_]+)"', m.group(1)))

for rid in sorted(r for r in required if r):
    if rid not in gui_set and rid not in created_ids:
        problems.append("hud.gui is missing node id '%s'" % rid)

if problems:
    for p in problems:
        print(p)
    print("\n%d problem(s)" % len(problems))
    sys.exit(1)
print("0 problem(s)")
sys.exit(0)
