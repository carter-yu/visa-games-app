#!/usr/bin/env python3
"""Independent reference for the W1 weekly metrics (design weekly-report §4.1–4.9, §9.6).

Reads a stats folder the way `PerfEventStore.read()` / `loadRollup()` do, computes the model
`WeeklyMetricsBuilder.build` must produce, and prints it in the canonical encoding described in
README.md. Standard library only; no shared code with the Swift side. Floats are summed in the
same order as the Swift builder (never with `sum()`, which compensates since Python 3.12).

Usage:
  python3 reference_model.py <folder> <week_start YYYY-MM-DD> <data_until ISO-8601> > expected-metrics.json
"""

import json
import math
import os
import re
import sys
from datetime import date, datetime, timedelta, timezone

UTC = timezone.utc
HKT = timezone(timedelta(hours=8))  # Asia/Hong_Kong: no daylight saving since 1979
DAY_MS = 86_400_000
GAME_MS_CAP = 600_000  # §4.6
TREND_WEEKS = 6
BUILDER = 1
DECIMALS = 6
TOP_TAG_MIN_WRONGS = 3
HELP_HEAVY_MEAN = 2
Z80 = 0.8416
PRIOR_ROUNDS = 4.0
POOLED_MIN_WEIGHT = 20.0

ENVELOPE = {"v", "t", "ts", "tz", "mono", "launch", "seq", "app", "actor", "mode", "session"}
ACTORS = {"child", "parent_uat", "parent_test_visa", "parent_playtest", "parent_preview", "parent", "system"}

# ActivityCatalog.playableKinds, in order.
CATALOG = [
    "twoPictureChoose", "findTheSame", "countVehicles", "sequenceShortToLong", "halfMatch", "shapeCousin",
    "capacityCompare", "moreFewer", "shadowMatch", "emptyBay", "lineMatchGuidedStraight", "lineMatchGuidedBridge",
    "lineMatch", "traceLines", "traceShapesDotted", "traceShapesArrows", "traceShapesFree", "tapCountAll",
    "tapCountTrace", "tapCountPick", "tapCountAllEnglish", "tapCountTraceEnglish", "tapCountPickEnglish",
    "tapLetterAll", "tapLetterWrite",
]
RANK = {kind: i for i, kind in enumerate(CATALOG)}
SHAPE_TRACE_FAMILY = {"traceLines", "traceShapesDotted", "traceShapesArrows", "traceShapesFree"}
TAP_BASE = {"tapCountAll": "tapCountAll", "tapCountAllEnglish": "tapCountAll",
            "tapCountTrace": "tapCountTrace", "tapCountTraceEnglish": "tapCountTrace",
            "tapCountPick": "tapCountPick", "tapCountPickEnglish": "tapCountPick"}

# PerfChoiceCatalog.chance(for:). tapCountPick* depends on the seeded reference deal, so the
# fixture always carries `cars` and this table never needs it.
CATALOG_CHANCE = {
    "twoPictureChoose": 0.5, "capacityCompare": 0.5, "moreFewer": 0.5,
    "findTheSame": 1.0 / 3.0, "countVehicles": 1.0 / 3.0, "halfMatch": 1.0 / 3.0, "shapeCousin": 1.0 / 3.0,
    "shadowMatch": 1.0 / 3.0, "emptyBay": 1.0 / 3.0,
    "sequenceShortToLong": 1.0 / 24.0,
    "lineMatch": 1.0 / 6.0, "lineMatchGuidedStraight": 1.0 / 6.0, "lineMatchGuidedBridge": 1.0 / 6.0,
    "traceLines": 1.0, "traceShapesDotted": 1.0, "traceShapesArrows": 1.0, "traceShapesFree": 1.0,
    "tapCountAll": 1.0, "tapCountTrace": 1.0, "tapCountAllEnglish": 1.0, "tapCountTraceEnglish": 1.0,
    "tapCountPick": None, "tapCountPickEnglish": None,
    "tapLetterAll": 1.0 / 45.0, "tapLetterWrite": 1.0 / 45.0,
}

AREAS = ["numbers", "matching", "comparing", "pen", "letters", "other"]
AREA_OF = {}
for _k in ["countVehicles", "moreFewer", "tapCountPick", "tapCountPickEnglish", "tapCountAll", "tapCountTrace",
           "tapCountAllEnglish", "tapCountTraceEnglish"]:
    AREA_OF[_k] = "numbers"
for _k in ["twoPictureChoose", "findTheSame", "halfMatch", "shadowMatch", "lineMatch"]:
    AREA_OF[_k] = "matching"
for _k in ["capacityCompare", "sequenceShortToLong", "shapeCousin", "emptyBay"]:
    AREA_OF[_k] = "comparing"
for _k in ["traceLines", "traceShapesDotted", "traceShapesArrows", "traceShapesFree", "lineMatchGuidedStraight",
           "lineMatchGuidedBridge"]:
    AREA_OF[_k] = "pen"
for _k in ["tapLetterAll", "tapLetterWrite"]:
    AREA_OF[_k] = "letters"

