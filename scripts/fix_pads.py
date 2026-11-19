#!/usr/bin/env python3
"""One-off data migration for 0.4.0: gives every landing pad a flat surface wide enough for the skids
and room for the waiting people at its edge. Kept in the repo for reference; running it twice is harmless."""
import json, glob, math, os
D = os.path.join(os.path.dirname(__file__), "..", "Sources", "RotorwachtCore", "Missions")

def gh(t, x):
    if x <= t[0][0]: return t[0][1]
    if x >= t[-1][0]: return t[-1][1]
    for a, b in zip(t, t[1:]):
        if a[0] <= x <= b[0]:
            u = (x - a[0]) / (b[0] - a[0]); s = u * u * (3 - 2 * u)
            return a[1] + (b[1] - a[1]) * s

def r10(v): return int(math.ceil(v / 10.0) * 10)

for f in sorted(glob.glob(os.path.join(D, "*.json"))):
    raw = open(f).read()
    m = json.loads(raw)
    t = [list(p) for p in m["terrain"]]
    for p in m["rescuePoints"]:
        if p.get("access") == "winch":
            continue
        c = (p["people"] + 1) // 2
        p["width"] = max(p["width"], r10(2 * (54 + 12 * c)), 130)
        x, w, top = p["x"], p["width"], p["top"]
        if p["kind"] not in ("island",):
            continue
        if m.get("look") == "town":
            # street plaza between two houses: widen the valley floor, keep the walls steep
            k = next(i for i in range(1, len(t) - 2) if t[i][1] <= top + 1 and t[i + 1][1] <= top + 1 and t[i][0] <= x <= t[i + 1][0])
            hl, hr = t[k - 1][1], t[k + 2][1]
            xa, xb = x - w / 2 - 12 - 18, x + w / 2 + 12 + 18
            t[k - 1:k + 3] = [[xa, hl], [xa + 18, top], [xb - 18, top], [xb, hr]]
            continue
        sh = 45
        xa, xb = x - w / 2 - sh, x + w / 2 + sh
        ya, yb = gh(t, xa), gh(t, xb)
        t = [q for q in t if q[0] < xa or q[0] > xb]
        t += [[xa, round(ya, 1)], [x - w / 2, top], [x + w / 2, top], [xb, round(yb, 1)]]
        t.sort(key=lambda q: q[0])
    m["terrain"] = t
    import re
    out = json.dumps(m, ensure_ascii=False, indent=1)
    out = re.sub(r"\[\s+(-?[\d.]+),\s+(-?[\d.]+)\s+\]", r"[\1, \2]", out)
    open(f, "w").write(out + "\n")
    print(os.path.basename(f), "ok")
