#!/usr/bin/env python3
"""Writes the synthetic stats folder for the W2 ranking golden fixture (weekly-report design §5.6).

The report week 2026-10-19 … 25 is the synthetic week of the design's sample report: the per-kind
schedule, failures, stars, practice extras and random draws below are copied from
`visa-games-design/weekly-report/mockups/make_sample.py` (`QUIZ_SPEC`, `PRACTICE_SPEC`,
`build_rounds`), so the W1 metrics of these records give the §5.6 table. The previous week
2026-10-12 … 18 reproduces the sample's `PREV` (n, k) per kind, with the same stars and settings,
except that 連一連 tolerance changes standard → wide on Wednesday 2026-10-21 (sample
`CONFIG_CHANGES`). Made-up records only, shaped like the files `PerfEventStore` writes: one
`events-YYYY-MM-DD.jsonl` per HKT day (sorted-key compact JSON lines). No rollup file.
Deterministic: re-running rewrites the same bytes. Then run `reference_analysis.py` (README.md).

Usage: python3 make_fixture.py [folder]   (default: this script's folder)
"""

import json
import math
import os
import sys
from datetime import datetime, timedelta, timezone

HKT = timezone(timedelta(hours=8))
UTC = timezone.utc


def at(day, clock):
    """'2026-10-19', '18:05:30' (HKT) -> aware UTC datetime."""
    y, m, d = (int(p) for p in day.split("-"))
    hh, mm, ss = (int(p) for p in clock.split(":"))
    return datetime(y, m, d, hh, mm, ss, tzinfo=HKT).astimezone(UTC)