FAMILIES = ["lines", "shapes", "roads", "tapAll", "tapTrace"]
FAMILY_OF = {"traceLines": "lines", "traceShapesDotted": "shapes", "traceShapesArrows": "shapes",
             "traceShapesFree": "shapes", "lineMatchGuidedStraight": "roads", "lineMatchGuidedBridge": "roads",
             "lineMatch": "roads", "tapCountAll": "tapAll", "tapCountAllEnglish": "tapAll",
             "tapCountTrace": "tapTrace", "tapCountTraceEnglish": "tapTrace"}


# ---------------------------------------------------------------- PerfValue accessors

def is_number(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool)


def int_value(v):
    if isinstance(v, bool):
        return None
    if isinstance(v, int):
        return v
    if isinstance(v, float) and math.isfinite(v) and v == math.floor(v) and abs(v) < 1e15:
        return int(v)
    return None


def double_value(v):
    return float(v) if is_number(v) else None


def string_value(v):
    return v if isinstance(v, str) else None


def string_array(v):
    return [s for s in v if isinstance(s, str)] if isinstance(v, list) else []


def flag(v):
    """WeeklyField.flag: true/false, or a 1/0 integer."""
    if isinstance(v, bool):
        return v
    if isinstance(v, int):
        return v != 0
    return None


# ---------------------------------------------------------------- decoding (PerfCodec)

TS = re.compile(r"^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,3}))?(Z|[+-]\d{2}:\d{2})$")


def parse_ts(text):
    m = TS.match(text) if isinstance(text, str) else None
    if not m:
        return None
    y, mo, d, hh, mm, ss, frac, zone = m.groups()
    ms = int((frac or "0").ljust(3, "0"))
    offset = 0
    if zone != "Z":
        sign = -1 if zone[0] == "-" else 1
        offset = sign * (int(zone[1:3]) * 60 + int(zone[4:6]))
    moment = datetime(int(y), int(mo), int(d), int(hh), int(mm), int(ss), tzinfo=timezone(timedelta(minutes=offset)))
    return int(moment.timestamp()) * 1000 + ms


def format_ts(ms):
    moment = datetime(1970, 1, 1, tzinfo=UTC) + timedelta(milliseconds=ms)
    return moment.strftime("%Y-%m-%dT%H:%M:%S.") + "%03d" % (ms % 1000) + "Z"


def day_stamp(ms):
    return (datetime(1970, 1, 1, tzinfo=UTC) + timedelta(milliseconds=ms)).astimezone(HKT).strftime("%Y-%m-%d")


class Event:
    __slots__ = ("t", "ts", "launch", "seq", "actor", "session", "fields", "file_order")

    def get(self, key):
        return self.fields.get(key)


def decode_line(line):
    text = line.strip(" \t")
    if not text:
        return "blank"
    try:
        obj = json.loads(text)
    except ValueError:
        return None
    if not isinstance(obj, dict) or int_value(obj.get("v")) != 1:
        return None
    t = obj.get("t")
    ts = parse_ts(obj.get("ts"))
    if not isinstance(t, str) or not t or ts is None:
        return None
    e = Event()
    e.t = t
    e.ts = ts
    e.launch = string_value(obj.get("launch")) or ""
    e.seq = int_value(obj.get("seq")) or 0
    actor = string_value(obj.get("actor"))
    e.actor = actor if actor in ACTORS else "system"
    e.session = string_value(obj.get("session")) or ""
    e.fields = {k: v for k, v in obj.items() if k not in ENVELOPE}
    return e


def read_store(folder):
    days = []
    for name in os.listdir(folder):
        if name.startswith("events-") and name.endswith(".jsonl"):
            stamp = name[len("events-"):-len(".jsonl")]
            if re.match(r"^\d{4}-\d{2}-\d{2}$", stamp):
                days.append(stamp)
    events, skipped = [], 0
    for stamp in sorted(days):
        with open(os.path.join(folder, "events-%s.jsonl" % stamp), encoding="utf-8") as f:
            text = f.read()
        for line in text.split("\n"):
            out = decode_line(line)
            if out == "blank":
                continue
            if out is None:
                skipped += 1
                continue
            out.file_order = len(events)
            events.append(out)
    return ordered(events), skipped


def ordered(events):
    """PerfCodec.ordered: (launch, seq) inside a launch, first-seen ts across launches."""
    first = {}
    for e in events:
        if e.launch not in first or e.ts < first[e.launch]:
            first[e.launch] = e.ts
    return sorted(events, key=lambda e: (first[e.launch], e.launch.encode("utf-8"), e.seq, e.ts, e.file_order))


def excluded_sessions(events):
    """PerfFilter.excludedSessions: last stats_exclude / stats_include per session wins."""
    state = {}
    for e in events:
        session = string_value(e.get("target_session"))
        if session is None:
            continue
        if e.t == "stats_exclude":
            state[session] = True
        elif e.t == "stats_include":
            state[session] = False
    return {s for s, on in state.items() if on}


def countable(e, excluded):
    return e.actor == "child" and e.session not in excluded


# ---------------------------------------------------------------- per-round facts (§4.3, §4.5)

def is_practice(dealt):
    """PerfQuestionGeneration.isPracticeOnly."""
    kind = string_value(dealt.get("kind"))
    if kind in RANK and (kind in SHAPE_TRACE_FAMILY or TAP_BASE.get(kind) in ("tapCountAll", "tapCountTrace")):
        return True
    return string_value(dealt.get("match_mode")) == "guided"


