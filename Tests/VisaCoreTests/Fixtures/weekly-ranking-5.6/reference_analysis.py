#!/usr/bin/env python3
"""Independent reference for the W2 weekly analysis (design weekly-report §4.10, §5, §6.5, page-5 changes).

Takes the W1 metrics of the report week and the week before from the W1 reference
(`../weekly-2026-10-19/reference_model.py`), applies the W2 rules (ADR 0022) and prints the result
in the canonical encoding of the W1 fixture README. Standard library only; no code shared with the
Swift side. Integer rules are written as integer comparisons, exactly as in Swift.

Usage:
  python3 reference_analysis.py <folder> <week_start YYYY-MM-DD> <data_until ISO-8601> > expected-analysis.json
"""

import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.dont_write_bytecode = True  # leave no __pycache__ in the W1 fixture folder
sys.path.insert(0, os.path.join(HERE, "..", "weekly-2026-10-19"))
import reference_model as w1  # noqa: E402

ANALYSIS = 1
MIN_ROUNDS = 5          # §5.1 (PerfMastery.minimumRounds)
LIST_SIZE = 5           # §5.3
MIN_DAYS = 2            # §5.3 / D5: still learning needs ≥ 2 days
MIN_QUALIFIED = 2       # §3 page 4: fewer than 2 qualified games → not ranked
WOW_MIN_ROUNDS = 5      # §4.10 rates
COUNT_MIN_DAYS = 4      # §4.10 counts and minutes
STAR_TOP_MIN = 3        # §5.4 bot.stars
MEMORISED_MIN = 10      # §5.5
WIN_MAX = 3             # §6.5
STREAK_MIN = 5
FIRST_TRY_EARLIER = 3
CLEAN_DAY_MIN = 5
NO_FUEL_MIN = 20

DEAL_FIELDS = ["gen", "level", "tolerance", "shape_trace_level", "trace_scaffold", "range", "count_voice", "english",
               "direction_coaching", "stop_coaching", "slant_enabled", "dot_style", "category_mix", "shape_mix"]
RESULT_FIELDS = ["guide_level"]
FAMILY_KINDS = {
    "lineMatch_": ["lineMatchGuidedStraight", "lineMatchGuidedBridge", "lineMatch"],
    "shapeTrace_": ["traceLines", "traceShapesDotted", "traceShapesArrows", "traceShapesFree"],
    "tapCount_": ["tapCountAll", "tapCountTrace", "tapCountPick", "tapCountAllEnglish", "tapCountTraceEnglish",
                  "tapCountPickEnglish"],
}
TIERS_QUALIFIED = ("going_well", "learning", "needs_practice")
REASON_ORDER = {"too_few": 0, "one_day": 1, "no_method": 2}


def text(v):
    """WeeklySignature.text: a field value as text; arrays, objects and null have none."""
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, int):
        return str(v)
    if isinstance(v, float):
        return w1.fmt(v)
    if isinstance(v, str):
        return v
    return None


def rank_of(kind):
    return w1.RANK.get(kind, sys.maxsize)


def catalog_key(kind):
    return (rank_of(kind), kind.encode("utf-8"))


# ---------------------------------------------------------------- §4.10 rules

def rate_change(k1, n1, k0, n0):
    if n1 < WOW_MIN_ROUNDS or n0 < WOW_MIN_ROUNDS:
        return None
    d = k1 * n0 - k0 * n1
    n = n1 * n0
    if 5 * abs(d) < n:
        return "same"
    k = k1 + k0
    m = n1 + n0
    lhs = float(d) * float(d) * float(m)
    rhs = float(k * (m - k)) * float(n)
    if lhs < rhs:
        return "unsure"
    return "up" if d > 0 else "down"


def count_change(cur, prev, days_cur, days_prev):
    if days_cur < COUNT_MIN_DAYS or days_prev < COUNT_MIN_DAYS or cur == prev:
        return None
    if abs(cur - prev) * 4 < prev:
        return None
    return "up" if cur > prev else "down"


def rate_json(k1, n1, k0, n0):
    return {"k1": k1, "n1": n1, "k0": k0, "n0": n0, "change": rate_change(k1, n1, k0, n0)}


