#!/usr/bin/env python3
"""Writes the synthetic stats folder for the W1 weekly-metrics golden fixture.

Three Hong Kong weeks of made-up play (no real child data), shaped like the files
`PerfEventStore` writes: one `events-YYYY-MM-DD.jsonl` per HKT day (sorted-key compact JSON
lines, as `PerfCodec.encodeLine`) plus `rollup-v1.json`. Deterministic: re-running rewrites the
same bytes. Then run `reference_model.py` to rebuild `expected-metrics.json` (see README.md).

Usage: python3 make_fixture.py [folder]   (default: this script's folder)
"""

import json
import os
import sys
from datetime import datetime, timedelta, timezone

HKT = timezone(timedelta(hours=8))
UTC = timezone.utc


def at(day, clock):
    """'2026-10-19', '18:05:30.250' (HKT) -> aware UTC datetime."""
    y, m, d = (int(p) for p in day.split("-"))
    hms, _, frac = clock.partition(".")
    hh, mm, ss = (int(p) for p in hms.split(":"))
    ms = int((frac + "000")[:3]) if frac else 0
    return datetime(y, m, d, hh, mm, ss, ms * 1000, tzinfo=HKT).astimezone(UTC)


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
        self.torn = {}

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

    def tear(self, ts, text):
        """A power cut mid-write: a partial last line with no newline."""
        self.torn[ts.astimezone(HKT).strftime("%Y-%m-%d")] = text

    def write(self, folder):
        for name in os.listdir(folder):
            if name.startswith("events-") and name.endswith(".jsonl"):
                os.remove(os.path.join(folder, name))
        for day in sorted(self.files):
            text = "".join(line + "\n" for line in self.files[day])
            if day in self.torn:
                text += self.torn[day]
            with open(os.path.join(folder, "events-%s.jsonl" % day), "w", encoding="utf-8", newline="") as f:
                f.write(text)


log = Log()
ROUND = [0]

QUIZ_SLOTS = {
    "twoPictureChoose": ["opt-fire", "opt-hktaxi"],
    "findTheSame": ["find-nytaxi", "find-target", "find-fire"],
    "countVehicles": ["count-2", "count-3", "count-4"],
    "halfMatch": ["half-bus", "half-taxi", "half-tanker"],
    "shapeCousin": ["shape-cone", "shape-wheel", "shape-toolbox"],
    "capacityCompare": ["cap-bus", "cap-taxi"],
    "moreFewer": ["lot-left", "lot-right"],
    "shadowMatch": ["shadow-fire", "shadow-hero", "shadow-truck"],
    "emptyBay": ["bay-a", "bay-b", "bay-c"],
}


def play_round(day, clock, kind, stars, *, seconds=40, first_try=True, misses=0, wrongs=(), outcome="solved",
               reason=None, hint=False, assisted=False, earned=None, dealt=None, extra=None, actor="child",
               mode="lock", session=None, practice=False, total_ms=None, active_ms=None, result=True,
               round_id=None):
    """game_dealt, judged taps (wrong ones carry tags), round_result `seconds` later."""
    ROUND[0] += 1
    rid = round_id or "r%03d" % ROUND[0]
    t0 = at(day, clock)
    fields = {
        "round": rid, "kind": kind, "item": "%s.item" % kind, "stars": stars,
        "pending_start": stars * 5, "pool": [kind], "deal_mode": "playtest" if actor == "parent_playtest" else "off",
        "slots": QUIZ_SLOTS.get(kind, ["slot-0", "slot-1", "slot-2"]),
    }
    fields.update(dealt or {})
    log.emit("game_dealt", t0, fields, actor=actor, mode=mode, session=session)
    answers = 0
    if not practice:
        for n, (choice, tags, fast) in enumerate(wrongs):
            log.emit("answer_attempt", t0 + timedelta(seconds=4 + 6 * n), {
                "round": rid, "kind": kind, "n": n + 1, "choice": choice, "correct": False, "tags": tags,
                "fast": fast, "repeat_wrong": False, "slot": n, "hint_on": False,
                "ms_since_deal": 4000 + 6000 * n, "ms_since_unlock": 900 if fast else 3200,
            }, actor=actor, mode=mode, session=session)
            answers += 1
        if outcome == "solved":
            log.emit("answer_attempt", t0 + timedelta(seconds=4 + 6 * len(wrongs)), {
                "round": rid, "kind": kind, "n": len(wrongs) + 1, "choice": "right", "correct": True, "tags": [],
                "fast": False, "repeat_wrong": False, "slot": 1, "hint_on": hint,
                "ms_since_deal": 4000 + 6000 * len(wrongs), "ms_since_unlock": 2500,
            }, actor=actor, mode=mode, session=session)
            answers += 1
    if not result:
        return rid
    t1 = t0 + timedelta(seconds=seconds)
    if total_ms is None:
        total_ms = seconds * 1000 - 250
    if active_ms is None:
        active_ms = min(total_ms, 3000 + 4000 * answers)
    if earned is None:
        earned = (stars * 5 if misses == 0 else max(0, stars * 5 - 5 * misses)) if outcome == "solved" else 0
    res = {
        "round": rid, "kind": kind, "item": "%s.item" % kind, "stars": stars, "outcome": outcome, "reason": reason,
        "first_try": (misses == 0 and outcome == "solved" and first_try) if answers > 0 else None,
        "misses": misses, "answers": answers, "hint_used": hint, "assisted": assisted,
        "pending_start": stars * 5, "earned_min": earned, "active_ms": active_ms, "total_ms": total_ms,
        "parent_ms": 0, "first_tap_ms": 2100 if answers else None, "mash_taps": 0,
        "wrong_choices": [w[0] for w in wrongs],
    }
    res.update(extra or {})
    log.emit("round_result", t1, res, actor=actor, mode=mode, session=session)
    return rid