def is_variant(dealt):
    return (string_value(dealt.get("gen")) or "fixed_v0") != "fixed_v0"


def chance_of(dealt):
    written = double_value(dealt.get("chance"))
    if written is not None and math.isfinite(written) and 0 < written <= 1:
        return written
    kind = string_value(dealt.get("kind"))
    if kind not in RANK:
        return None
    if kind == "lineMatch":
        pairs = int_value(dealt.get("pairs"))
        if pairs is not None and 1 <= pairs <= 20:
            return 1.0 / float(math.factorial(pairs))
    elif kind in ("tapCountPick", "tapCountPickEnglish"):
        cars = int_value(dealt.get("cars"))
        if cars is not None and cars >= 1:
            return 1.0 / float(cars)
    elif kind in ("countVehicles", "findTheSame"):
        slots = string_array(dealt.get("slots"))
        if is_variant(dealt) and slots:
            return 1.0 / float(len(slots))
    value = CATALOG_CHANCE[kind]
    if value is None:
        raise SystemExit("fixture needs `cars` on every %s deal" % kind)
    return value


def smooth_of(kind, res):
    """WeeklySmooth.evaluate: None unless solved, the kind has a rule and every field is there."""
    if string_value(res.get("outcome")) != "solved" or kind not in RANK:
        return None

    def i(key):
        return int_value(res.get(key))

    if kind in ("traceLines", "traceShapesDotted", "traceShapesArrows"):
        vals = [i("shapes_done"), i("shapes_total"), i("wrong_start"), i("reverse_direction"), i("off_path_count")]
        if None in vals:
            return None
        done, total, wrong_start, reverse, off_path = vals
        return done == total and wrong_start == 0 and reverse == 0 and off_path <= total
    if kind == "traceShapesFree":
        done, total, erasers = i("shapes_done"), i("shapes_total"), i("erasers")
        ink = double_value(res.get("ink_outside_ratio"))
        if None in (done, total, erasers, ink):
            return None
        return done == total and ink <= 0.25 and erasers <= 1
    if kind in ("lineMatchGuidedStraight", "lineMatchGuidedBridge", "lineMatch"):
        vals = [i("roads"), i("roads_total"), i("wrong_start"), i("off_path_count")]
        if None in vals:
            return None
        roads, total, wrong_start, off_path = vals
        return roads == total and wrong_start == 0 and off_path <= 1
    if kind in ("tapCountAll", "tapCountAllEnglish"):
        recount = i("recount_attempts")
        return None if recount is None else recount == 0
    if kind in ("tapCountTrace", "tapCountTraceEnglish"):
        recount = i("recount_attempts")
        if recount is None:
            return None
        clean = flag(res.get("guide_clean"))
        if clean is not None:
            return recount == 0 and clean
        off_path, wrong_start = i("trace_off_path_count"), i("trace_wrong_start")
        if off_path is None or wrong_start is None:
            return None
        return recount == 0 and off_path <= 1 and wrong_start == 0
    return None


def watched_ms(v):
    seconds = double_value(v)
    if seconds is None or not math.isfinite(seconds) or seconds <= 0:
        return 0
    return int(math.floor(seconds * 1000 + 0.5))


# ---------------------------------------------------------------- PerfMastery (MasteryEstimator.swift)

def chance_corrected(x, c):
    if not c < 1:
        return 0.0
    return min(max((x - c) / (1 - c), 0.0), 1.0)


def estimate(c, mbar, success, failure):
    p0 = c + (1 - c) * mbar
    a0 = PRIOR_ROUNDS * p0
    b0 = PRIOR_ROUNDS * (1 - p0)
    a = a0 + success
    b = b0 + failure
    n = a + b
    mean = a / n
    sd = math.sqrt(a * b / (n * n * (n + 1)))
    low = min(max(mean - Z80 * sd, 0.0), 1.0)
    high = min(max(mean + Z80 * sd, 0.0), 1.0)
    return {"p0": p0, "alpha": a, "beta": b, "mean": mean, "sd": sd,
            "m": chance_corrected(mean, c), "lo": chance_corrected(low, c), "hi": chance_corrected(high, c)}


def pooled_prior(entries):
    """entries: (chance, success, failure) in row order."""
    total = 0.0
    for _, s, f in entries:
        total = total + (s + f)
    if not total >= POOLED_MIN_WEIGHT:
        return 0.5
    acc = 0.0
    for c, s, f in entries:
        w = s + f
        if w > 0:
            acc += w * chance_corrected(s / w, c)
    return min(max(acc / total, 0.2), 0.8)


def median(values):
    if not values:
        return None
    v = sorted(values)
    mid = len(v) // 2
    return v[mid] if len(v) % 2 == 1 else (v[mid - 1] + v[mid]) / 2


def adjusted(first_try, answered, expected):
    if expected is None or answered <= 0:
        return None
    room = answered - expected
    if not room > 0:
        return None
    return min(max((first_try - expected) / room, 0.0), 1.0)


# ---------------------------------------------------------------- windows (§4.2)

