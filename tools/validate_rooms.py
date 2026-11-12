#!/usr/bin/env python3
"""Validate src/levels/rooms.lua. Run from the project root:  python tools/validate_rooms.py

Checks every room: 13 rows x 20 columns, solid outer border (torches 'T' allowed on the top row),
exactly one '@', only known characters, every torch has floor to its south, every floor cell is
reachable from '@', at least one enemy, enemies >= 4 tiles from '@', no enemies in the bottom two
interior rows (the HUD covers them). Exit code 0 = all rooms OK.
"""
import re, sys
from collections import deque

COLS, ROWS = 20, 13
SOLID = set("#OT")
KNOWN = set("#.OT@wscbpdWSCBQX")
ENEMIES = set("wscbpdWSCBQX")
HOME_PATH = "src/levels/home.lua"

def load(path="src/levels/rooms.lua"):
    src = open(path, encoding="utf-8").read()
    rooms = []
    for m in re.finditer(r'name\s*=\s*"([^"]+)",\s*rows\s*=\s*\{(.*?)\}', src, re.S):
        rooms.append((m.group(1), re.findall(r'"([^"]*)"', m.group(2))))
    return rooms

def load_home():
    try:
        src = open(HOME_PATH, encoding="utf-8").read()
    except OSError:
        print("no home file: %s" % HOME_PATH)
        sys.exit(1)
    mname = re.search(r'name\s*=\s*"([^"]+)"', src)
    mrows = re.search(r'rows\s*=\s*\{(.*?)\}', src, re.S)
    if not mname or not mrows:
        print("no home name/rows found in %s" % HOME_PATH)
        sys.exit(1)
    return (mname.group(1), re.findall(r'"([^"]*)"', mrows.group(1)))

def check_peaceful(name, rows):
    """The home room: same geometry as a room, but enemies are optional.

    Must still have a closed border, exactly one '@', reachable floor, torches
    over floor, and any enemy (if one is ever added) 4+ tiles from '@'.
    """
    errs = []
    if len(rows) != ROWS: return ["needs %d rows, has %d" % (ROWS, len(rows))]
    for i, r in enumerate(rows):
        if len(r) != COLS: errs.append("row %d has %d chars (need %d)" % (i + 1, len(r), COLS))
        bad = set(r) - KNOWN
        if bad: errs.append("row %d has unknown chars %s" % (i + 1, sorted(bad)))
    if errs: return errs
    for c in range(COLS):
        if rows[0][c] not in "#T": errs.append("top border broken at col %d" % (c + 1))
        if rows[-1][c] != "#": errs.append("bottom border broken at col %d" % (c + 1))
    for r in range(ROWS):
        if rows[r][0] != "#" or rows[r][-1] != "#": errs.append("side border broken at row %d" % (r + 1))
    starts = [(r, c) for r in range(ROWS) for c in range(COLS) if rows[r][c] == "@"]
    if len(starts) != 1: errs.append("needs exactly one '@' (found %d)" % len(starts))
    for r in range(ROWS):
        for c in range(COLS):
            if rows[r][c] == "T" and (r + 1 >= ROWS or rows[r + 1][c] in SOLID):
                errs.append("torch at row %d col %d has no floor to its south" % (r + 1, c + 1))
    free = lambda r, c: 0 <= r < ROWS and 0 <= c < COLS and rows[r][c] not in SOLID
    if starts:
        seen, q = {starts[0]}, deque([starts[0]])
        while q:
            r, c = q.popleft()
            for dr, dc in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                n = (r + dr, c + dc)
                if free(*n) and n not in seen: seen.add(n); q.append(n)
        unreachable = {(r, c) for r in range(ROWS) for c in range(COLS) if free(r, c)} - seen
        if unreachable: errs.append("unreachable floor cells (row,col): %s" % sorted((r + 1, c + 1) for r, c in unreachable)[:8])
    enemies = [(r, c, rows[r][c]) for r in range(ROWS) for c in range(COLS) if rows[r][c] in ENEMIES]
    if enemies:
        for r, c, ch in enemies:
            if starts and ((r - starts[0][0]) ** 2 + (c - starts[0][1]) ** 2) ** 0.5 < 4:
                errs.append("enemy '%s' at row %d col %d is closer than 4 tiles to '@'" % (ch, r + 1, c + 1))
            if r >= ROWS - 3: errs.append("enemy '%s' at row %d is under the HUD (use rows 2-10)" % (ch, r + 1))
    return errs