def shape_extra(done, total, off_path, wrong_start=0, reverse=0):
    return {"practice": "shape_trace", "shapes_done": done, "shapes_total": total, "off_path_count": off_path,
            "lifts": 1, "wrong_start": wrong_start, "reverse_direction": reverse, "corner_overshoot": 0,
            "corner_cut": 0, "end_overshoot": 0, "strokes": total + 1, "tolerance": "standard",
            "mean_dev_u": 9.25, "duration_ms": 41000}


def road_extra(roads, total, off_path, wrong_start=0):
    return {"match_mode": "guided", "roads": roads, "roads_total": total, "off_path_count": off_path, "lifts": 0,
            "wrong_start": wrong_start, "strokes": total, "tolerance": "standard", "mean_dev_u": 12.5,
            "duration_ms": 36000}


def tap_extra(target, recount, trace=None, guide=None):
    out = {"practice": "tap_count", "target": target, "cars": target, "taps": target + recount,
           "recount_attempts": recount, "double_taps": 1, "tap_order": "reading", "idle_nudges": 0,
           "idle_reprompts": 0}
    if trace is not None:
        out.update({"trace_off_path_count": trace[0], "trace_wrong_start": trace[1], "trace_lifts": 0,
                    "numeral": target})
    if guide is not None:
        out.update({"guide_level": "standard", "guide_learned_before": 0, "guide_demo": "full",
                    "guide_redemos": 0, "guide_stalls": guide[1], "guide_ghost_to_end": 0,
                    "guide_helps": guide[1], "guide_clean": guide[0]})
    return out


def generated(level, slots=None, chance=None, **more):
    out = {"gen": "variants_v1", "level": level}
    if slots is not None:
        out["slots"] = slots
    if chance is not None:
        out["chance"] = chance
    out.update(more)
    return out


def tap_dealt(kind, target, cars, pick=False):
    return {"gen": "variants_v1", "level": 3 if pick else 2, "practice": "tap_count_pick" if pick else "tap_count",
            "target": target, "cars": cars, "scene": "site", "match_mode": "free" if pick else "guided",
            "slots": ["bay-%d" % i for i in range(cars)]}


def video(day, clock, video_id, watched, *, source="pick", actor="child", mode="play", session=None,
          end=True, progress=(), stop="ended", play=None):
    """video_start, video_progress every 60 s, video_end when `end`."""
    play = play or "p-%s-%s" % (day[5:], clock.replace(":", "")[:4])
    t0 = at(day, clock)
    log.emit("video_start", t0, {"play": play, "video": video_id, "source": source, "start_s": 0.0},
             actor=actor, mode=mode, session=session)
    for i, w in enumerate(progress):
        log.emit("video_progress", t0 + timedelta(seconds=60 * (i + 1)), {
            "play": play, "video": video_id, "pos_s": w, "watched_s": w, "wall_s": 60.0 * (i + 1)},
            actor=actor, mode=mode, session=session)
    if end:
        log.emit("video_end", t0 + timedelta(seconds=watched + 3), {
            "play": play, "video": video_id, "source": source, "stop_reason": stop, "completed": stop == "ended",
            "watched_s": watched, "wall_s": watched + 3, "telemetry": "full", "resume_saved": False},
            actor=actor, mode=mode, session=session)
    return play