class Window:
    def __init__(self, monday_ms, cutoff=None):
        self.start = monday_ms
        self.day_starts = [monday_ms + i * DAY_MS for i in range(8)]
        self.end = self.day_starts[7]
        self.cutoff = self.end if cutoff is None else min(cutoff, self.end)
        self.day_stamps = [day_stamp(ms) for ms in self.day_starts[:7]]

    @staticmethod
    def containing(stamp, cutoff=None):
        d = date.fromisoformat(stamp)
        monday = d - timedelta(days=d.weekday())
        ms = int(datetime(monday.year, monday.month, monday.day, tzinfo=HKT).timestamp()) * 1000
        return Window(ms, cutoff)

    def shifted(self, weeks):
        return Window(self.start + weeks * 7 * DAY_MS)

    def day_index(self, ts):
        if ts < self.start or ts >= self.end:
            return None
        for i in range(7):
            if ts < self.day_starts[i + 1]:
                return i
        return None

    def contains(self, ts):
        return self.start <= ts < self.end and ts <= self.cutoff


# ---------------------------------------------------------------- the index (one pass)

class Dealt:
    __slots__ = ("event", "countable", "round", "kind", "type")


class Index:
    def __init__(self, events, excluded, rollup):
        self.dealt, self.results, self.wrong = [], {}, {}
        self.video_starts, self.video_ends, self.ended, self.progress = [], [], {}, {}
        self.launch_start, self.cleared, self.dealt_times, self.rollup_days = {}, [], {}, {}
        self.first_event = None
        for e in events:
            if self.first_event is None or e.ts < self.first_event:
                self.first_event = e.ts
            if e.launch not in self.launch_start or e.ts < self.launch_start[e.launch]:
                self.launch_start[e.launch] = e.ts
            if e.t == "game_dealt":
                d = Dealt()
                d.event = e
                d.countable = countable(e, excluded)
                d.round = string_value(e.get("round")) or ""
                kind = string_value(e.get("kind"))
                d.kind = "unknown" if kind is None else kind
                d.type = "practice" if is_practice(e) else "quiz"
                self.dealt.append(d)
                if d.countable:
                    self.dealt_times.setdefault(d.kind, []).append(e.ts)
            elif e.t == "round_result":
                r = string_value(e.get("round"))
                if r:
                    self.results.setdefault(r, []).append(e)
            elif e.t == "answer_attempt":
                r = string_value(e.get("round"))
                if e.get("correct") is False and countable(e, excluded) and r:
                    self.wrong.setdefault(r, []).append(e)
            elif e.t == "video_start":
                if countable(e, excluded):
                    self.video_starts.append(e)
            elif e.t == "video_progress":
                play = string_value(e.get("play"))
                if countable(e, excluded) and play is not None:
                    self.progress.setdefault(play, []).append(e)
            elif e.t == "video_end":
                play = string_value(e.get("play"))
                if play is not None:
                    self.ended.setdefault(play, []).append(e.ts)
                if countable(e, excluded):
                    self.video_ends.append(e)
            elif e.t == "stats_marker":
                if string_value(e.get("what")) == "cleared":
                    self.cleared.append(e.ts)
        self.cleared.sort()
        for stamp, summary in (rollup.get("days") or {}).items():
            for key, stats in ((summary or {}).get("games") or {}).items():
                if (int_value((stats or {}).get("deals")) or 0) > 0:
                    self.rollup_days.setdefault(key.split("|")[0], []).append(stamp)

    def result(self, round_id, cutoff):
        for r in reversed(self.results.get(round_id, []) if round_id else []):
            if r.ts <= cutoff:
                return r
        return None

    def is_lost(self, position, cutoff):
        """No result, but the app has moved on: relaunched, or dealt another non-playtest round."""
        d = self.dealt[position].event
        for launch, started in self.launch_start.items():
            if launch != d.launch and d.ts < started <= cutoff:
                return True
        j = position + 1
        while j < len(self.dealt) and self.dealt[j].event.launch == d.launch:
            later = self.dealt[j].event
            if later.actor != "parent_playtest" and later.ts <= cutoff:
                return True
            j += 1
        return False

    def has_history(self, kind, window):
        resets = [c for c in self.cleared if c <= window.cutoff]
        reset = resets[-1] if resets else None
        for t in self.dealt_times.get(kind, []):
            if t < window.start and (reset is None or t >= reset):
                return True
        reset_stamp = day_stamp(reset) if reset is not None else None
        for stamp in self.rollup_days.get(kind, []):
            if stamp < window.day_stamps[0] and (reset_stamp is None or stamp >= reset_stamp):
                return True
        return False


# ---------------------------------------------------------------- metrics per window