def count_json(cur, prev, days_cur, days_prev, minutes=False):
    return {"current": cur / 60000 if minutes else cur, "previous": prev / 60000 if minutes else prev,
            "change": count_change(cur, prev, days_cur, days_prev)}


# ---------------------------------------------------------------- deal signatures and settings changes

def signatures(index, window):
    tallies = {}
    for position, d in enumerate(index.dealt):
        if not d.countable or not window.contains(d.event.ts):
            continue
        t = tallies.setdefault((d.kind, d.type), {"counts": {}, "follows": True})
        for field in DEAL_FIELDS:
            if field == "gen":
                gen = w1.string_value(d.event.get("gen"))
                value = "fixed_v0" if gen is None else gen
            else:
                value = text(d.event.get(field))
            if value is not None:
                tally(t, field, value, position)
        level = w1.int_value(d.event.get("level"))
        stars = w1.int_value(d.event.get("stars"))
        if level is not None and level != min(max(1 if stars is None else stars, 1), 3):
            t["follows"] = False
        res = index.result(d.round, window.cutoff)
        if res is not None:
            for field in RESULT_FIELDS:
                value = text(res.get(field))
                if value is not None:
                    tally(t, field, value, position)
    out = {}
    for key, t in tallies.items():
        dominant = {}
        for field, values in t["counts"].items():
            best = None
            for value, (count, last) in values.items():
                if best is None or count > best[1] or (count == best[1] and last > best[2]):
                    best = (value, count, last)
            dominant[field] = best[0]
        out[key] = {"dominant": dominant, "follows": t["follows"]}
    return out


def tally(t, field, value, position):
    values = t["counts"].setdefault(field, {})
    count = values[value][0] if value in values else 0
    values[value] = (count + 1, position)


def signature_changes(prev, cur):
    if prev is None or cur is None:
        return []
    out = []
    for field in DEAL_FIELDS + RESULT_FIELDS:
        if field == "level" and prev["follows"] and cur["follows"]:
            continue
        old, new = prev["dominant"].get(field), cur["dominant"].get(field)
        if old is not None and new is not None and old != new:
            out.append({"reason": "signature", "field": field, "old": old, "new": new})
    return out


def config_kinds(what, kind):
    if what == "assignment":
        return [kind] if kind is not None else []
    for prefix, kinds in FAMILY_KINDS.items():
        if what.startswith(prefix):
            return list(kinds)
    return []


def configs(events, cutoff):
    out = []
    for position, e in enumerate(events):
        if e.t != "config_change" or e.ts > cutoff:
            continue
        what = w1.string_value(e.get("what"))
        if not what:
            continue
        kind = w1.string_value(e.get("kind"))
        value = e.get("value")
        out.append({"position": position, "ts": e.ts, "date": w1.day_stamp(e.ts), "what": what, "kind": kind,
                    "value": text(value), "flag": value if isinstance(value, bool) else None,
                    "star": w1.int_value(e.get("star")) if what == "assignment" else None,
                    "kinds": config_kinds(what, kind)})
    return out


def star_shift(prev_row, row):
    if prev_row is None or prev_row["rounds"] <= 0 or row["rounds"] <= 0:
        return None
    p3, c3 = prev_row["stars"][2]["rounds"], row["stars"][2]["rounds"]
    p, c = prev_row["rounds"], row["rounds"]
    if 10 * abs(c3 * p - p3 * c) < 3 * c * p:
        return None
    return {"reason": "stars", "previous": p3, "previous_rounds": p, "current": c3, "current_rounds": c}


# ---------------------------------------------------------------- §5 ranking

def tier_of(row_type, est, zeroed, help_heavy):
    m, lo, hi = est["m"], est["lo"], est["hi"]
    if (m <= 0.35 and hi <= 0.55) or (row_type == "quiz" and zeroed >= 2 and m < 0.70) \
            or (row_type == "practice" and help_heavy and m < 0.70):
        return "needs_practice"
    if m >= 0.70 and lo >= 0.50:
        return "going_well"
    return "learning"