def parent(day, clock, t, fields, session):
    log.emit(t, at(day, clock), fields, actor="parent", mode="parent", session=session)


def build():
    # ---------------- Week 2026-10-05 (records start on Thursday: a partial trend week) ----------------
    log.start("L-1008", at("2026-10-08", "18:00:00"), "0.29.0", "s-1008a")
    play_round("2026-10-08", "18:01:00", "countVehicles", 1, seconds=35)
    play_round("2026-10-08", "18:03:00", "findTheSame", 1, misses=1, wrongs=[("find-fire", ["same_color"], False)])
    # Count, then trace written before guide_clean existed (v0.29): the trace fields decide.
    play_round("2026-10-08", "18:06:00", "tapCountTrace", 2, practice=True, dealt=tap_dealt("tapCountTrace", 3, 3),
               extra=tap_extra(3, 0, trace=(1, 0)))
    play_round("2026-10-08", "18:09:00", "tapCountTrace", 2, practice=True, dealt=tap_dealt("tapCountTrace", 4, 4),
               extra=tap_extra(4, 0, trace=(3, 0)))
    play_round("2026-10-08", "18:12:00", "capacityCompare", 1)
    video("2026-10-08", "18:20:00", "vid-a", 610.5)

    log.start("L-1009", at("2026-10-09", "17:30:00"), "0.29.0", "s-1009a")
    play_round("2026-10-09", "17:31:00", "moreFewer", 1)
    play_round("2026-10-09", "17:33:00", "shadowMatch", 2)
    play_round("2026-10-09", "17:36:00", "traceLines", 1, practice=True, dealt=generated(1, match_mode="guided"),
               extra=shape_extra(2, 2, 0))
    video("2026-10-09", "17:45:00", "vid-b", 422.25)

    log.start("L-1011", at("2026-10-11", "23:40:00"), "0.29.0", "s-1011a")
    play_round("2026-10-11", "23:41:00", "emptyBay", 1)
    # Dealt Sunday 23:59, solved Monday 00:01: after that week's cut-off, so in no week.
    play_round("2026-10-11", "23:59:00", "sequenceShortToLong", 1, seconds=120)

    # ---------------- Week 2026-10-12 (the previous week) ----------------
    log.start("L-1012", at("2026-10-12", "17:00:00"), "0.31.0", "s-1012a")
    # A pre-v0.24.1 guided road dealt under kind lineMatch: practice, road family.
    play_round("2026-10-12", "17:01:00", "lineMatch", 1, practice=True,
               dealt=generated(1, match_mode="guided", pairs=2, category="numbers"), extra=road_extra(2, 2, 0))
    play_round("2026-10-12", "17:04:00", "lineMatch", 2, dealt=generated(2, pairs=3, match_mode="free"))
    video("2026-10-12", "17:10:00", "vid-a", 480.0)

    log.new_session("s-1013a", at("2026-10-13", "18:00:00"))
    play_round("2026-10-13", "18:00:30", "countVehicles", 2, misses=1,
               wrongs=[("count-4", ["over_by_1"], True)], dealt=generated(2, slots=["count-3", "count-4", "count-5", "count-6"]))
    play_round("2026-10-13", "18:03:00", "halfMatch", 1, actor="parent_uat", session="s-1013u")  # UAT: not counted

    log.new_session("s-1015a", at("2026-10-15", "17:20:00"))
    play_round("2026-10-15", "17:20:30", "tapCountAll", 1, practice=True, dealt=tap_dealt("tapCountAll", 4, 4),
               extra=tap_extra(4, 0))
    play_round("2026-10-15", "17:22:00", "tapCountTrace", 2, practice=True, dealt=tap_dealt("tapCountTrace", 5, 5),
               extra=tap_extra(5, 0, trace=(0, 0), guide=(1, 0)))
    play_round("2026-10-15", "17:25:00", "emptyBay", 1)
    parent("2026-10-15", "17:40:00", "parent_enter", {"reason": "corner"}, "s-1015a")
    play_round("2026-10-15", "17:41:00", "traceShapesDotted", 0, practice=True, actor="parent_playtest", mode="parent",
               session="s-1015a", dealt=generated(1, match_mode="guided"), extra=shape_extra(3, 3, 0))
    parent("2026-10-15", "17:45:00", "parent_leave", {}, "s-1015a")

    log.new_session("s-1016a", at("2026-10-16", "17:00:00"))
    play_round("2026-10-16", "17:00:30", "shapeCousin", 1)
    play_round("2026-10-16", "17:02:00", "twoPictureChoose", 1)
    play_round("2026-10-16", "17:04:00", "traceShapesDotted", 1, practice=True, dealt=generated(1, match_mode="guided"),
               extra=shape_extra(3, 3, 4))
    video("2026-10-16", "17:10:00", "vid-c", 905.75)

    log.new_session("s-1017a", at("2026-10-17", "10:00:00"))
    play_round("2026-10-17", "10:00:30", "moreFewer", 3, outcome="zeroed", misses=2,
               wrongs=[("lot-left", ["fewer"], False), ("lot-left", ["fewer"], True)])
    play_round("2026-10-17", "10:03:00", "findTheSame", 1, outcome="abandoned", reason="superseded", seconds=20)
    play_round("2026-10-17", "10:04:00", "findTheSame", 1)

    log.start("L-1018", at("2026-10-18", "23:40:00"), "0.33.1", "s-1018b")
    play_round("2026-10-18", "23:41:00", "findTheSame", 1)
    # Sunday 23:59:59 belongs to this week; Monday 00:00 to the next.
    video("2026-10-18", "23:57:06", "vid-b", 170.0)

    # ---------------- Week 2026-10-19 (the report week, made Sunday 21:00) ----------------
    play_round("2026-10-19", "00:00:00", "shadowMatch", 1, seconds=42)
    log.new_session("s-1019a", at("2026-10-19", "18:00:00"))
    play_round("2026-10-19", "18:00:30", "halfMatch", 1)  # first raw round; the rollup knows it
    play_round("2026-10-19", "18:02:00", "countVehicles", 2, misses=1, wrongs=[("count-5", ["over_by_1"], True)],
               dealt=generated(2, slots=["count-3", "count-4", "count-5", "count-6"]))
    play_round("2026-10-19", "18:05:00", "lineMatch", 2, dealt=generated(2, pairs=3, match_mode="free"))
    play_round("2026-10-19", "18:08:00", "tapCountTrace", 2, practice=True, dealt=tap_dealt("tapCountTrace", 6, 6),
               extra=tap_extra(6, 0, trace=(2, 0), guide=(1, 0)))
    play_round("2026-10-19", "18:12:00", "traceShapesArrows", 2, practice=True, dealt=generated(2, match_mode="guided"),
               extra=shape_extra(3, 3, 2))
    video("2026-10-19", "18:40:00", "vid-a", 702.5, progress=(59.5, 119.5))

    # Tuesday: only parent test mode (家長測試中) — no child play.
    log.new_session("s-1020p", at("2026-10-20", "19:00:00"), reason="launch", actor="parent", mode="parent")
    parent("2026-10-20", "19:00:10", "uat_mode", {"on": True, "reason": "parent"}, "s-1020p")
    log.new_session("s-1020u", at("2026-10-20", "19:01:00"), reason="after_parent", actor="parent_uat")
    play_round("2026-10-20", "19:01:30", "findTheSame", 2, actor="parent_uat", dealt=generated(2))
    play_round("2026-10-20", "19:03:00", "traceLines", 1, actor="parent_uat", practice=True,
               dealt=generated(1, match_mode="guided"), extra=shape_extra(2, 2, 0))
    video("2026-10-20", "19:10:00", "vid-c", 300.0, actor="parent_uat")

    # Wednesday: settings change and a playtest in parent mode, then child play.
    log.new_session("s-1021p", at("2026-10-21", "17:00:00"), reason="launch", actor="parent", mode="parent")
    parent("2026-10-21", "17:00:20", "config_change", {"what": "lineMatch_tolerance", "kind": "lineMatch",
                                                      "value": "wide", "category_mix": "numbers:35,body:30"}, "s-1021p")
    play_round("2026-10-21", "17:02:00", "tapCountTraceEnglish", 0, practice=True, actor="parent_playtest",
               mode="parent", session="s-1021p", dealt=tap_dealt("tapCountTraceEnglish", 3, 3),
               extra=tap_extra(3, 0, trace=(0, 0), guide=(1, 0)))
    parent("2026-10-21", "17:10:00", "parent_leave", {}, "s-1021p")
    log.new_session("s-1021a", at("2026-10-21", "17:20:00"), reason="after_parent")
    play_round("2026-10-21", "17:20:30", "lineMatch", 3, misses=1,
               wrongs=[("submit", ["wrong_target", "category:numbers"], False)],
               dealt=generated(3, pairs=4, match_mode="free"))
    play_round("2026-10-21", "17:24:00", "tapCountPick", 3, dealt=tap_dealt("tapCountPick", 3, 5, pick=True))
    play_round("2026-10-21", "17:27:00", "tapCountPickEnglish", 3, dealt=tap_dealt("tapCountPickEnglish", 4, 6, pick=True))
    play_round("2026-10-21", "17:30:00", "capacityCompare", 1)
    play_round("2026-10-21", "17:32:00", "mysteryQuiz", 1, dealt={"gen": "beta_v1"})  # unknown kind, no chance
    video("2026-10-21", "18:10:00", "vid-b", 845.0)
    log.new_session("s-1021b", at("2026-10-21", "23:58:00"))
    # Crosses midnight HKT: counted on Wednesday, the day it was dealt.
    play_round("2026-10-21", "23:58:30", "moreFewer", 2, seconds=160, total_ms=160000)

    # Thursday: the app updates to 0.34.0, which writes game_dealt.chance.
    log.start("L-1022", at("2026-10-22", "07:00:00"), "0.34.0", "s-1022s")
    log.new_session("s-1022a", at("2026-10-22", "16:00:00"))
    play_round("2026-10-22", "16:00:30", "countVehicles", 2, dealt=generated(2, slots=["count-3", "count-4", "count-5", "count-6"],
                                                                          chance=0.25))
    play_round("2026-10-22", "16:03:00", "findTheSame", 2, dealt=generated(2, chance=1.0 / 3.0))
    play_round("2026-10-22", "16:06:00", "tapCountTraceEnglish", 2, practice=True,
               dealt=dict(tap_dealt("tapCountTraceEnglish", 7, 7), chance=1),
               extra=tap_extra(7, 0, trace=(1, 0), guide=(0, 3)))
    play_round("2026-10-22", "16:09:00", "tapCountTraceEnglish", 2, practice=True,
               dealt=dict(tap_dealt("tapCountTraceEnglish", 8, 8), chance=1),
               extra=tap_extra(8, 0, trace=(0, 0), guide=(1, 1)))
    # Walked away for 15 minutes: game time counts at most 10 minutes per round.
    play_round("2026-10-22", "16:12:00", "tapCountAll", 1, practice=True, seconds=900, total_ms=900000,
               dealt=dict(tap_dealt("tapCountAll", 5, 5), chance=1), extra=tap_extra(5, 0))
    video("2026-10-22", "16:30:00", "vid-c", 600.25)
    log.new_session("s-1022b", at("2026-10-22", "19:00:00"))  # excluded at 19:30, re-included on Sunday 22:00
    play_round("2026-10-22", "19:00:30", "emptyBay", 1, dealt={"chance": 1.0 / 3.0})
    play_round("2026-10-22", "19:02:00", "sequenceShortToLong", 2, dealt={"chance": 1.0 / 24.0})
    play_round("2026-10-22", "19:05:00", "traceLines", 1, practice=True,
               dealt=generated(1, match_mode="guided", chance=1), extra=shape_extra(2, 2, 1))
    parent("2026-10-22", "19:30:00", "stats_exclude", {"target_session": "s-1022b"}, "s-1022b")

    # Friday: practice, then a power cut while a video plays (no video_end, torn last line).
    log.new_session("s-1023a", at("2026-10-23", "17:00:00"))
    play_round("2026-10-23", "17:00:30", "twoPictureChoose", 1, dealt={"chance": 0.5})
    play_round("2026-10-23", "17:02:00", "traceShapesFree", 3, practice=True,
               dealt=generated(3, match_mode="guided", chance=1),
               extra=dict(shape_extra(3, 3, 1), ink_outside_ratio=0.18, erasers=1))
    play_round("2026-10-23", "17:05:00", "traceShapesFree", 3, practice=True,
               dealt=generated(3, match_mode="guided", chance=1),
               extra=dict(shape_extra(3, 3, 0), ink_outside_ratio=None, erasers=0))
    play_round("2026-10-23", "17:08:00", "lineMatchGuidedStraight", 1, practice=True,
               dealt=generated(1, match_mode="guided", pairs=3, chance=1), extra=road_extra(3, 3, 1))
    play_round("2026-10-23", "17:11:00", "lineMatchGuidedBridge", 2, practice=True,
               dealt=generated(2, match_mode="guided", pairs=3, chance=1), extra=road_extra(3, 3, 0, wrong_start=1))
    play_round("2026-10-23", "17:14:00", "mysteryTrace", 1, practice=True, dealt={"match_mode": "guided"},
               extra={"strokes": 4})
    video("2026-10-23", "17:30:00", "vid-a", 0, end=False, progress=(59.8, 119.6, 179.4))
    log.tear(at("2026-10-23", "17:33:30"),
             '{"actor":"child","app":"0.34.0","launch":"L-1022","mode":"play","mono":'
             '37830.5,"play":"p-10-23-1730","pos_s":209.4,"seq":')

    # Saturday: power back; a crash mid-round; a forgotten test-mode session the parent excluded.
    log.start("L-1024a", at("2026-10-24", "09:00:00"), "0.34.0", "s-1024s")
    log.new_session("s-1024a", at("2026-10-24", "10:00:00"))
    play_round("2026-10-24", "10:00:30", "tapCountAllEnglish", 1, practice=True,
               dealt=dict(tap_dealt("tapCountAllEnglish", 4, 4), chance=1), extra=tap_extra(4, 0))
    play_round("2026-10-24", "10:03:00", "tapCountAll", 1, practice=True,
               dealt=dict(tap_dealt("tapCountAll", 6, 6), chance=1), extra=tap_extra(6, 1))
    video("2026-10-24", "10:06:00", "vid-b", 300.0)
    play_round("2026-10-24", "10:20:00", "shapeCousin", 1, dealt={"chance": 1.0 / 3.0}, result=False)  # crash
    log.start("L-1024b", at("2026-10-24", "10:31:00"), "0.34.0", "s-1024r")
    log.new_session("s-1024x", at("2026-10-24", "15:00:00"))
    play_round("2026-10-24", "15:00:30", "countVehicles", 1, dealt=generated(1, slots=["count-1", "count-2", "count-3"],
                                                                          chance=1.0 / 3.0))
    play_round("2026-10-24", "15:03:00", "traceLines", 1, practice=True,
               dealt=generated(1, match_mode="guided", chance=1), extra=shape_extra(2, 2, 0))
    video("2026-10-24", "15:10:00", "vid-c", 512.0)
    parent("2026-10-24", "16:00:00", "stats_exclude", {"target_session": "s-1024x"}, "s-1024x")
    log.new_session("s-1024t", at("2026-10-24", "16:30:00"), reason="after_parent", actor="parent_test_visa", mode="play")
    video("2026-10-24", "16:30:30", "vid-a", 58.0, actor="parent_test_visa")

    # Sunday: the report is made at 21:00; later events are past the cut-off.
    log.new_session("s-1025a", at("2026-10-25", "10:00:00"))
    play_round("2026-10-25", "10:00:30", "halfMatch", 2, dealt={"chance": 1.0 / 3.0})
    play_round("2026-10-25", "10:03:00", "findTheSame", 1, misses=2, hint=True, assisted=True,
               wrongs=[("find-nytaxi", ["same_shape", "diff_color"], False), ("find-fire", ["same_color"], True)],
               dealt=generated(1, chance=1.0 / 3.0))
    play_round("2026-10-25", "10:07:00", "capacityCompare", 2, dealt={"chance": 0.5})
    play_round("2026-10-25", "10:09:00", "countVehicles", 1, misses=1, wrongs=[("count-3", ["over_by_1"], True)],
               dealt=generated(1, slots=["count-1", "count-2", "count-3"], chance=1.0 / 3.0))
    play_round("2026-10-25", "10:12:00", "countVehicles", 1, misses=1, wrongs=[("count-1", ["under_by_1"], False)],
               dealt=generated(1, slots=["count-1", "count-2", "count-3"], chance=1.0 / 3.0))
    play_round("2026-10-25", "10:15:00", "tapLetterAll", 1,
               dealt={"gen": "letters_v1", "level": 1, "match_mode": "test", "chance": 1.0 / 45.0})
    play_round("2026-10-25", "10:18:00", "shadowMatch", 2, dealt={"chance": 1.0 / 3.0})
    play_round("2026-10-25", "10:20:00", "emptyBay", 1, dealt={"chance": 1.0 / 3.0})
    play_round("2026-10-25", "10:22:00", "traceShapesDotted", 1, practice=True, outcome="abandoned",
               reason="superseded", seconds=15, dealt=generated(1, match_mode="guided", chance=1),
               extra=shape_extra(1, 3, 0))
    log.emit("future_event", at("2026-10-25", "11:00:00"), {"note": "a newer build's event type"}, actor="system")
    video("2026-10-25", "11:30:00", "vid-c", 400.0, stop="parent_unlock", progress=(59.0, 119.0))
    parent("2026-10-25", "11:37:00", "parent_enter", {"reason": "corner"}, "s-1025a")
    parent("2026-10-25", "11:39:00", "parent_leave", {}, "s-1025a")
    log.new_session("s-1025b", at("2026-10-25", "11:39:05"), reason="after_parent", mode="play")
    video("2026-10-25", "11:39:10", "vid-c", 240.0, source="after_parent")
    log.new_session("s-1025c", at("2026-10-25", "20:55:00"))
    # Dealt 20:58, solved 21:02: still open at the 21:00 cut-off, so not counted.
    play_round("2026-10-25", "20:58:00", "emptyBay", 2, seconds=240, dealt={"chance": 1.0 / 3.0})
    play_round("2026-10-25", "21:30:00", "shadowMatch", 1, dealt={"chance": 1.0 / 3.0})  # after the cut-off
    parent("2026-10-25", "22:00:00", "stats_include", {"target_session": "s-1022b"}, "s-1025c")