def check(name, rows):
    errs = []
    if len(rows) != ROWS: return ["needs %d rows, has %d" % (ROWS, len(rows))]
    for i, r in enumerate(rows):
        if len(r) != COLS: errs.append("row %d has %d chars (need %d)" % (i + 1, len(r), COLS))
        bad = set(r) - KNOWN
        if bad: errs.append("row %d has unknown chars %s" % (i + 1, sorted(bad)))
    if errs: return errs
    for c in range(COLS):
        if rows[0][c] not in "#T": errs.append("top border broken at col %d" % (c + 1))
        if rows[-1][c] != "#": errs.append("bottom border broken at col %d" % (c + 1))
    for r in range(ROWS):
        if rows[r][0] != "#" or rows[r][-1] != "#": errs.append("side border broken at row %d" % (r + 1))
    starts = [(r, c) for r in range(ROWS) for c in range(COLS) if rows[r][c] == "@"]
    if len(starts) != 1: errs.append("needs exactly one '@' (found %d)" % len(starts))
    for r in range(ROWS):
        for c in range(COLS):
            if rows[r][c] == "T" and (r + 1 >= ROWS or rows[r + 1][c] in SOLID):
                errs.append("torch at row %d col %d has no floor to its south" % (r + 1, c + 1))
    free = lambda r, c: 0 <= r < ROWS and 0 <= c < COLS and rows[r][c] not in SOLID
    if starts:
        seen, q = {starts[0]}, deque([starts[0]])
        while q:
            r, c = q.popleft()
            for dr, dc in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                n = (r + dr, c + dc)
                if free(*n) and n not in seen: seen.add(n); q.append(n)
        unreachable = {(r, c) for r in range(ROWS) for c in range(COLS) if free(r, c)} - seen
        if unreachable: errs.append("unreachable floor cells (row,col): %s" % sorted((r + 1, c + 1) for r, c in unreachable)[:8])
    enemies = [(r, c, rows[r][c]) for r in range(ROWS) for c in range(COLS) if rows[r][c] in ENEMIES]
    if not enemies: errs.append("no enemies")
    for r, c, ch in enemies:
        if starts and ((r - starts[0][0]) ** 2 + (c - starts[0][1]) ** 2) ** 0.5 < 4:
            errs.append("enemy '%s' at row %d col %d is closer than 4 tiles to '@'" % (ch, r + 1, c + 1))
        if r >= ROWS - 3: errs.append("enemy '%s' at row %d is under the HUD (use rows 2-10)" % (ch, r + 1))
    return errs

def main():
    rooms = load()
    if not rooms:
        print("no rooms found in src/levels/rooms.lua"); return 1
    bad = 0
    for i, (name, rows) in enumerate(rooms, 1):
        errs = check(name, rows)
        n = sum(ch in ENEMIES for r in rows for ch in r)
        print("%s room %d %-20s enemies=%d" % ("OK  " if not errs else "FAIL", i, name, n))
        for e in errs: print("       -", e)
        bad += len(errs)
    hname, hrows = load_home()
    herrs = check_peaceful(hname, hrows)
    henemies = sum(ch in ENEMIES for r in hrows for ch in r)
    print("%s home %s enemies=%d (peaceful)" % ("OK  " if not herrs else "FAIL", hname, henemies))
    for e in herrs: print("       -", e)
    bad += len(herrs)
    print("\n%d room(s), %d problem(s)" % (len(rooms) + 1, bad))
    return 1 if bad else 0

if __name__ == "__main__":
    sys.exit(main())