def make_round(d, day, res):
    e = d.event
    if res is None:
        outcome = "no_result"
    else:
        o = string_value(res.get("outcome"))
        outcome = o if o in ("solved", "zeroed") else "abandoned"
    rf = res.fields if res is not None else {}
    quiz = d.type == "quiz"
    answers = int_value(rf.get("answers")) or 0
    answered = quiz and answers > 0
    first_try = answered and rf.get("first_try") is True
    helped = answered and (flag(rf.get("hint_used")) is True or flag(rf.get("assisted")) is True)
    total = int_value(rf.get("total_ms")) or 0
    smooth, guide_helps = None, None
    if not quiz and res is not None and outcome == "solved":
        smooth = smooth_of(d.kind, res.fields)
        guide_helps = int_value(rf.get("guide_helps"))
    stars = int_value(e.get("stars"))
    return {
        "round": d.round, "kind": d.kind, "type": d.type, "ts": e.ts, "day": day, "session": e.session,
        "stars": min(max(1 if stars is None else stars, 1), 3), "outcome": outcome,
        "answered": answered, "first_try": first_try, "chance": chance_of(e) if quiz else None,
        "misses": max(0, int_value(rf.get("misses")) or 0) if quiz else 0, "helped": helped,
        "active_ms": int_value(rf.get("active_ms")), "game_ms": min(max(total, 0), GAME_MS_CAP),
        "visa_min": max(0, int_value(rf.get("earned_min")) or 0) if outcome == "solved" else 0,
        "smooth": smooth, "guide_helps": guide_helps,
    }


def counts():
    return {"rounds": 0, "answered": 0, "first_try": 0, "finished": 0, "smooth_defined": 0, "smooth": 0}


def add_counts(c, r):
    c["rounds"] += 1
    if r["type"] == "quiz":
        if r["answered"]:
            c["answered"] += 1
        if r["first_try"]:
            c["first_try"] += 1
    else:
        if r["outcome"] == "solved":
            c["finished"] += 1
        if r["smooth"] is not None:
            c["smooth_defined"] += 1
            if r["smooth"]:
                c["smooth"] += 1


def new_row(kind, type_):
    return {"kind": kind, "type": type_, "area": AREA_OF.get(kind, "other"),
            "family": FAMILY_OF.get(kind) if type_ == "practice" and kind in RANK else None,
            "new": False, "rounds": 0, "solved": 0, "zeroed": 0, "unfinished": 0, "no_result": 0,
            "stars": [counts(), counts(), counts()], "cells": [counts() for _ in range(7)],
            "answered": 0, "first_try": 0, "chance_known": True, "expected_sum": 0.0, "misses": 0, "helped": 0,
            "active": [], "wrong": 0, "fast": 0, "tags": {}, "smooth_defined": 0, "smooth": 0,
            "helps_total": 0, "helps_rounds": 0, "estimate": None}


def add_row(row, r):
    row["rounds"] += 1
    add_counts(row["stars"][r["stars"] - 1], r)
    add_counts(row["cells"][r["day"]], r)
    o = r["outcome"]
    if o == "solved":
        row["solved"] += 1
    elif o == "zeroed":
        row["zeroed"] += 1
    else:
        row["unfinished"] += 1
        if o == "no_result":
            row["no_result"] += 1
    if row["type"] == "quiz":
        if r["answered"]:
            row["answered"] += 1
            if r["first_try"]:
                row["first_try"] += 1
            if r["helped"]:
                row["helped"] += 1
            if r["chance"] is not None:
                row["expected_sum"] += r["chance"]
            else:
                row["chance_known"] = False
        row["misses"] += r["misses"]
        if o == "solved" and r["active_ms"] is not None:
            row["active"].append(r["active_ms"] / 1000)
    else:
        if r["smooth"] is not None:
            row["smooth_defined"] += 1
            if r["smooth"]:
                row["smooth"] += 1
        if r["guide_helps"] is not None:
            row["helps_total"] += r["guide_helps"]
            row["helps_rounds"] += 1


def row_expected(row):
    return row["expected_sum"] if row["type"] == "quiz" and row["chance_known"] else None


def row_chance_mean(row):
    e = row_expected(row)
    return e / row["answered"] if row["type"] == "quiz" and row["answered"] > 0 and e is not None else None


def row_evidence(row):
    if row["type"] == "quiz":
        return float(row["first_try"]), float(row["answered"] - row["first_try"])
    return float(row["smooth"]), float(row["smooth_defined"] - row["smooth"])


def group():
    return {"rounds": 0, "quiz_rounds": 0, "practice_rounds": 0, "answered": 0, "first_try": 0, "expected": 0.0,
            "expected_answered": 0, "expected_first_try": 0, "finished": 0, "smooth_defined": 0, "smooth": 0}


def add_group(g, row):
    g["rounds"] += row["rounds"]
    if row["type"] == "quiz":
        g["quiz_rounds"] += row["rounds"]
        g["answered"] += row["answered"]
        g["first_try"] += row["first_try"]
        e = row_expected(row)
        if e is not None:
            g["expected"] += e
            g["expected_answered"] += row["answered"]
            g["expected_first_try"] += row["first_try"]
    else:
        g["practice_rounds"] += row["rounds"]
        g["finished"] += row["solved"]
        g["smooth_defined"] += row["smooth_defined"]
        g["smooth"] += row["smooth"]