ROLLUP = {
    "rollup_schema": 2,
    "folded_days": ["2026-06-30", "2026-07-02"],
    "days": {
        "2026-06-30": {
            "games": {
                "halfMatch|1": {"deals": 3, "answered": 3, "first_try": 2, "misses": 1, "solved": 3, "zeroed": 0,
                                "abandoned": 0, "hinted": 0, "active_ms": 21000, "active_hist": [1, 2, 0, 0, 0, 0]},
                "capacityCompare|1": {"deals": 2, "answered": 2, "first_try": 2, "misses": 0, "solved": 2,
                                      "zeroed": 0, "abandoned": 0, "hinted": 0, "active_ms": 9000,
                                      "active_hist": [2, 0, 0, 0, 0, 0]},
            },
            "videos": {}, "uncounted_rounds": 0, "uncounted_plays": 0, "multi_page_visits": 0, "paged_visits": 0,
        },
        "2026-07-02": {
            "games": {
                "lineMatch|1|variants_v1|guided": {"deals": 1, "answered": 0, "first_try": 0, "misses": 0,
                                                   "solved": 1, "zeroed": 0, "abandoned": 0, "hinted": 0,
                                                   "active_ms": 0, "active_hist": [0, 0, 0, 0, 0, 0]},
                "tapLetterWrite|1": {"deals": 0, "answered": 0, "first_try": 0, "misses": 0, "solved": 0,
                                     "zeroed": 0, "abandoned": 0, "hinted": 0, "active_ms": 0,
                                     "active_hist": [0, 0, 0, 0, 0, 0]},
            },
            "videos": {}, "uncounted_rounds": 1, "uncounted_plays": 0, "multi_page_visits": 0, "paged_visits": 0,
        },
    },
}


def main():
    folder = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.abspath(__file__))
    build()
    log.write(folder)
    with open(os.path.join(folder, "rollup-v1.json"), "w", encoding="utf-8", newline="") as f:
        f.write(json.dumps(ROLLUP, sort_keys=True, indent=2) + "\n")


if __name__ == "__main__":
    main()