def largest_remainder(total, weights):
    s = sum(weights)
    if total <= 0 or s <= 0:
        return [0] * len(weights)
    slots = [total * w // s for w in weights]
    rems = [total * w % s for w in weights]
    order = sorted(range(len(weights)), key=lambda i: (-rems[i], i))
    left = total - sum(slots)
    for i in order:
        if left <= 0:
            break
        slots[i] += 1
        left -= 1
    return slots


def fill(slots, pools):
    take = [min(s, len(p)) for s, p in zip(slots, pools)]
    spare = sum(slots) - sum(take)
    for i, p in enumerate(pools):
        if spare <= 0:
            break
        extra = min(spare, len(p) - take[i])
        take[i] += extra
        spare -= extra
    return [p[:t] for p, t in zip(pools, take)]


def cmp_top(a, b):
    if a["low"] != b["low"]:
        return a["low"] > b["low"]
    if a["n"] != b["n"]:
        return a["n"] > b["n"]
    left, right = a["k"] * b["n"], b["k"] * a["n"]
    if left != right:
        return left > right
    return catalog_key(a["kind"]) < catalog_key(b["kind"])


def cmp_bottom(a, b):
    if a["high"] != b["high"]:
        return a["high"] < b["high"]
    if a["n"] != b["n"]:
        return a["n"] > b["n"]
    left, right = a["k"] * b["n"], b["k"] * a["n"]
    if left != right:
        return left < right
    return catalog_key(a["kind"]) < catalog_key(b["kind"])


def sort_by(items, before):
    """Insertion sort with a strict 'comes before' test (the orders are total; no ties remain)."""
    out = []
    for item in items:
        at = len(out)
        while at > 0 and before(item, out[at - 1]):
            at -= 1
        out.insert(at, item)
    return out


def rank(scores):
    qualified = [s for s in scores if s["tier"] in TIERS_QUALIFIED]
    quiz = [s for s in qualified if s["type"] == "quiz"]
    practice = [s for s in qualified if s["type"] == "practice"]
    weights = [len(quiz), len(practice)]
    top_size = min(LIST_SIZE, (len(qualified) + 1) // 2)
    top_slots = largest_remainder(top_size, weights)
    top = fill(top_slots, [sort_by([s for s in pool if s["tier"] != "needs_practice"], cmp_top)
                           for pool in (quiz, practice)])
    chosen = {(s["kind"], s["type"]) for pool in top for s in pool}
    cands = [sort_by([s for s in pool if (s["kind"], s["type"]) not in chosen
                      and s["tier"] in ("learning", "needs_practice") and s["days"] >= MIN_DAYS], cmp_bottom)
             for pool in (quiz, practice)]
    cand_count = len(cands[0]) + len(cands[1])
    bottom_size = min(LIST_SIZE, cand_count)
    bottom_slots = largest_remainder(bottom_size, weights)
    bottom = fill(bottom_slots, cands)
    chosen |= {(s["kind"], s["type"]) for pool in bottom for s in pool}
    also_well, also_learning, insufficient = [[], []], [[], []], []
    for t, pool in enumerate((quiz, practice)):
        rest = [s for s in pool if (s["kind"], s["type"]) not in chosen]
        also_well[t] = [s["kind"] for s in sort_by([s for s in rest if s["tier"] == "going_well"], cmp_top)]
        also_learning[t] = [s["kind"] for s in sort_by([s for s in rest if s["tier"] != "going_well"
                                                        and s["days"] >= MIN_DAYS], cmp_bottom)]
        for s in rest:
            if s["tier"] != "going_well" and s["days"] < MIN_DAYS:
                insufficient.append(entry(s, "one_day"))
    for s in scores:
        if s["tier"] not in TIERS_QUALIFIED:
            insufficient.append(entry(s, "no_method" if s["tier"] == "no_method" else "too_few"))
    insufficient.sort(key=lambda e: (0 if e["type"] == "quiz" else 1, REASON_ORDER[e["reason"]], -e["n"],
                                     catalog_key(e["kind"])))
    lists = lambda picked: {"quiz": [s["kind"] for s in picked[0]], "practice": [s["kind"] for s in picked[1]]}  # noqa
    return {
        "ranked": len(qualified) >= MIN_QUALIFIED,
        "qualified": {"quiz": len(quiz), "practice": len(practice)},
        "top": dict(lists(top), size=top_size, slots={"quiz": top_slots[0], "practice": top_slots[1]}),
        "still_learning": dict(lists(bottom), size=bottom_size, candidates=cand_count,
                               slots={"quiz": bottom_slots[0], "practice": bottom_slots[1]}),
        "also_well": {"quiz": also_well[0], "practice": also_well[1]},
        "also_learning": {"quiz": also_learning[0], "practice": also_learning[1]},
        "insufficient": insufficient,
    }


def entry(s, reason):
    return {"kind": s["kind"], "type": s["type"], "reason": reason, "n": s["n"], "k": s["k"],
            "days_played": s["days"], "more": max(0, MIN_ROUNDS - s["n"]) if reason == "too_few" else 0}


def placement(ranking, kind, row_type):
    for key, name in (("top", "top"), ("still_learning", "still_learning"), ("also_well", "also_well"),
                      ("also_learning", "also_learning")):
        if kind in ranking[key][row_type]:
            return name
    return "insufficient"


# ---------------------------------------------------------------- §6.5 wins

def learned_numeral(dealt, res):
    if w1.flag(res.get("guide_learned_before")) is not True:
        return None
    n = w1.int_value(res.get("numeral"))
    return n if n is not None else w1.int_value(dealt.get("numeral"))


def win_facts(index, rollup, window):
    resets = [c for c in index.cleared if c <= window.cutoff]
    reset = resets[-1] if resets else None
    f = {"answered": {}, "first_try": set(), "smooth": set(), "learned": set(), "learned_week": set()}
    for d in index.dealt:
        if not d.countable:
            continue
        ts = d.event.ts
        if ts < window.start:
            if reset is not None and ts < reset:
                continue
            res = index.result(d.round, window.start)
            if res is None:
                continue
            if d.type == "quiz":
                if (w1.int_value(res.get("answers")) or 0) > 0:
                    f["answered"][d.kind] = f["answered"].get(d.kind, 0) + 1
                    if res.get("first_try") is True:
                        f["first_try"].add(d.kind)
            elif w1.smooth_of(d.kind, res.fields) is True:
                f["smooth"].add(d.kind)
            n = learned_numeral(d.event, res)
            if n is not None:
                f["learned"].add(n)
        elif window.contains(ts):
            res = index.result(d.round, window.cutoff)
            if res is not None:
                n = learned_numeral(d.event, res)
                if n is not None:
                    f["learned_week"].add(n)
    reset_stamp = w1.day_stamp(reset) if reset is not None else None
    for stamp, summary in (rollup.get("days") or {}).items():
        if stamp >= window.day_stamps[0] or (reset_stamp is not None and stamp < reset_stamp):
            continue
        for key, stats in ((summary or {}).get("games") or {}).items():
            parts = key.split("|")
            if len(parts) > 3 and parts[3] == "guided":
                continue
            stats = stats or {}
            f["answered"][parts[0]] = f["answered"].get(parts[0], 0) + (w1.int_value(stats.get("answered")) or 0)
            if (w1.int_value(stats.get("first_try")) or 0) > 0:
                f["first_try"].add(parts[0])
    return f


def wins(cur, games, facts):
    out = []
    for kind in cur["new_kinds"]:
        out.append({"id": "win.newGame", "kind": kind})
    numerals = sorted(facts["learned_week"] - facts["learned"])
    if numerals:
        out.append({"id": "win.numeral", "numerals": numerals})
    best = None
    for row in cur["rows"]:
        if row["type"] != "quiz":
            continue
        run = longest = 0
        for r in cur["rounds"]:
            if r["kind"] == row["kind"] and r["type"] == "quiz" and r["answered"]:
                run = run + 1 if r["first_try"] else 0
                longest = max(longest, run)
        if longest >= STREAK_MIN and longest > (best[1] if best else 0):
            best = (row["kind"], longest)
    if best:
        out.append({"id": "win.streak", "kind": best[0], "run": best[1]})
    for g in games:
        if g["wow"]["change"] == "up" and not g["settings"]:
            out.append({"id": "win.rise", "kind": g["kind"], "type": g["type"], "k0": g["wow"]["k0"],
                        "n0": g["wow"]["n0"], "k1": g["wow"]["k1"], "n1": g["wow"]["n1"]})
    for row in cur["rows"]:
        if row["type"] == "practice" and row["smooth"] > 0 and row["kind"] not in facts["smooth"]:
            for r in cur["rounds"]:
                if r["kind"] == row["kind"] and r["type"] == "practice" and r["smooth"] is True:
                    out.append({"id": "win.firstSmooth", "kind": row["kind"], "day": r["day"]})
                    break
    for row in cur["rows"]:
        if row["type"] == "quiz" and row["first_try"] > 0 and row["kind"] not in facts["first_try"]:
            earlier = facts["answered"].get(row["kind"], 0)
            for r in cur["rounds"]:
                if r["kind"] != row["kind"] or r["type"] != "quiz" or not r["answered"]:
                    continue
                if r["first_try"]:
                    if earlier >= FIRST_TRY_EARLIER:
                        out.append({"id": "win.firstTry", "kind": row["kind"], "earlier": earlier, "day": r["day"]})
                    break
                earlier += 1
    clean = None
    for d in cur["days"]:
        if d["quiz_rounds"] >= CLEAN_DAY_MIN and d["counts"]["first_try"] == d["quiz_rounds"]:
            if d["quiz_rounds"] > (clean[1] if clean else 0):
                clean = (d["index"], d["quiz_rounds"])
    if clean:
        out.append({"id": "win.cleanDay", "day": clean[0], "rounds": clean[1]})
    zeroed = 0
    for row in cur["rows"]:
        if row["type"] == "quiz":
            zeroed += row["zeroed"]
    if cur["totals"]["quiz_rounds"] >= NO_FUEL_MIN and zeroed == 0:
        out.append({"id": "win.noFuelOut", "rounds": cur["totals"]["quiz_rounds"]})
    return out


# ---------------------------------------------------------------- the analysis

def days_played(m):
    return sum(1 for d in m["days"] if d["counts"]["rounds"] > 0 or d["plays"] > 0)


def game_ms(m):
    total = 0
    for d in m["days"]:
        total += d["quiz_ms"] + d["practice_ms"]
    return total


def video_ms(m):
    total = 0
    for d in m["days"]:
        total += d["video_ms"]
    return total


def row_nk(row):
    if row["type"] == "quiz":
        return row["answered"], row["first_try"]
    return row["smooth_defined"], row["smooth"]


def analyse(events, apps, rollup, window):
    excluded = w1.excluded_sessions(events)
    index = w1.Index(events, excluded, rollup)
    cur = w1.metrics(index, window)
    previous_window = window.shifted(-1)
    prev = w1.metrics(index, previous_window)
    sig_cur = signatures(index, window)
    sig_prev = signatures(index, previous_window)
    cfg = configs(events, window.cutoff)

    games, scores = [], []
    for row in cur["rows"]:
        key = (row["kind"], row["type"])
        prev_row = next((p for p in prev["rows"] if (p["kind"], p["type"]) == key), None)
        n, k = row_nk(row)
        if row["type"] == "quiz":
            has_method = not any(r["kind"] == row["kind"] and r["type"] == "quiz" and r["chance"] is None
                                 for r in cur["rounds"])
        else:
            has_method = row["family"] is not None
        help_heavy = row["helps_rounds"] > 0 and row["helps_total"] >= w1.HELP_HEAVY_MEAN * row["helps_rounds"]
        est = row["estimate"]
        if not has_method:
            tier = "no_method"
        elif n < MIN_ROUNDS or est is None:
            tier = "insufficient"
        else:
            tier = tier_of(row["type"], est, row["zeroed"], help_heavy)
        qualified = tier in TIERS_QUALIFIED
        scores.append({"kind": row["kind"], "type": row["type"], "n": n, "k": k, "days": row["days_played"],
                       "tier": tier, "low": est["lo"] if qualified else 0.0, "high": est["hi"] if qualified else 0.0})
        settings = []
        for c in cfg:
            if c["ts"] >= previous_window.start and row["kind"] in c["kinds"]:
                settings.append({"reason": "config", "what": c["what"], "value": c["value"], "star": c["star"],
                                 "date": c["date"]})
        settings += signature_changes(sig_prev.get(key), sig_cur.get(key))
        shift = star_shift(prev_row, row)
        if shift is not None:
            settings.append(shift)
        fixed = sig_cur.get(key, {"dominant": {}})["dominant"].get("gen") == "fixed_v0"
        star_rule = None
        if row["type"] == "quiz":
            st = row["stars"]
            n3, k3 = st[2]["answered"], st[2]["first_try"]
            n12, k12 = st[0]["answered"] + st[1]["answered"], st[0]["first_try"] + st[1]["first_try"]
            if n3 >= STAR_TOP_MIN and n12 > 0 and 10 * (k12 * n3 - k3 * n12) >= 3 * n12 * n3:
                star_rule = {"k3": k3, "n3": n3, "k12": k12, "n12": n12}
        k0, n0 = (0, 0) if prev_row is None else (row_nk(prev_row)[1], row_nk(prev_row)[0])
        games.append({
            "kind": row["kind"], "type": row["type"], "area": row["area"], "family": row["family"], "new": row["new"],
            "rounds": row["rounds"], "n": n, "k": k, "rate": k / n if n > 0 else None,
            "chance": w1.row_chance_mean(row), "m": est["m"] if est else None, "lo": est["lo"] if est else None,
            "hi": est["hi"] if est else None, "tier": tier, "placement": None, "days_played": row["days_played"],
            "zeroed": row["zeroed"], "help_heavy": help_heavy, "fixed_question": fixed,
            "memorised": row["type"] == "quiz" and fixed and n >= MEMORISED_MIN and 10 * k >= 9 * n,
            "stars": [c["rounds"] for c in row["stars"]], "star_rule": star_rule, "settings": settings,
            "wow": rate_json(k, n, k0, n0),
        })
    ranking = rank(scores)
    for g in games:
        g["placement"] = placement(ranking, g["kind"], g["type"])

    d1, d0 = days_played(cur), days_played(prev)
    comparison = {
        "baseline": prev["covered"] == 0,
        "previous_covered_days": prev["covered"],
        "days_played": count_json(d1, d0, d1, d0),
        "rounds": count_json(cur["totals"]["rounds"], prev["totals"]["rounds"], d1, d0),
        "game_min": count_json(game_ms(cur), game_ms(prev), d1, d0, minutes=True),
        "video_min": count_json(video_ms(cur), video_ms(prev), d1, d0, minutes=True),
        "quiz": rate_json(cur["totals"]["first_try"], cur["totals"]["answered"], prev["totals"]["first_try"],
                          prev["totals"]["answered"]),
        "practice": rate_json(cur["totals"]["smooth"], cur["totals"]["smooth_defined"], prev["totals"]["smooth"],
                              prev["totals"]["smooth_defined"]),
        "areas": [dict(rate_json(cur["areas"][a]["first_try"], cur["areas"][a]["answered"],
                                 prev["areas"][a]["first_try"], prev["areas"][a]["answered"]), area=a)
                  for a in w1.AREAS],
        "families": [dict(rate_json(cur["families"][f]["smooth"], cur["families"][f]["smooth_defined"],
                                    prev["families"][f]["smooth"], prev["families"][f]["smooth_defined"]), family=f)
                     for f in w1.FAMILIES],
        "clear_changes": [{"kind": g["kind"], "type": g["type"], "change": g["wow"]["change"]} for g in games
                          if g["wow"]["change"] in ("up", "down") and not g["settings"]],
    }
    candidates = wins(cur, games, win_facts(index, rollup, window))

    versions = {}
    for e in events:
        app = apps.get((e.launch, e.seq, e.ts), "")
        if not app or not window.contains(e.ts):
            continue
        day = window.day_index(e.ts)
        if day is None:
            continue
        seen = versions.get(app)
        if seen is None:
            versions[app] = [e.ts, day, day]
        else:
            seen[0] = min(seen[0], e.ts)
            seen[1] = min(seen[1], day)
            seen[2] = max(seen[2], day)
    version_list = [{"app": app, "first_day": v[1], "last_day": v[2]}
                    for app, v in sorted(versions.items(), key=lambda kv: (kv[1][0], kv[0].encode("utf-8")))]
    settings_list = []
    for c in cfg:
        if c["what"] == "assignment" or not window.contains(c["ts"]):
            continue
        old = None
        for earlier in cfg:
            if earlier["position"] < c["position"] and earlier["what"] == c["what"]:
                old = earlier["value"]
        settings_list.append({"date": c["date"], "what": c["what"], "old": old, "new": c["value"],
                              "kinds": c["kinds"]})
    toggles = {}
    for c in cfg:
        if c["what"] != "assignment" or not window.contains(c["ts"]) or c["kind"] is None or c["star"] is None \
                or c["flag"] is None:
            continue
        key = (c["kind"], c["star"])
        if key in toggles:
            toggles[key].update(last=c["flag"], position=c["position"], date=c["date"])
        else:
            toggles[key] = {"first": c["flag"], "last": c["flag"], "position": c["position"], "date": c["date"]}
    assignment = [{"date": t["date"], "kind": key[0], "star": key[1], "on": t["last"]}
                  for key, t in sorted(toggles.items(), key=lambda kv: kv[1]["position"]) if t["first"] == t["last"]]
    gen = []
    for row in cur["rows"]:
        key = (row["kind"], row["type"])
        old = sig_prev.get(key, {"dominant": {}})["dominant"].get("gen")
        new = sig_cur.get(key, {"dominant": {}})["dominant"].get("gen")
        if old is not None and new is not None and old != new:
            gen.append({"kind": row["kind"], "type": row["type"], "old": old, "new": new})
    changes = {
        "versions": version_list,
        "config": settings_list,
        "assignment": assignment,
        "gen": gen,
        "mix": {"quiz_rounds": count_json(cur["totals"]["quiz_rounds"], prev["totals"]["quiz_rounds"], d1, d0),
                "practice_rounds": count_json(cur["totals"]["practice_rounds"], prev["totals"]["practice_rounds"],
                                              d1, d0),
                "stars": {"current": list(cur["stars"]), "previous": list(prev["stars"])}},
        "excluded_rounds": {"total": sum(cur["excluded"].values()), "by_reason": dict(cur["excluded"]),
                            "open_at_cutoff": cur["open"]},
    }
    for g in games:
        for key in ("rate", "chance", "m", "lo", "hi"):
            g[key] = w1.num(g[key])
    return {
        "analysis": ANALYSIS, "builder": w1.BUILDER, "time_zone": "Asia/Hong_Kong",
        "week_start": window.day_stamps[0], "previous_week_start": previous_window.day_stamps[0],
        "data_until": w1.format_ts(window.cutoff),
        "pooled": {"quiz": float(cur["pooled_quiz"]), "practice": float(cur["pooled_practice"])},
        "games": games, "ranking": ranking, "comparison": comparison,
        "wins": candidates[:WIN_MAX], "win_candidates": candidates, "changes": changes,
    }


def read_folder(folder):
    """w1.read_store plus the envelope `app` per (launch, seq, ts), which the W1 reference drops."""
    events, skipped = w1.read_store(folder)
    apps = {}
    for name in sorted(os.listdir(folder)):
        if not (name.startswith("events-") and name.endswith(".jsonl")):
            continue
        with open(os.path.join(folder, name), encoding="utf-8") as f:
            for line in f.read().split("\n"):
                try:
                    obj = json.loads(line)
                except ValueError:
                    continue
                if isinstance(obj, dict):
                    launch = obj.get("launch") if isinstance(obj.get("launch"), str) else ""
                    seq = w1.int_value(obj.get("seq")) or 0
                    apps[(launch, seq, w1.parse_ts(obj.get("ts")))] = obj.get("app") if isinstance(obj.get("app"), str) else ""
    return events, apps, skipped


def main():
    if len(sys.argv) != 4:
        raise SystemExit(__doc__)
    folder, week_start, data_until = sys.argv[1:]
    events, apps, skipped = read_folder(folder)
    rollup_path = os.path.join(folder, "rollup-v1.json")
    rollup = {}
    if os.path.exists(rollup_path):
        with open(rollup_path, encoding="utf-8") as f:
            rollup = json.load(f)
    cutoff = w1.parse_ts(data_until)
    if cutoff is None:
        raise SystemExit("data_until must look like 2026-10-25T13:00:00.000Z")
    model = analyse(events, apps, rollup, w1.Window.containing(week_start, cutoff))
    sys.stderr.write("%d events, %d skipped lines\n" % (len(events), skipped))
    sys.stdout.write(w1.encode(model) + "\n")


if __name__ == "__main__":
    main()