def metrics(index, window):
    rounds, excluded, open_at_cutoff = [], {}, 0
    for position, d in enumerate(index.dealt):
        ts = d.event.ts
        day = window.day_index(ts)
        if not window.contains(ts) or day is None:
            continue
        if not d.countable:
            reason = "excluded_session" if d.event.actor == "child" else d.event.actor
            excluded[reason] = excluded.get(reason, 0) + 1
            continue
        res = index.result(d.round, window.cutoff)
        if res is None and not index.is_lost(position, window.cutoff):
            open_at_cutoff += 1
            continue
        rounds.append(make_round(d, day, res))

    rows, at = [], {}
    for r in rounds:
        key = (r["kind"], r["type"])
        if key not in at:
            at[key] = len(rows)
            rows.append(new_row(r["kind"], r["type"]))
        row = rows[at[key]]
        add_row(row, r)
        if r["type"] == "quiz":
            for attempt in index.wrong.get(r["round"], []) if r["round"] else []:
                if attempt.ts > window.cutoff:
                    continue
                row["wrong"] += 1
                if attempt.get("fast") is True:
                    row["fast"] += 1
                for tag in string_array(attempt.get("tags")):
                    row["tags"][tag] = row["tags"].get(tag, 0) + 1
    for row in rows:
        row["median_active"] = median(row["active"])
        row["days_played"] = sum(1 for c in row["cells"] if c["rounds"] > 0)
        row["top_tag"], row["top_tag_count"] = None, 0
        if row["tags"]:
            tag, n = sorted(row["tags"].items(), key=lambda kv: (-kv[1], kv[0].encode("utf-8")))[0]
            if row["wrong"] >= TOP_TAG_MIN_WRONGS and 2 * n >= row["wrong"]:
                row["top_tag"], row["top_tag_count"] = tag, n
    rows.sort(key=lambda row: (RANK.get(row["kind"], sys.maxsize), row["kind"].encode("utf-8"),
                               0 if row["type"] == "quiz" else 1))

    pooled_quiz = pooled_prior([(row_chance_mean(row),) + row_evidence(row) for row in rows
                                if row["type"] == "quiz" and row["answered"] > 0 and row_chance_mean(row) is not None])
    pooled_practice = pooled_prior([(0.0,) + row_evidence(row) for row in rows
                                    if row["type"] == "practice" and row["family"] is not None
                                    and row["smooth_defined"] > 0])
    for row in rows:
        if row["type"] == "quiz":
            mean = row_chance_mean(row)
            if row["answered"] > 0 and mean is not None:
                row["estimate"] = estimate(mean, pooled_quiz, *row_evidence(row))
        elif row["family"] is not None and row["smooth_defined"] > 0:
            row["estimate"] = estimate(0.0, pooled_practice, *row_evidence(row))

    new_kinds, seen = [], set()
    for row in rows:
        if row["kind"] in seen:
            continue
        seen.add(row["kind"])
        if not index.has_history(row["kind"], window):
            new_kinds.append(row["kind"])
    for row in rows:
        row["new"] = row["kind"] in new_kinds

    days = [{"index": i, "date": window.day_stamps[i], "counts": counts(), "quiz_rounds": 0, "practice_rounds": 0,
             "quiz_ms": 0, "practice_ms": 0, "video_ms": 0, "video_estimated": False, "plays": 0, "visa_min": 0,
             "sessions": set(), "new_kinds": []} for i in range(7)]
    for r in rounds:
        day = days[r["day"]]
        add_counts(day["counts"], r)
        if r["type"] == "quiz":
            day["quiz_rounds"] += 1
            day["quiz_ms"] += r["game_ms"]
        else:
            day["practice_rounds"] += 1
            day["practice_ms"] += r["game_ms"]
        day["visa_min"] += r["visa_min"]
        if r["session"]:
            day["sessions"].add(r["session"])
    for kind in new_kinds:
        first = None
        for r in rounds:
            if r["kind"] == kind and (first is None or r["ts"] < first["ts"]):
                first = r
        if first is not None:
            days[first["day"]]["new_kinds"].append(kind)
    for start in index.video_starts:
        if not window.contains(start.ts):
            continue
        day = window.day_index(start.ts)
        if day is None:
            continue
        if string_value(start.get("source")) != "after_parent":
            days[day]["plays"] += 1
            if start.session:
                days[day]["sessions"].add(start.session)
        play = string_value(start.get("play"))
        if not play or any(t <= window.cutoff for t in index.ended.get(play, [])):
            continue
        last = None
        for p in index.progress.get(play, []):
            if p.ts <= window.cutoff:
                last = p
        at_day = window.day_index(last.ts) if last is not None else None
        at_day = day if at_day is None else at_day
        days[at_day]["video_ms"] += watched_ms(last.get("watched_s") if last is not None else None)
        days[at_day]["video_estimated"] = True
    for end in index.video_ends:
        if not window.contains(end.ts):
            continue
        day = window.day_index(end.ts)
        if day is not None:
            days[day]["video_ms"] += watched_ms(end.get("watched_s"))

    areas = {a: group() for a in AREAS}
    families = {f: group() for f in FAMILIES}
    totals = group()
    for row in rows:
        add_group(areas[row["area"]], row)
        if row["family"] is not None:
            add_group(families[row["family"]], row)
        add_group(totals, row)

    stars = [0, 0, 0]
    for r in rounds:
        stars[r["stars"] - 1] += 1
    if index.first_event is None:
        covered = 0
    else:
        covered = sum(1 for i in range(7)
                      if window.day_starts[i] < window.cutoff and window.day_starts[i + 1] > index.first_event)
    return {"window": window, "rounds": rounds, "rows": rows, "days": days, "areas": areas, "families": families,
            "totals": totals, "excluded": excluded, "open": open_at_cutoff, "pooled_quiz": pooled_quiz,
            "pooled_practice": pooled_practice, "new_kinds": new_kinds, "stars": stars, "covered": covered}