def iso(ts):
    return ts.strftime("%Y-%m-%dT%H:%M:%S.") + "%03d" % (ts.microsecond // 1000) + "Z"


class Log:
    """One app process at a time (launch id, seq, mono), like the recorder."""

    def __init__(self):
        self.files = {}
        self.launch = None
        self.app = None
        self.seq = 0
        self.launched_at = None
        self.session = ""

    def emit(self, t, ts, fields=None, actor="child", mode="lock", session=None):
        self.seq += 1
        obj = dict(fields or {})
        obj.update({
            "v": 1, "t": t, "ts": iso(ts), "tz": "+08:00",
            "mono": round(40.0 + (ts - self.launched_at).total_seconds(), 3),
            "launch": self.launch, "seq": self.seq, "app": self.app, "actor": actor, "mode": mode,
            "session": self.session if session is None else session,
        })
        line = json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
        self.files.setdefault(ts.astimezone(HKT).strftime("%Y-%m-%d"), []).append(line)

    def start(self, launch, ts, app, session):
        self.launch, self.app, self.seq, self.launched_at = launch, app, 0, ts
        self.session = session
        self.emit("session_start", ts, {"reason": "launch"}, actor="system")
        self.emit("app_launch", ts, {"build": app}, actor="system")

    def new_session(self, session, ts, reason="idle_gap", actor="child", mode="lock"):
        self.session = session
        self.emit("session_start", ts, {"reason": reason}, actor=actor, mode=mode)

    def write(self, folder):
        for name in os.listdir(folder):
            if name.startswith("events-") and name.endswith(".jsonl"):
                os.remove(os.path.join(folder, name))
        for day in sorted(self.files):
            with open(os.path.join(folder, "events-%s.jsonl" % day), "w", encoding="utf-8", newline="") as f:
                f.write("".join(line + "\n" for line in self.files[day]))


log = Log()

# ---------------------------------------------------------------------------------------------
# The sample week, copied from make_sample.py (design repository) with its random draws.
# ---------------------------------------------------------------------------------------------
CATALOG_ORDER = [
    "twoPictureChoose", "findTheSame", "countVehicles", "sequenceShortToLong", "halfMatch", "shapeCousin",
    "capacityCompare", "moreFewer", "shadowMatch", "emptyBay", "lineMatchGuidedStraight", "lineMatchGuidedBridge",
    "lineMatch", "traceLines", "traceShapesDotted", "traceShapesArrows", "traceShapesFree", "tapCountAll",
    "tapCountTrace", "tapCountPick", "tapCountAllEnglish", "tapCountTraceEnglish", "tapCountPickEnglish",
    "tapLetterAll", "tapLetterWrite",
]
DAYS = ["2026-10-19", "2026-10-20", "2026-10-21", "2026-10-22", "2026-10-23", "2026-10-24", "2026-10-25"]
PREV_DAYS = ["2026-10-12", "2026-10-13", "2026-10-14", "2026-10-15", "2026-10-16", "2026-10-17", "2026-10-18"]
SESSIONS = [2, 3, 0, 2, 2, 4, 3]
VIDEO_FACTOR = [0.88, 0.90, 0.0, 0.92, 0.85, 0.90, 0.88]
FIXED = {"twoPictureChoose", "sequenceShortToLong", "halfMatch", "shapeCousin", "capacityCompare", "moreFewer",
         "shadowMatch", "emptyBay"}

QUIZ_SPEC = {
    "capacityCompare": ([2, 2, 0, 2, 2, 2, 2], {4: 1}, ["smaller"]),
    "halfMatch": ([2, 2, 0, 2, 1, 2, 2], {6: 1}, ["same_color", "long_vehicle"]),
    "shadowMatch": ([1, 2, 0, 2, 1, 2, 1], {}, []),
    "sequenceShortToLong": ([1, 1, 0, 2, 1, 2, 1], {3: 2}, ["rank_error:1", "screen_order"]),
    "findTheSame": ([2, 2, 0, 1, 1, 2, 2], {1: 1, 5: 2, 8: 1}, ["same_shape", "diff_color"]),
    "emptyBay": ([1, 1, 0, 2, 1, 2, 2], {0: 1, 4: 2, 7: 1}, ["occupied", "vehicle_attraction"]),
    "moreFewer": ([2, 1, 0, 2, 1, 2, 2], {1: 1, 3: 2, 6: 1, 8: 1}, ["fewer", "smaller_vehicles"]),
    "lineMatch": ([1, 1, 0, 1, 1, 2, 2], {2: 1, 4: 2, 6: 2, 7: 1}, []),
    "countVehicles": ([1, 2, 0, 2, 2, 4, 3], {0: 1, 2: 2, 3: 1, 5: 2, 7: 3, 8: 1, 10: 2, 12: 2}, None),
    "shapeCousin": ([0, 1, 0, 0, 0, 1, 2], {}, []),
    "twoPictureChoose": ([0, 0, 0, 0, 0, 1, 1], {}, []),
}
COUNT_TAGS = ["over_by_1", "under_by_1", "over_by_1", "over_by_1", "under_by_1", "over_by_1", "under_by_1",
              "over_by_1", "over_by_1", "under_by_1", "over_by_1", "under_by_1", "over_by_1", "under_by_1"]
STAR_PATTERN = [1, 1, 2, 1, 1, 3, 1, 2, 1, 1, 2, 1, 3, 1]
LINEMATCH_STARS = [1, 2, 1, 2, 3, 1, 2, 3]
CHANCE = {"capacityCompare": 0.5, "moreFewer": 0.5, "twoPictureChoose": 0.5, "sequenceShortToLong": 1 / 24}

PRACTICE_SPEC = {
    "traceShapesArrows": ([1, 2, 0, 1, 1, 2, 2], [0, 3]),
    "traceShapesDotted": ([1, 1, 0, 2, 1, 2, 1], [2]),
    "traceLines": ([1, 1, 0, 1, 1, 1, 1], []),
    "tapCountAll": ([1, 1, 0, 1, 1, 1, 1], [1]),
    "tapCountAllEnglish": ([1, 1, 0, 1, 1, 2, 1], [4]),
    "tapCountTrace": ([1, 1, 0, 2, 1, 1, 1], None),
    "tapCountTraceEnglish": ([0, 0, 0, 0, 0, 2, 1], None),
    "lineMatchGuidedStraight": ([1, 1, 0, 1, 1, 1, 1], [3]),
    "lineMatchGuidedBridge": ([0, 1, 0, 1, 0, 2, 1], None),
}
TRACE_ROUNDS = {
    "tapCountTrace": [(3, 0, 1), (4, 3, 0), (5, 0, 1), (6, 3, 0), (4, 2, 0), (6, 3, 0), (3, 0, 1)],
    "tapCountTraceEnglish": [(2, 2, 0), (4, 3, 0), (2, 0, 0)],
}
BRIDGE_OFF_PATH = [8, 1, 13, 13, 1]
SHAPE_TRACE = {"traceLines", "traceShapesDotted", "traceShapesArrows"}
GUIDED_ROADS = {"lineMatchGuidedStraight", "lineMatchGuidedBridge"}
TAP_ALL = {"tapCountAll", "tapCountAllEnglish"}
TAP_TRACE = {"tapCountTrace", "tapCountTraceEnglish"}

# The previous week: kind -> (n, k), sample `PREV`.
PREV = {
    "countVehicles": (16, 7), "capacityCompare": (10, 9), "halfMatch": (9, 8), "shadowMatch": (6, 5),
    "sequenceShortToLong": (7, 5), "findTheSame": (8, 5), "emptyBay": (8, 4), "moreFewer": (9, 6),
    "lineMatch": (6, 3), "shapeCousin": (3, 3), "twoPictureChoose": (4, 4),
    "traceShapesArrows": (6, 3), "traceShapesDotted": (9, 6), "traceLines": (8, 7), "tapCountAll": (5, 4),
    "tapCountAllEnglish": (4, 3), "tapCountTrace": (6, 2), "lineMatchGuidedStraight": (4, 3),
    "lineMatchGuidedBridge": (2, 1),
}

# Settings carried by every deal (constant across both weeks except 連一連 tolerance).
QUIZ_SLOTS = {
    "twoPictureChoose": ["opt-fire", "opt-hktaxi"], "halfMatch": ["half-bus", "half-taxi", "half-tanker"],
    "shapeCousin": ["shape-cone", "shape-wheel", "shape-toolbox"], "capacityCompare": ["cap-bus", "cap-taxi"],
    "moreFewer": ["lot-left", "lot-right"], "shadowMatch": ["shadow-fire", "shadow-hero", "shadow-truck"],
    "emptyBay": ["bay-a", "bay-b", "bay-c"],
    "sequenceShortToLong": ["seq-taxi", "seq-van", "seq-bus", "seq-tram"],
}
CATEGORY_MIX = "numbers:35,body:30,animals:20,zodiac:15"
SHAPE_MIX = "circle:45,square:35,triangle:20"
PINNED_LEVEL = {"traceLines": 1, "traceShapesDotted": 1, "traceShapesArrows": 2, "lineMatchGuidedStraight": 1,
                "lineMatchGuidedBridge": 2, "tapCountAll": 1, "tapCountAllEnglish": 1, "tapCountTrace": 2,
                "tapCountTraceEnglish": 2}


def fnv1a64(text):
    h = 0xcbf29ce484222325
    for byte in text.encode("utf-8"):
        h ^= byte
        h = (h * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF
    return h


def _lcg(seed):
    state = fnv1a64(seed) & 0x7FFFFFFF
    while True:
        state = (1103515245 * state + 12345) & 0x7FFFFFFF
        yield state


def smooth(kind, res):
    """design.md §4.5 (WeeklySmooth); every field is present in this fixture."""
    if res.get("outcome") != "solved":
        return None
    if kind in SHAPE_TRACE:
        return (res["shapes_done"] == res["shapes_total"] and res["wrong_start"] == 0
                and res["reverse_direction"] == 0 and res["off_path_count"] <= res["shapes_total"])
    if kind in GUIDED_ROADS:
        return res["roads"] == res["roads_total"] and res["wrong_start"] == 0 and res["off_path_count"] <= 1
    if kind in TAP_ALL:
        return res["recount_attempts"] == 0
    if kind in TAP_TRACE:
        return res["recount_attempts"] == 0 and res["guide_clean"] == 1
    return None


def build_rounds():
    """make_sample.build_rounds, unchanged apart from the comments."""
    rounds = []
    for kind, (per_day, fails, tags) in QUIZ_SPEC.items():
        rng = _lcg(kind)
        stars_seq = LINEMATCH_STARS if kind == "lineMatch" else STAR_PATTERN
        i = wrong_i = 0
        for day, count in enumerate(per_day):
            for _ in range(count):
                stars = stars_seq[i % len(stars_seq)]
                misses = fails.get(i, 0)
                if kind == "countVehicles" and misses == 3:
                    stars = 1  # 5 → 2 → 1 → 0: fuel ran out
                pending = 5 * stars
                for _m in range(misses):
                    pending //= 2
                zeroed = pending == 0
                wrong_tags = []
                for _m in range(misses):
                    if kind == "countVehicles":
                        wrong_tags.append([COUNT_TAGS[wrong_i]])
                    elif tags:
                        wrong_tags.append(list(tags))
                    wrong_i += 1
                active = 11000 + next(rng) % 14000 + misses * 3500
                if kind == "lineMatch":
                    chance = 1 / math.factorial(stars + 1)
                elif kind == "sequenceShortToLong":
                    chance = 1 / 24
                else:
                    chance = CHANCE.get(kind, 1 / 3)
                rounds.append({
                    "round": "%s-%02d" % (kind, i), "kind": kind, "day": day, "stars": stars, "type": "quiz",
                    "outcome": "zeroed" if zeroed else "solved", "first_try": misses == 0 and not zeroed,
                    "misses": misses, "answers": misses + (0 if zeroed else (4 if kind == "sequenceShortToLong" else 1)),
                    "hint_used": misses >= 2, "assisted": misses >= 2 and not zeroed,
                    "pending_start": 5 * stars, "earned_min": 0 if zeroed else pending,
                    "active_ms": active, "total_ms": active + misses * 10000 + 6000, "chance": chance,
                    "wrong_tags": wrong_tags, "fast_wrongs": 1 if (kind == "countVehicles" and i in (2, 7, 10)) else 0,
                    "tolerance": ("standard" if day < 2 else "wide") if kind == "lineMatch" else None,
                })
                i += 1
    for kind, (per_day, rough) in PRACTICE_SPEC.items():
        rng = _lcg(kind)
        i = 0
        for day, count in enumerate(per_day):
            for _ in range(count):
                stars = STAR_PATTERN[(i + 3) % len(STAR_PATTERN)]
                active = 42000 + next(rng) % 60000
                res = {"round": "%s-%02d" % (kind, i), "kind": kind, "day": day, "stars": stars, "type": "practice",
                       "outcome": "solved", "first_try": None, "misses": 0, "answers": 0, "hint_used": False,
                       "assisted": False, "pending_start": 5 * stars, "earned_min": 5 * stars,
                       "active_ms": active, "total_ms": active + 9000, "chance": None, "wrong_tags": [],
                       "fast_wrongs": 0}
                if kind in SHAPE_TRACE:
                    total = 4 if kind == "traceShapesArrows" else 3
                    bad = i in rough
                    res.update({"shapes_total": total, "shapes_done": total,
                                "off_path_count": (total + 3) if (bad and kind == "traceShapesArrows" and i == 3) else (next(rng) % 2 + (1 if i % 3 == 0 else 0)),
                                "wrong_start": 1 if (bad and kind == "traceShapesArrows" and i == 0) else 0,
                                "reverse_direction": 1 if (bad and kind == "traceShapesDotted") else 0,
                                "lifts": next(rng) % 4, "mean_dev_u": round(6 + (next(rng) % 50) / 10, 1)})
                elif kind in TAP_ALL:
                    res.update({"recount_attempts": 1 if i in rough else 0, "double_taps": next(rng) % 2,
                                "target": 3 + next(rng) % 6})
                elif kind in TAP_TRACE:
                    numeral, helps, learned = TRACE_ROUNDS[kind][i]
                    res.update({"recount_attempts": 0, "numeral": numeral, "guide_helps": helps,
                                "guide_clean": 1 if helps == 0 else 0, "guide_learned_before": learned,
                                "guide_level": "standard", "guide_stalls": max(0, helps - 1)})
                elif kind in GUIDED_ROADS:
                    off = BRIDGE_OFF_PATH[i] if kind == "lineMatchGuidedBridge" else (3 if i in rough else i % 2)
                    res.update({"roads": 3, "roads_total": 3, "off_path_count": off, "wrong_start": 0,
                                "tolerance": "standard" if day < 2 else "wide"})
                res["smooth"] = smooth(kind, res)
                rounds.append(res)
                i += 1
    rounds.sort(key=lambda r: (r["day"], CATALOG_ORDER.index(r["kind"]), r["round"]))
    return rounds


def build_previous_rounds():
    """The previous week: PREV (n, k) per kind over all 7 days, same stars and settings."""
    rounds = []
    for kind, (n, k) in PREV.items():
        quiz = kind in QUIZ_SPEC
        offset = CATALOG_ORDER.index(kind) % 7
        fails = {int((j + 0.5) * n / (n - k)) for j in range(n - k)}
        assert len(fails) == n - k, kind
        rng = _lcg("prev:" + kind)
        for i in range(n):
            day = (offset + i) % 7
            failed = i in fails
            if quiz:
                stars = (LINEMATCH_STARS if kind == "lineMatch" else STAR_PATTERN)[i % 14 if kind != "lineMatch" else i % 8]
                active = 12000 + next(rng) % 12000
                misses = 1 if failed else 0
                pending = 5 * stars // (2 if failed else 1)
                tags = QUIZ_SPEC[kind][2]
                wrong_tags = ([["over_by_1"]] if kind == "countVehicles" else [list(tags)] if tags else [[]]) if failed else []
                rounds.append({
                    "round": "p-%s-%02d" % (kind, i), "kind": kind, "day": day, "stars": stars, "type": "quiz",
                    "outcome": "solved", "first_try": not failed, "misses": misses,
                    "answers": misses + (4 if kind == "sequenceShortToLong" else 1), "hint_used": False,
                    "assisted": False, "pending_start": 5 * stars, "earned_min": pending, "active_ms": active,
                    "total_ms": active + misses * 10000 + 6000, "wrong_tags": wrong_tags, "fast_wrongs": 0,
                    "tolerance": "standard" if kind == "lineMatch" else None,
                })
            else:
                stars = STAR_PATTERN[(i + 3) % 14]
                active = 45000 + next(rng) % 50000
                res = {"round": "p-%s-%02d" % (kind, i), "kind": kind, "day": day, "stars": stars, "type": "practice",
                       "outcome": "solved", "first_try": None, "misses": 0, "answers": 0, "hint_used": False,
                       "assisted": False, "pending_start": 5 * stars, "earned_min": 5 * stars, "active_ms": active,
                       "total_ms": active + 9000, "wrong_tags": [], "fast_wrongs": 0}
                if kind in SHAPE_TRACE:
                    total = 4 if kind == "traceShapesArrows" else 3
                    res.update({"shapes_total": total, "shapes_done": total, "off_path_count": i % 2,
                                "wrong_start": 1 if failed else 0, "reverse_direction": 0, "lifts": i % 3,
                                "mean_dev_u": 7.5})
                elif kind in TAP_ALL:
                    res.update({"recount_attempts": 1 if failed else 0, "double_taps": i % 2, "target": 3 + i % 6})
                elif kind in TAP_TRACE:
                    numeral = [3, 4, 5, 6, 4, 3][i % 6]
                    helps = 2 if failed else 0
                    res.update({"recount_attempts": 0, "numeral": numeral, "guide_helps": helps,
                                "guide_clean": 0 if failed else 1, "guide_learned_before": 0,
                                "guide_level": "standard", "guide_stalls": max(0, helps - 1)})
                elif kind in GUIDED_ROADS:
                    res.update({"roads": 3, "roads_total": 3, "off_path_count": 3 if failed else i % 2,
                                "wrong_start": 0, "tolerance": "standard"})
                res["smooth"] = smooth(kind, res)
                rounds.append(res)
    rounds.sort(key=lambda r: (r["day"], CATALOG_ORDER.index(r["kind"]), r["round"]))
    return rounds


# ---------------------------------------------------------------------------------------------
# Records
# ---------------------------------------------------------------------------------------------
def dealt_fields(r, deal_mode="off"):
    kind, stars = r["kind"], r["stars"]
    out = {"round": r["round"], "kind": kind, "item": "%s.item" % kind, "stars": stars, "pending_start": 5 * stars,
           "pool": [kind], "deal_mode": deal_mode}
    if kind in FIXED:
        out.update({"gen": "fixed_v0", "slots": QUIZ_SLOTS[kind]})
    elif kind == "countVehicles":
        out.update({"gen": "variants_v1", "level": stars, "slots": ["count-2", "count-3", "count-4"]})
    elif kind == "findTheSame":
        out.update({"gen": "variants_v1", "level": stars, "slots": ["find-a", "find-b", "find-c"]})
    elif kind == "lineMatch":
        out.update({"gen": "variants_v1", "level": stars, "match_mode": "free", "pairs": stars + 1,
                    "category": "numbers", "category_mix": CATEGORY_MIX, "tolerance": r["tolerance"],
                    "slots": ["r%d" % j for j in range(stars + 1)]})
    elif kind in SHAPE_TRACE:
        level = PINNED_LEVEL[kind]
        out.update({"gen": "variants_v1", "level": level, "match_mode": "guided", "practice": "shape_trace",
                    "shape_trace_level": "L%d" % level, "tolerance": "standard", "direction_coaching": True,
                    "stop_coaching": True, "slant_enabled": False, "dot_style": "dots", "scene": "garage",
                    "slots": ["s0", "s1", "s2"]})
        if kind != "traceLines":
            out["shape_mix"] = SHAPE_MIX
    elif kind in GUIDED_ROADS:
        out.update({"gen": "variants_v1", "level": PINNED_LEVEL[kind], "match_mode": "guided", "pairs": 3,
                    "category": "numbers", "category_mix": CATEGORY_MIX, "tolerance": r["tolerance"],
                    "slots": ["r0", "r1", "r2"]})
    elif kind in TAP_ALL or kind in TAP_TRACE:
        target = r.get("numeral") or r.get("target") or 4
        out.update({"gen": "variants_v1", "level": PINNED_LEVEL[kind], "match_mode": "guided",
                    "practice": "tap_count", "target": target, "cars": target, "scene": "site",
                    "count_voice": True, "english": True, "range": 10,
                    "slots": ["bay-%d" % j for j in range(target)]})
        if kind in TAP_TRACE:
            out.update({"numeral": target, "strokes": 1, "trace_scaffold": "dots", "tolerance": "standard"})
    return out


def result_fields(r):
    out = {"round": r["round"], "kind": r["kind"], "item": "%s.item" % r["kind"], "stars": r["stars"],
           "outcome": r["outcome"], "reason": None, "first_try": r["first_try"], "misses": r["misses"],
           "answers": r["answers"], "hint_used": r["hint_used"], "assisted": r["assisted"],
           "pending_start": r["pending_start"], "earned_min": r["earned_min"], "active_ms": r["active_ms"],
           "total_ms": r["total_ms"], "parent_ms": 0, "mash_taps": 0}
    if r["type"] == "quiz":
        out["first_tap_ms"] = 2100
    for key in ("shapes_total", "shapes_done", "off_path_count", "wrong_start", "reverse_direction", "lifts",
                "mean_dev_u", "recount_attempts", "double_taps", "target", "numeral", "guide_helps", "guide_clean",
                "guide_learned_before", "guide_level", "guide_stalls", "roads", "roads_total"):
        if key in r:
            out[key] = r[key]
    if r["kind"] in SHAPE_TRACE:
        out["practice"] = "shape_trace"
    elif r["kind"] in TAP_ALL or r["kind"] in TAP_TRACE:
        out["practice"] = "tap_count"
    elif r["kind"] in GUIDED_ROADS:
        out["match_mode"] = "guided"
    return out


def play(r, t0, actor="child", mode="lock", session=None):
    """game_dealt, judged taps (quiz), round_result; returns when the next round can start."""
    log.emit("game_dealt", t0, dealt_fields(r, "playtest" if actor == "parent_playtest" else "off"),
             actor=actor, mode=mode, session=session)
    if r["type"] == "quiz":
        for n in range(r["misses"]):
            tags = r["wrong_tags"][n] if n < len(r["wrong_tags"]) else []
            log.emit("answer_attempt", t0 + timedelta(seconds=4 + 6 * n), {
                "round": r["round"], "kind": r["kind"], "n": n + 1, "choice": "wrong-%d" % n, "correct": False,
                "tags": tags, "fast": n == 0 and r["fast_wrongs"] > 0, "repeat_wrong": False, "slot": n,
                "hint_on": False}, actor=actor, mode=mode, session=session)
        if r["outcome"] == "solved":
            log.emit("answer_attempt", t0 + timedelta(seconds=4 + 6 * r["misses"]), {
                "round": r["round"], "kind": r["kind"], "n": r["misses"] + 1, "choice": "right", "correct": True,
                "tags": [], "fast": False, "repeat_wrong": False, "slot": 1, "hint_on": r["hint_used"]},
                actor=actor, mode=mode, session=session)
    t1 = t0 + timedelta(seconds=int(math.ceil(r["total_ms"] / 1000.0)))
    log.emit("round_result", t1, result_fields(r), actor=actor, mode=mode, session=session)
    return t1 + timedelta(seconds=15)


def videos(day, start, total_s, plays, session_tag):
    """`plays` plays adding up to `total_s` watched seconds; returns the end time."""
    t = start
    each = round(total_s / plays, 1)
    for p in range(plays):
        watched = each if p < plays - 1 else round(total_s - each * (plays - 1), 1)
        play_id = "p-%s-%s-%d" % (day[5:], session_tag, p)
        log.emit("video_start", t, {"play": play_id, "video": "vid-%s" % "abcdefgh"[p % 8], "source": "pick",
                                     "start_s": 0.0}, mode="play")
        t_end = t + timedelta(seconds=int(math.ceil(watched)) + 3)
        log.emit("video_end", t_end, {"play": play_id, "video": "vid-%s" % "abcdefgh"[p % 8], "source": "pick",
                                       "stop_reason": "ended", "completed": True, "watched_s": watched,
                                       "wall_s": watched + 3, "telemetry": "full", "resume_saved": False},
                 mode="play")
        t = t_end + timedelta(seconds=20)
    return t


def child_day(day, rounds, sessions, start_clock, video_s, plays):
    """The child's rounds of one day in `sessions` sessions two hours apart; videos after the last."""
    if not rounds:
        return
    per = int(math.ceil(len(rounds) / float(sessions)))
    chunks = [rounds[j:j + per] for j in range(0, len(rounds), per)]
    base = at(day, start_clock)
    for s, chunk in enumerate(chunks):
        t = base + timedelta(hours=2 * s)
        log.new_session("s-%s-%d" % (day[5:], s), t)
        t += timedelta(seconds=30)
        for r in chunk:
            t = play(r, t)
        if s == len(chunks) - 1 and plays:
            videos(day, t + timedelta(seconds=60), video_s, plays, "%d" % s)


def parent(day, clock, t, fields, session):
    log.emit(t, at(day, clock), fields, actor="parent", mode="parent", session=session)


def extra_round(kind, rid, stars, day, practice=False):
    """A simple solved round for parent test mode or a playtest (never counted)."""
    if practice:
        r = {"round": rid, "kind": kind, "day": day, "stars": stars, "type": "practice", "outcome": "solved",
             "first_try": None, "misses": 0, "answers": 0, "hint_used": False, "assisted": False,
             "pending_start": 5 * stars, "earned_min": 0, "active_ms": 40000, "total_ms": 45000, "wrong_tags": [],
             "fast_wrongs": 0, "tolerance": "wide"}
        if kind in TAP_TRACE:
            r.update({"recount_attempts": 0, "numeral": 3, "guide_helps": 1, "guide_clean": 0,
                      "guide_learned_before": 0, "guide_level": "standard", "guide_stalls": 0})
        elif kind in TAP_ALL:
            r.update({"recount_attempts": 0, "double_taps": 0, "target": 4})
        elif kind in SHAPE_TRACE:
            r.update({"shapes_total": 3, "shapes_done": 3, "off_path_count": 0, "wrong_start": 0,
                      "reverse_direction": 0, "lifts": 1, "mean_dev_u": 7.0})
        elif kind in GUIDED_ROADS:
            r.update({"roads": 3, "roads_total": 3, "off_path_count": 0, "wrong_start": 0})
        return r
    return {"round": rid, "kind": kind, "day": day, "stars": stars, "type": "quiz", "outcome": "solved",
            "first_try": True, "misses": 0, "answers": 1, "hint_used": False, "assisted": False,
            "pending_start": 5 * stars, "earned_min": 0, "active_ms": 9000, "total_ms": 15000, "wrong_tags": [],
            "fast_wrongs": 0, "tolerance": "wide"}


def check(current, previous):
    """The week reproduces design §5.6 and the sample's previous week; no unintended ★★★ shift."""
    def nk(rounds, kind):
        rs = [r for r in rounds if r["kind"] == kind]
        if not rs:
            return None
        if rs[0]["type"] == "quiz":
            ans = [r for r in rs if r["answers"] > 0]
            return len(ans), sum(1 for r in ans if r["first_try"])
        fin = [r for r in rs if r["smooth"] is not None]
        return len(fin), sum(1 for r in fin if r["smooth"])

    expected = {"shadowMatch": (9, 9), "halfMatch": (11, 10), "sequenceShortToLong": (8, 7),
                "capacityCompare": (12, 11), "findTheSame": (10, 7), "emptyBay": (9, 6), "lineMatch": (8, 4),
                "moreFewer": (10, 6), "countVehicles": (14, 6), "traceLines": (6, 6), "traceShapesDotted": (8, 7),
                "tapCountAllEnglish": (7, 6), "tapCountAll": (6, 5), "lineMatchGuidedStraight": (6, 5),
                "traceShapesArrows": (9, 7), "lineMatchGuidedBridge": (5, 2), "tapCountTrace": (7, 3),
                "shapeCousin": (4, 4), "twoPictureChoose": (2, 2), "tapCountTraceEnglish": (3, 1)}
    for kind, want in expected.items():
        assert nk(current, kind) == want, (kind, nk(current, kind), want)
    for kind, (n, k) in PREV.items():
        assert nk(previous, kind) == (n, k), (kind, nk(previous, kind), (n, k))
    for kind in PREV:
        cur = [r for r in current if r["kind"] == kind]
        prev = [r for r in previous if r["kind"] == kind]
        c3 = sum(1 for r in cur if r["stars"] == 3)
        p3 = sum(1 for r in prev if r["stars"] == 3)
        assert 10 * abs(c3 * len(prev) - p3 * len(cur)) < 3 * len(cur) * len(prev), (kind, c3, len(cur), p3, len(prev))


def build():
    current = build_rounds()
    previous = build_previous_rounds()
    check(current, previous)

    # An earlier settings change gives the Wednesday change its old value.
    log.start("L-1009", at("2026-10-09", "20:00:00"), "0.30.0", "s-1009p")
    parent("2026-10-09", "20:05:00", "config_change", {"what": "lineMatch_tolerance", "kind": "lineMatch",
                                                      "value": "standard", "category_mix": CATEGORY_MIX}, "s-1009p")

    # ---------------- Previous week 2026-10-12 … 18: 7 days, 120 video minutes a day ----------------
    log.start("L-1012", at("2026-10-12", "07:00:00"), "0.30.0", "s-1012s")
    for d, day in enumerate(PREV_DAYS):
        rounds = [r for r in previous if r["day"] == d]
        child_day(day, rounds, 1, "10:00:00" if d >= 5 else "17:00:00", 7200.0, 8)

    # ---------------- Report week 2026-10-19 … 25 (made Sunday 21:00) ----------------
    log.start("L-1019", at("2026-10-19", "07:00:00"), "0.31.0", "s-1019s")
    visa = [sum(r["earned_min"] for r in current if r["day"] == d) for d in range(7)]
    for d in (0, 1):
        video_min = round(visa[d] * VIDEO_FACTOR[d])
        child_day(DAYS[d], [r for r in current if r["day"] == d], SESSIONS[d], "15:00:00", video_min * 60.0,
                  round(video_min / 12.5))
    # Tuesday 22:30: parent test mode (家長測試中): 5 rounds, not counted.
    log.new_session("s-1020p", at("2026-10-20", "22:30:00"), reason="launch", actor="parent", mode="parent")
    parent("2026-10-20", "22:30:10", "uat_mode", {"on": True, "reason": "parent"}, "s-1020p")
    log.new_session("s-1020u", at("2026-10-20", "22:31:00"), reason="after_parent", actor="parent_uat")
    t = at("2026-10-20", "22:31:30")
    for j, (kind, practice) in enumerate([("findTheSame", False), ("countVehicles", False), ("halfMatch", False),
                                          ("traceLines", True), ("tapCountAll", True)]):
        t = play(extra_round(kind, "uat-%d" % j, 1, 1, practice), t, actor="parent_uat", session="s-1020u")
    # Wednesday: no child play. The parent widens 連一連 tolerance and playtests.
    log.new_session("s-1021p", at("2026-10-21", "17:00:00"), reason="launch", actor="parent", mode="parent")
    parent("2026-10-21", "17:00:20", "config_change", {"what": "lineMatch_tolerance", "kind": "lineMatch",
                                                      "value": "wide", "category_mix": CATEGORY_MIX}, "s-1021p")
    t = at("2026-10-21", "17:02:00")
    for j, (kind, practice) in enumerate([("tapCountTraceEnglish", True), ("tapCountTraceEnglish", True),
                                          ("lineMatch", False), ("lineMatchGuidedBridge", True)]):
        t = play(extra_round(kind, "pt-%d" % j, 0, 2, practice), t, actor="parent_playtest", mode="parent",
                 session="s-1021p")
    parent("2026-10-21", "17:30:00", "parent_leave", {}, "s-1021p")

    # Thursday: the app updates to 0.31.1; two more playtests, then 數完畫（英文）★ joins the tickets.
    log.start("L-1022", at("2026-10-22", "07:00:00"), "0.31.1", "s-1022p")
    t = at("2026-10-22", "07:30:00")
    for j in range(2):
        t = play(extra_round("tapCountTraceEnglish", "pt-%d" % (4 + j), 0, 3, True), t, actor="parent_playtest",
                 mode="parent", session="s-1022p")
    parent("2026-10-22", "07:40:00", "config_change", {"what": "assignment", "kind": "tapCountTraceEnglish",
                                                      "star": 1, "value": True}, "s-1022p")
    parent("2026-10-22", "07:41:00", "parent_leave", {}, "s-1022p")
    for d in (3, 4, 5, 6):
        video_min = round(visa[d] * VIDEO_FACTOR[d])
        child_day(DAYS[d], [r for r in current if r["day"] == d], SESSIONS[d],
                  "09:30:00" if d >= 5 else "15:00:00", video_min * 60.0, round(video_min / 12.5))


def main():
    folder = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.abspath(__file__))
    build()
    log.write(folder)


if __name__ == "__main__":
    main()
