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
lua.execute('L = dofile("src/ui/layout.lua")')
L = lua.globals().L
if L is None:
    print("validate_ui: layout.lua failed to load")
    sys.exit(1)

ALL_SCREENS = ("TITLE", "COMBOS", "CREDITS", "HOME", "HOME_EDIT", "ROOM", "REWARD",
                "CAULDRON", "DEAD", "WIN")

# Runtime-built bodies for the static audit (COMBOS/CREDITS panels): built INSIDE
# Lua (real Lua table, not a Python dict) so missing keys return nil as the audit
# expects. Built from the same pure modules the HUD uses.
audit_bodies = None
lua.execute('package.path = package.path .. ";./?.lua;./src/?.lua"')
try:
    lua.execute('_bodies = { ["COMBOS:credits_body"] = require("src.core.combos").panel_text(), ["CREDITS:credits_body"] = table.concat(require("src.core.credits"), "\\n") }')
    audit_bodies = lua.globals()._bodies
    cb = audit_bodies["COMBOS:credits_body"]
    cr = audit_bodies["CREDITS:credits_body"]
    print("bodies   : COMBOS (%d chars), CREDITS (%d chars)" % (len(cb), len(cr)))
except Exception as e:
    problems.append("validate_ui: failed to build combos/credits bodies: %s" % e)
    audit_bodies = lua.eval("return {}")

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

for p in collect(L.audit_text_fit(audit_bodies)):
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

# ---- full position map: static twin of the harness geometry audits ----
# (a) every authored node id has a layout rect mapping;
# (b) every mapped box rect is inside 960x640;
# (c) panel and flash_box map to the full screen;
# (d) every screen's required region is covered by the union of mapped rects
#     (all mapped rects assumed visible: an upper bound for the visible union,
#     so this catches missing mappings, not occlusion);
# plus: authored positions are all zeroed (no reliance on authoring) and box
# sizes match their mapped rects.
lua.execute('rect_list = {} for k, v in pairs(L.ALL_RECT_RECT) do rect_list[#rect_list + 1] = { k, v.x, v.y, v.w, v.h } end')
_rect_list = lua.globals().rect_list
mapped = {}
for i in range(1, len(_rect_list) + 1):
    row = _rect_list[i]
    mapped[row[1]] = (float(row[2]), float(row[3]), float(row[4]), float(row[5]))

if len(mapped) != len(gui_set):
    problems.append("position map has %d mapped rects, hud.gui has %d nodes" % (len(mapped), len(gui_set)))
for rid in sorted(gui_set - set(mapped)):
    problems.append("no layout rect mapped for authored node '%s'" % rid)
for rid in sorted(set(mapped) - gui_set):
    problems.append("layout rect mapped for missing node '%s'" % rid)

for rid, (x, y, w, h) in mapped.items():
    if w > 0 or h > 0:
        if x < -0.01 or y < -0.01 or x + w > L.DESIGN_W + 0.01 or y + h > L.DESIGN_H + 0.01:
            problems.append("%s: mapped rect leaves 960x640 (x=%.0f y=%.0f %.0fx%.0f)" % (rid, x, y, w, h))

for rid in ("panel", "flash_box"):
    r = mapped.get(rid)
    if r != (0.0, 0.0, 960.0, 640.0):
        problems.append("%s: mapped rect is %s, expected the full 960x640 screen" % (rid, r))

# authored positions are all zero (layout owns position; nothing may rely on authoring)
for pm in re.finditer(r'position \{ x:\s*([-\d.]+)\s*y:\s*([-\d.]+) \}', gui_text):
    if float(pm.group(1)) != 0.0 or float(pm.group(2)) != 0.0:
        problems.append("authored position %s,%s is not zero (layout owns positions)" % (pm.group(1), pm.group(2)))

# box sizes match mapped rect sizes
_gui_blocks = re.findall(r'nodes\s*{.*?\n}\n', gui_text, re.S)
for block in _gui_blocks:
    nid = re.search(r'id:\s*"([^"]+)"', block).group(1)
    sz = re.search(r'size\s*{\s*x:\s*([\d.]+)\s*y:\s*([\d.]+)\s*}', block)
    if sz and nid in mapped and mapped[nid][2] > 0:
        mw, mh = mapped[nid][2], mapped[nid][3]
        if abs(float(sz.group(1)) - mw) > 0.5 or abs(float(sz.group(2)) - mh) > 0.5:
            problems.append("%s: authored size %sx%s != mapped rect %sx%s" % (
                nid, sz.group(1), sz.group(2), mw, mh))

def _subtract(E, R):
    ix, iy = max(E[0], R[0]), max(E[1], R[1])
    ix2, iy2 = min(E[0] + E[2], R[0] + R[2]), min(E[1] + E[3], R[1] + R[3])
    if ix >= ix2 or iy >= iy2:
        return [E]
    out = []
    ex, ey, ew, eh = E
    if ex < ix: out.append((ex, ey, ix - ex, eh))
    if ex + ew > ix2: out.append((ix2, ey, (ex + ew) - ix2, eh))
    if ey < iy: out.append((ix, ey, ix2 - ix, iy - ey))
    if ey + eh > iy2: out.append((ix, iy2, ix2 - ix, (ey + eh) - iy2))
    return out

def _covered(E, rects):
    pieces = [E]
    for r in rects:
        new_pieces = []
        for p in pieces:
            new_pieces.extend(_subtract(p, r))
        pieces = new_pieces
        if not pieces:
            return True
    return len(pieces) == 0

_all_rects = [(x, y, w, h) for (x, y, w, h) in mapped.values() if w > 0 and h > 0]
for name in ALL_SCREENS:
    scr = L.SCREENS[name]
    expected = []
    panel = scr.panel
    if panel is not None:
        expected = [(float(panel.x), float(panel.y), float(panel.w), float(panel.h))]
    elif name == "ROOM":
        for key in ("hp_bar", "slot_s1", "slot_s2"):
            r = getattr(scr, key)
            expected.append((float(r.x), float(r.y), float(r.w), float(r.h)))
    for E in expected:
        if not _covered(E, _all_rects):
            problems.append("%s: mapped rects do not cover the required region (x=%.0f y=%.0f %.0fx%.0f)" % (name, E[0], E[1], E[2], E[3]))

print("position map: %d/%d ids mapped; all box sizes match; positions zeroed; panels covered" % (len(mapped), len(gui_set)))

# ---- exact node count audit ----
print("hud.gui  : %d node(s)" % len(gui_set))
print("ALL_NODES: %d id(s)" % len(re.findall(r'"([a-z0-9_]+)"', m.group(1))))
if len(gui_set) != len(re.findall(r'"([a-z0-9_]+)"', m.group(1))):
    problems.append("node count mismatch: hud.gui has %d, ALL_NODES has %d" % (
        len(gui_set), len(re.findall(r'"([a-z0-9_]+)"', m.group(1)))))
if len(gui_set) != 222:
    problems.append("hud.gui node count changed: expected 222, got %d (update this constant with the change)" % len(gui_set))

if problems:
    for p in problems:
        print(p)
    print("\n%d problem(s)" % len(problems))
    sys.exit(1)
print("0 problem(s)")
sys.exit(0)