# ---------------------------------------------------------------- JSON values

def num(x):
    return None if x is None else float(x)


def ratio(a, b):
    return a / b if b > 0 else None


def estimate_json(e):
    return None if e is None else {k: float(v) for k, v in e.items()}


def counts_json(c, type_, key, value):
    out = {key: value, "rounds": c["rounds"]}
    if type_ == "quiz":
        out.update(answered=c["answered"], first_try=c["first_try"])
    else:
        out.update(finished=c["finished"], smooth_defined=c["smooth_defined"], smooth=c["smooth"])
    return out


def row_json(row):
    out = {"kind": row["kind"], "type": row["type"], "area": row["area"], "family": row["family"], "new": row["new"],
           "rounds": row["rounds"], "solved": row["solved"], "zeroed": row["zeroed"],
           "unfinished": row["unfinished"], "no_result": row["no_result"], "days_played": row["days_played"],
           "estimate": estimate_json(row["estimate"]),
           "stars": [counts_json(c, row["type"], "stars", i + 1) for i, c in enumerate(row["stars"])],
           "days": [counts_json(c, row["type"], "day", i) for i, c in enumerate(row["cells"]) if c["rounds"] > 0]}
    if row["type"] == "quiz":
        out.update({
            "answered": row["answered"], "first_try": row["first_try"], "rate": ratio(row["first_try"], row["answered"]),
            "chance_known": row["chance_known"], "expected": num(row_expected(row)),
            "chance_mean": num(row_chance_mean(row)),
            "adjusted": num(adjusted(row["first_try"], row["answered"], row_expected(row))),
            "misses": row["misses"], "misses_per_round": ratio(row["misses"], row["answered"]),
            "helped": row["helped"], "help_rate": ratio(row["helped"], row["answered"]),
            "median_active_s": num(row["median_active"]), "wrong_attempts": row["wrong"],
            "fast_wrong": row["fast"], "fast_wrong_share": ratio(row["fast"], row["wrong"]),
            "top_wrong_tag": row["top_tag"], "top_wrong_tag_count": row["top_tag_count"],
        })
    else:
        out.update({
            "finished": row["solved"], "smooth_defined": row["smooth_defined"], "smooth": row["smooth"],
            "rate": ratio(row["smooth"], row["smooth_defined"]),
            "guide_helps_mean": ratio(row["helps_total"], row["helps_rounds"]),
            "help_heavy": row["helps_rounds"] > 0 and row["helps_total"] >= HELP_HEAVY_MEAN * row["helps_rounds"],
        })
    return out


def group_json(g):
    return {
        "rounds": g["rounds"], "quiz_rounds": g["quiz_rounds"], "practice_rounds": g["practice_rounds"],
        "quiz_answered": g["answered"], "quiz_first_try": g["first_try"], "quiz_rate": ratio(g["first_try"], g["answered"]),
        "quiz_expected": float(g["expected"]), "quiz_expected_answered": g["expected_answered"],
        "quiz_chance_mean": ratio(g["expected"], g["expected_answered"]),
        "quiz_adjusted": num(adjusted(g["expected_first_try"], g["expected_answered"], g["expected"])),
        "practice_finished": g["finished"], "practice_smooth_defined": g["smooth_defined"],
        "practice_smooth": g["smooth"], "practice_rate": ratio(g["smooth"], g["smooth_defined"]),
    }


def family_json(family, g):
    return {"family": family, "rounds": g["rounds"], "finished": g["finished"], "smooth_defined": g["smooth_defined"],
            "smooth": g["smooth"], "rate": ratio(g["smooth"], g["smooth_defined"])}


def day_json(d):
    c = d["counts"]
    return {
        "index": d["index"], "date": d["date"], "rounds": c["rounds"], "quiz_rounds": d["quiz_rounds"],
        "quiz_answered": c["answered"], "quiz_first_try": c["first_try"], "practice_rounds": d["practice_rounds"],
        "practice_finished": c["finished"], "practice_smooth_defined": c["smooth_defined"],
        "practice_smooth": c["smooth"], "quiz_min": d["quiz_ms"] / 60000, "practice_min": d["practice_ms"] / 60000,
        "game_min": (d["quiz_ms"] + d["practice_ms"]) / 60000, "video_min": d["video_ms"] / 60000,
        "video_estimated": d["video_estimated"], "plays": d["plays"], "visa_min": d["visa_min"],
        "sessions": len(d["sessions"]), "new_kinds": list(d["new_kinds"]),
    }


def round_json(r):
    quiz = r["type"] == "quiz"
    return {"round": r["round"], "kind": r["kind"], "type": r["type"], "day": r["day"], "stars": r["stars"],
            "outcome": r["outcome"], "game_ms": r["game_ms"], "visa_min": r["visa_min"],
            "answered": r["answered"] if quiz else None, "first_try": r["first_try"] if quiz else None,
            "chance": num(r["chance"]), "smooth": r["smooth"]}


def window_json(m):
    w, days = m["window"], m["days"]
    totals = group_json(m["totals"])
    sessions = set()
    for d in days:
        sessions |= d["sessions"]
    quiz_ms = practice_ms = video_ms = 0
    for d in days:
        quiz_ms += d["quiz_ms"]
        practice_ms += d["practice_ms"]
        video_ms += d["video_ms"]
    totals.update({
        "days_played": sum(1 for d in days if d["counts"]["rounds"] > 0 or d["plays"] > 0),
        "sessions": len(sessions), "plays": sum(d["plays"] for d in days),
        "quiz_min": quiz_ms / 60000, "practice_min": practice_ms / 60000,
        "game_min": (quiz_ms + practice_ms) / 60000, "video_min": video_ms / 60000,
        "video_estimated": any(d["video_estimated"] for d in days),
        "visa_min": sum(d["visa_min"] for d in days),
    })
    return {
        "week_start": w.day_stamps[0], "week_end": w.day_stamps[6], "data_until": format_ts(w.cutoff),
        "covered_days": m["covered"], "partial": m["covered"] < 7, "open_at_cutoff": m["open"],
        "excluded_rounds": {"total": sum(m["excluded"].values()), "by_reason": dict(m["excluded"])},
        "pooled": {"quiz": float(m["pooled_quiz"]), "practice": float(m["pooled_practice"])},
        "stars": list(m["stars"]), "new_kinds": list(m["new_kinds"]),
        "days": [day_json(d) for d in days],
        "kinds": [row_json(row) for row in m["rows"]],
        "areas": [dict(group_json(m["areas"][a]), area=a) for a in AREAS],
        "families": [family_json(f, m["families"][f]) for f in FAMILIES],
        "totals": totals,
        "rounds": [round_json(r) for r in m["rounds"]],
    }


def week_json(m, current):
    out = group_json(m["totals"])
    out.update({"week_start": m["window"].day_stamps[0], "current": current, "partial": m["covered"] < 7,
                "open_at_cutoff": m["open"]})
    return out


def build(events, rollup, window):
    excluded = excluded_sessions(events)
    index = Index(events, excluded, rollup)
    current = metrics(index, window)
    previous_window = window.shifted(-1)
    previous = metrics(index, previous_window)
    trend = [window.shifted(-k) for k in range(TREND_WEEKS, 0, -1)]
    weeks = []
    for week in trend:
        if any(week.start <= e.ts < week.end for e in events):
            m = previous if week.start == previous_window.start else metrics(index, week)
            weeks.append(week_json(m, False))
    weeks.append(week_json(current, True))
    return {"builder": BUILDER, "time_zone": "Asia/Hong_Kong", "week_start": window.day_stamps[0],
            "data_until": format_ts(window.cutoff), "current": window_json(current),
            "previous": window_json(previous), "weeks": weeks}


# ---------------------------------------------------------------- canonical encoding (README.md)

def quote(text):
    out = ['"']
    for ch in text:
        code = ord(ch)
        if ch == '"':
            out.append('\\"')
        elif ch == "\\":
            out.append("\\\\")
        elif ch == "\n":
            out.append("\\n")
        elif ch == "\r":
            out.append("\\r")
        elif ch == "\t":
            out.append("\\t")
        elif code == 0x08:
            out.append("\\b")
        elif code == 0x0C:
            out.append("\\f")
        elif code < 0x20:
            out.append("\\u%04x" % code)
        else:
            out.append(ch)
    out.append('"')
    return "".join(out)


def fmt(x):
    if not math.isfinite(x):
        return "null"
    scaled = x * 10 ** DECIMALS
    if abs(scaled - math.floor(scaled) - 0.5) < 1e-6:
        raise SystemExit("%r sits on a %d-decimal rounding tie; change the fixture" % (x, DECIMALS))
    text = "%.*f" % (DECIMALS, x)
    if text.startswith("-") and set(text[1:]) <= set("0."):
        text = text[1:]
    return text


def encode(value, indent=0):
    if value is None:
        return "null"
    if value is True:
        return "true"
    if value is False:
        return "false"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        return fmt(value)
    if isinstance(value, str):
        return quote(value)
    pad, inner = " " * indent, " " * (indent + 2)
    if isinstance(value, list):
        if not value:
            return "[]"
        return "[\n" + ",\n".join(inner + encode(v, indent + 2) for v in value) + "\n" + pad + "]"
    if isinstance(value, dict):
        if not value:
            return "{}"
        keys = sorted(value, key=lambda k: k.encode("utf-8"))
        return "{\n" + ",\n".join(inner + quote(k) + ": " + encode(value[k], indent + 2) for k in keys) + "\n" + pad + "}"
    raise TypeError(type(value))


def main():
    if len(sys.argv) != 4:
        raise SystemExit(__doc__)
    folder, week_start, data_until = sys.argv[1:]
    events, skipped = read_store(folder)
    rollup_path = os.path.join(folder, "rollup-v1.json")
    rollup = {}
    if os.path.exists(rollup_path):
        with open(rollup_path, encoding="utf-8") as f:
            rollup = json.load(f)
    cutoff = parse_ts(data_until)
    if cutoff is None:
        raise SystemExit("data_until must look like 2026-10-25T13:00:00.000Z")
    model = build(events, rollup, Window.containing(week_start, cutoff))
    sys.stderr.write("%d events, %d skipped lines\n" % (len(events), skipped))
    sys.stdout.write(encode(model) + "\n")


if __name__ == "__main__":
    main()
