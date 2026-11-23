"""Locks, pause and the child's notifications (Del H3/H4)."""

from __future__ import annotations

from datetime import date, datetime, timedelta

import pytest

from custom_components.lommepenge.family import Family, FamilyError

MONDAY = datetime(2026, 11, 23, 9, 0)  # tasks are created in the morning
DEADLINE = MONDAY.replace(hour=18)


def act(family: Family, action_type: str, now: datetime, **payload):
    return family.apply_action({"type": action_type, "payload": payload}, now)


def make_family(**settings) -> Family:
    family = Family()
    family.cleanup(MONDAY)
    act(family, "add_child", MONDAY - timedelta(days=30), id="emma", name="Emma")
    act(family, "add_child", MONDAY - timedelta(days=30), id="oscar", name="Oscar")
    for key, value in settings.items():
        act(family, "set_setting", MONDAY, key=key, value=value)
    add_task(family, "t1", "Dishes")
    return family


def add_task(family: Family, task_id: str, title: str, **fields) -> None:
    act(
        family,
        "create_task",
        fields.pop("created", MONDAY),
        **{
            "id": task_id,
            "title": title,
            "amountOre": 500,
            "recurrence": "daily",
            "mandatory": True,
            **fields,
        },
    )


def at(hour: int, minute: int = 0, day: int = 0, second: int = 0) -> datetime:
    return MONDAY.replace(hour=hour, minute=minute, second=second) + timedelta(days=day)


def lock(family: Family, now: datetime, child: str = "emma") -> dict:
    return family.lock_json(child, now)


def use(family: Family, now: datetime, child: str = "emma", event: str = "screen_on") -> None:
    act(family, "report_use", now, childId=child, event=event, at=1795442400)


def complete(family: Family, now: datetime, task_id: str = "t1", child: str = "emma"):
    return act(family, "complete_task", now, taskId=task_id, childId=child)


def notifications(family: Family, now: datetime, child: str = "emma") -> list[dict]:
    return family.notifications_json(child, now)


# ---- Lifecycle ------------------------------------------------------------------


def test_lock_waits_for_use_then_runs_and_ends() -> None:
    family = make_family()
    family.tick(at(17, 59))
    assert lock(family, at(17, 59))["status"] == "none"

    family.tick(at(18, 1))
    pending = lock(family, at(18, 1))
    assert pending["status"] == "pending"
    assert pending["reason"] == "Missing: Dishes (due 18:00)"
    assert pending["minutes"] == 60
    assert pending["pendingSince"] == "2026-11-23T18:01:00.000"
    assert pending["pendingUntil"] == "2026-11-24T18:01:00.000"
    assert pending["endsAt"] is None
    assert [r["kind"] for r in pending["reasons"]] == ["overdue"]
    assert pending["reasons"][0]["taskTitle"] == "Dishes"
    # Oscar has the same task overdue - his own lock.
    assert lock(family, at(18, 1), "oscar")["status"] == "pending"

    use(family, at(19, 0))
    running = lock(family, at(19, 0))
    assert running["status"] == "running"
    assert running["startedAt"] == "2026-11-23T19:00:00.000"
    assert running["endsAt"] == "2026-11-23T20:00:00.000"
    assert family.summary("F", at(19, 0))["children"][0]["restricted"] is True
    assert [e["event"] for e in family.pop_events()] == ["lock_started"]

    # A second report while it runs changes nothing.
    use(family, at(19, 30), event="user_present")
    assert lock(family, at(19, 30))["endsAt"] == "2026-11-23T20:00:00.000"

    # The state never shows a lock that has run out, even before the tick.
    assert lock(family, at(20, 0))["status"] == "none"
    assert family.tick(at(20, 0, second=30)) is True
    assert family.current_lock("emma") is None
    assert family.data["locks"][0]["status"] == "ended"
    assert family.data["locks"][0]["endedAt"] == "2026-11-23T20:00:00.000"
    assert [e["event"] for e in family.pop_events()] == ["lock_ended"]


def test_pending_lock_lapses_after_24_hours() -> None:
    family = make_family()
    family.tick(at(18, 1))
    assert lock(family, at(18, 0, day=1))["status"] == "pending"
    complete(family, at(12, day=1))  # today's occurrence is done in time
    family.tick(at(18, 1, day=1))
    assert family.data["locks"][0]["status"] == "lapsed"
    assert family.data["locks"][0]["endedAt"] == "2026-11-24T18:01:00.000"
    # Use after the lapse starts nothing.
    use(family, at(18, 2, day=1))
    assert lock(family, at(18, 2, day=1))["status"] == "none"


def test_report_use_without_a_lock_and_invalid_event() -> None:
    family = make_family()
    use(family, at(12))  # nothing pending - nothing happens
    assert family.data["locks"] == []
    with pytest.raises(FamilyError, match="event"):
        act(family, "report_use", at(12), childId="emma", event="screen_off")
    with pytest.raises(FamilyError):
        act(family, "report_use", at(12), childId="nobody", event="screen_on")


# ---- Late completion and money ---------------------------------------------------


def test_late_task_done_before_the_lock_starts_gives_a_short_lock() -> None:
    family = make_family()
    family.tick(at(18, 5))
    completion = complete(family, at(18, 20))
    assert completion["late"] is True and completion["amountAtCompletionOre"] == 500
    pending = lock(family, at(18, 20))
    assert pending["status"] == "pending"
    assert pending["minutes"] == 10  # latePauseMinutes
    assert pending["reason"] == "Done late: Dishes"

    use(family, at(18, 30))
    assert lock(family, at(18, 30))["endsAt"] == "2026-11-23T18:40:00.000"
    family.tick(at(18, 41))
    assert lock(family, at(18, 41))["status"] == "none"
    # It still gives money, and nothing was forfeited.
    act(family, "approve_completion", at(19), completionId=completion["id"])
    assert family.balance_ore("emma") == 500
    assert not any(n["type"] == "forgotten" for n in notifications(family, at(19)))


def test_late_pause_zero_means_no_lock() -> None:
    family = make_family(latePauseMinutes=0)
    family.tick(at(18, 5))
    complete(family, at(18, 20))
    assert lock(family, at(18, 20))["status"] == "none"
    assert family.data["locks"][0]["status"] == "cancelled"
    # The occurrence has had its penalty: a rejection does not lock again.
    completion = family.data["completions"][0]
    act(family, "reject_completion", at(18, 30), completionId=completion["id"])
    assert lock(family, at(18, 30))["status"] == "none"


def test_done_while_the_lock_runs_earns_money() -> None:
    family = make_family()
    family.tick(at(18, 5))
    use(family, at(18, 10))
    completion = complete(family, at(18, 30))
    assert completion["amountAtCompletionOre"] == 500
    # The lock is not shortened.
    assert lock(family, at(18, 30))["endsAt"] == "2026-11-23T19:10:00.000"
    family.tick(at(19, 11))
    assert not any(n["type"] == "forgotten" for n in notifications(family, at(19, 11)))


def test_after_the_lock_has_run_out_the_task_gives_nothing() -> None:
    family = make_family()
    family.tick(at(18, 5))
    use(family, at(18, 10))
    family.tick(at(19, 10, second=30))  # the lock runs out, the task is still not done

    forgotten = [n for n in notifications(family, at(19, 11)) if n["type"] == "forgotten"]
    assert len(forgotten) == 1
    assert forgotten[0]["message"] == "You forgot Dishes – it gives no money today"
    assert forgotten[0]["at"] == "2026-11-23T19:10:30.000"
    da = family.notifications_json("emma", at(19, 11), "da")
    assert "Du glemte Dishes – den giver ikke penge i dag" in [n["message"] for n in da]

    entry = family.task_entries("emma", at(19, 11))[0]
    assert entry["status"] == "overdue" and entry["forfeited"] is True
    assert entry["amountOre"] == 0
    completion = complete(family, at(20))
    assert completion["amountAtCompletionOre"] == 0
    act(family, "approve_completion", at(20), completionId=completion["id"])
    assert family.balance_ore("emma") == 0
    # No new lock for the same occurrence.
    assert lock(family, at(20))["status"] == "none"


# ---- One lock at a time, one penalty per occurrence --------------------------------


def test_causes_merge_and_are_absorbed() -> None:
    family = make_family()
    add_task(family, "t2", "Tidy up", dueTime="18:30")
    add_task(family, "t3", "Homework", dueTime="20:00")
    family.tick(at(18, 5))
    family.tick(at(18, 35))
    pending = lock(family, at(18, 35))
    assert [r["taskTitle"] for r in pending["reasons"]] == ["Dishes", "Tidy up"]
    assert pending["reason"] == "Missing: Dishes (due 18:00); Missing: Tidy up (due 18:30)"
    assert len([x for x in family.data["locks"] if x["childId"] == "emma"]) == 1

    use(family, at(19, 30))
    family.tick(at(20, 5))  # Homework is late while the lock runs: absorbed
    running = lock(family, at(20, 5))
    assert running["endsAt"] == "2026-11-23T20:30:00.000"
    assert running["reasons"][-1] == {
        **running["reasons"][-1],
        "taskTitle": "Homework",
        "absorbed": True,
    }
    family.tick(at(20, 31))
    # All three were part of the lock that ran out: forfeited, no new lock.
    assert lock(family, at(20, 31))["status"] == "none"
    assert len([x for x in family.data["locks"] if x["childId"] == "emma"]) == 1
    forgotten = {
        n["taskTitle"] for n in notifications(family, at(20, 31)) if n["type"] == "forgotten"
    }
    assert forgotten == {"Dishes", "Tidy up", "Homework"}


def test_lift_lock_clears_and_never_relocks_the_same_occurrence() -> None:
    family = make_family()
    family.tick(at(18, 5))
    act(family, "lift_lock", at(18, 10), childId="emma")
    assert lock(family, at(18, 10))["status"] == "none"
    assert [e["event"] for e in family.pop_events()] == ["lock_lifted"]
    family.tick(at(18, 15))
    assert lock(family, at(18, 15))["status"] == "none"
    # A lifted lock was never run out: the task still gives money.
    completion = complete(family, at(19))
    assert completion["amountAtCompletionOre"] == 500
    act(family, "approve_completion", at(19), completionId=completion["id"])

    # A new cause can lock again (the next day's occurrence).
    family.cleanup(at(0, 1, day=1))
    family.tick(at(18, 5, day=1))
    assert lock(family, at(18, 5, day=1))["status"] == "pending"
    use(family, at(18, 6, day=1))
    act(family, "lift_lock", at(18, 7, day=1), childId="emma")  # running -> lifted
    assert lock(family, at(18, 7, day=1))["status"] == "none"
    # The old alias from the restriction model still lifts.
    act(family, "suspend_restriction", at(18, 8, day=1), childId="emma")


def test_rejection_locks_with_reason() -> None:
    family = make_family()
    add_task(family, "free", "Wash the car", mandatory=False)
    completion = complete(family, at(12))
    act(family, "reject_completion", at(13), completionId=completion["id"], reason="  Still dirty ")
    assert family.completion(completion["id"])["rejectReason"] == "Still dirty"
    pending = lock(family, at(13))
    assert pending["status"] == "pending" and pending["minutes"] == 60
    assert pending["reasons"][0]["kind"] == "rejected"
    assert pending["reasons"][0]["reason"] == "Still dirty"
    assert pending["reason"] == "Rejected: Dishes"
    rejected = notifications(family, at(13))[0]
    assert rejected["type"] == "rejected" and rejected["reason"] == "Still dirty"
    assert rejected["message"] == "Dishes was rejected: Still dirty"

    # Rejected again (retry): nothing new.
    act(family, "reject_completion", at(13, 1), completionId=completion["id"])
    assert len(notifications(family, at(13, 1))) == 1

    # An optional task: the child is told, but no lock.
    optional = complete(family, at(14), "free")
    act(family, "reject_completion", at(14), completionId=optional["id"])
    assert notifications(family, at(14))[0]["message"] == "Wash the car was rejected"
    assert len(lock(family, at(14))["reasons"]) == 1

    # History: the reason is the rejection's note.
    items = family.history(date(2026, 11, 24), "emma", {"rejected"})["items"]
    assert {i["note"] for i in items} == {"Still dirty", None}


def test_late_then_rejected_is_one_penalty() -> None:
    family = make_family()
    family.tick(at(18, 5))
    completion = complete(family, at(18, 20))
    act(family, "reject_completion", at(18, 30), completionId=completion["id"])
    pending = lock(family, at(18, 30))
    assert [r["kind"] for r in pending["reasons"]] == ["late"]
    assert pending["minutes"] == 10


# ---- Midnight ---------------------------------------------------------------------


def test_midnight_drops_the_task_but_keeps_the_pending_lock() -> None:
    family = make_family()
    family.tick(at(18, 5))
    family.cleanup(at(0, 1, day=1))
    family.tick(at(0, 1, day=1))
    assert [m["date"] for m in family.data["missed"]] == ["2026-11-23", "2026-11-23"]
    assert lock(family, at(0, 1, day=1))["status"] == "pending"
    # The child uses the tablet in the morning: the lock runs then.
    use(family, at(7, 0, day=1))
    assert lock(family, at(7, 0, day=1))["endsAt"] == "2026-11-24T08:00:00.000"
    family.tick(at(8, 1, day=1))
    # The dropped occurrence is not "forgotten" - it is gone already.
    assert not any(n["type"] == "forgotten" for n in notifications(family, at(8, 1, day=1)))


def test_midnight_pending_lock_still_lapses() -> None:
    family = make_family()
    family.tick(at(23, 0))
    family.cleanup(at(0, 1, day=1))
    family.tick(at(22, 59, day=1))
    assert family.current_lock("emma") is not None
    family.tick(at(23, 0, day=1))
    assert family.data["locks"][0]["status"] == "lapsed"


# ---- Pause --------------------------------------------------------------------------


def test_pause_removes_mandatory_status_but_keeps_money() -> None:
    family = make_family()
    family.tick(at(18, 5))
    act(family, "set_pause", at(18, 10), childId="emma", paused=True, until="2026-11-26")
    assert lock(family, at(18, 10))["status"] == "none"  # pausing lifts the lock

    entry = family.task_entries("emma", at(19))[0]
    assert entry["mandatory"] is False and entry["deadline"] is None
    assert entry["status"] == "available"
    family.tick(at(19))
    assert lock(family, at(19))["status"] == "none"
    completion = complete(family, at(19))
    assert completion["late"] is False and completion["amountAtCompletionOre"] == 500
    act(family, "approve_completion", at(19), completionId=completion["id"])

    state = family.state_json("F", at(19), "emma")["children"][0]
    assert state["paused"] is True and state["pausedUntil"] == "2026-11-26"
    # The sibling is not paused.
    assert family.task_entries("oscar", at(19))[0]["status"] == "overdue"

    # Nothing is missed at midnight while paused.
    family.cleanup(at(0, 1, day=2))
    assert {m["childId"] for m in family.data["missed"]} == {"oscar"}

    # It resumes by itself on the end date, and nothing from the pause is late.
    family.tick(at(0, 0, day=3))
    assert family.is_paused("emma", at(0, 0, day=3)) is False
    assert "pause" not in family.child("emma")
    assert family.child("emma")["resumedAt"] == "2026-11-26T00:00:00.000"
    entry = family.task_entries("emma", at(12, day=3))[0]
    assert entry["mandatory"] is True and entry["date"] == "2026-11-26"
    assert entry["status"] == "available"
    family.tick(at(18, 1, day=3))
    assert lock(family, at(18, 1, day=3))["status"] == "pending"


def test_pause_without_end_and_resume() -> None:
    family = make_family()
    add_task(family, "w", "Change sheets", recurrence="weekly")
    act(family, "set_pause", at(12), childId="emma", paused=True)
    assert family.paused_until("emma", at(12)) is None
    # Ten days later, still paused, nothing missed and no locks.
    for day in range(1, 11):
        family.cleanup(at(0, 1, day=day))
        family.tick(at(20, day=day))
    assert not [m for m in family.data["missed"] if m["childId"] == "emma"]
    assert family.data["locks"] == [] or all(
        lock_["childId"] == "oscar" for lock_ in family.data["locks"]
    )
    act(family, "set_pause", at(12, day=10), childId="emma", paused=False)
    entries = {e["taskId"]: e for e in family.task_entries("emma", at(12, day=10))}
    # Starting over after the pause: the weekly task is due now, not weeks ago.
    assert entries["w"]["date"] == "2026-12-03" and entries["w"]["status"] == "available"
    # Resuming twice is fine.
    act(family, "set_pause", at(12, day=10), childId="emma", paused=False)


def test_pause_validation() -> None:
    family = make_family()
    for until in ("2026-11-23", "tomorrow", 5):
        with pytest.raises(FamilyError, match="pause must end"):
            act(family, "set_pause", at(12), childId="emma", paused=True, until=until)
    with pytest.raises(FamilyError):
        act(family, "set_pause", at(12), childId="emma")


# ---- Notifications ---------------------------------------------------------------------


def test_deadline_warning_and_overdue_once() -> None:
    family = make_family(warningMinutes=30)
    family.tick(at(17, 29))
    assert notifications(family, at(17, 29)) == []
    family.tick(at(17, 30))
    family.tick(at(17, 45))
    warning = notifications(family, at(17, 45))
    assert [n["type"] for n in warning] == ["deadlineWarning"]
    assert warning[0]["message"] == "Remember Dishes – due at 18:00"
    assert warning[0]["deadline"] == "2026-11-23T18:00:00.000"

    family.tick(at(18, 1))
    family.tick(at(18, 30))
    overdue = notifications(family, at(18, 30))
    assert [n["type"] for n in overdue] == ["overdue", "deadlineWarning"]  # newest first
    assert overdue[0]["message"] == "Dishes was due at 18:00 – do it now"

    use(family, at(18, 40))
    started = notifications(family, at(18, 40))[0]
    assert started["type"] == "lockStarted" and started["minutes"] == 60
    assert started["endsAt"] == "2026-11-23T19:40:00.000"
    assert started["reason"] == "Missing: Dishes (due 18:00)"
    assert started["message"] == "The tablet is locked for 60 minutes. Missing: Dishes (due 18:00)"
    de = family.notifications_json("emma", at(18, 40), "de")[0]["message"]
    assert de == "Das Tablet ist für 60 Minuten gesperrt. Fehlt: Dishes (fällig 18:00)"


def test_no_warning_for_done_or_optional_tasks() -> None:
    family = make_family()
    add_task(family, "free", "Wash the car", mandatory=False)
    complete(family, at(16, 59))
    family.tick(at(17, 30))
    assert notifications(family, at(17, 30)) == []
    assert [n["type"] for n in notifications(family, at(17, 30), "oscar")] == ["deadlineWarning"]


def test_notifications_are_kept_for_7_days() -> None:
    family = make_family()
    family.tick(at(18, 1))
    # No tick in the warning window: only "overdue" (a warning after the
    # deadline would make no sense).
    assert len(notifications(family, at(18, 1))) == 1
    # Older than 7 days: not shown, and removed by the next tick.
    assert notifications(family, at(18, 2, day=7)) == []
    family.tick(at(18, 2, day=7))
    assert all(
        datetime.fromisoformat(n["at"]) > at(18, 2) for n in family.data["notifications"]
    )


# ---- State and history -----------------------------------------------------------------


def test_state_payload() -> None:
    family = make_family()
    family.tick(at(18, 5))
    tablet = family.state_json("F", at(18, 5), "emma", "da")
    child = tablet["children"][0]
    assert child["lock"]["status"] == "pending"
    assert child["lock"]["reason"] == "Mangler: Dishes (frist 18:00)"
    assert child["paused"] is False and child["pausedUntil"] is None
    assert [n["type"] for n in child["notifications"]] == ["overdue"]
    # Parents get the lock, but not the child's notifications.
    parents = family.state_json("F", at(18, 5))
    assert parents["children"][0]["lock"]["status"] == "pending"
    assert "notifications" not in parents["children"][0]
    assert "lockMinutes" in parents["settings"] and "restrictionStart" not in parents["settings"]


def test_lock_history() -> None:
    family = make_family()
    family.tick(at(18, 5))
    use(family, at(18, 10))
    family.tick(at(19, 11))
    family.cleanup(at(0, 1, day=1))
    family.tick(at(18, 5, day=1))
    act(family, "lift_lock", at(18, 6, day=1), childId="emma")  # lifted while pending

    items = family.history(date(2026, 11, 25), "emma", {"lock"}, "en")["items"]
    assert [(i["lockEvent"], i["at"]) for i in items] == [
        ("lifted", "2026-11-24T18:06:00.000"),
        ("ended", "2026-11-23T19:10:00.000"),
        ("started", "2026-11-23T18:10:00.000"),
    ]
    started = items[-1]
    assert started["type"] == "lock" and started["minutes"] == 60
    assert started["note"] == "Missing: Dishes (due 18:00)"
    assert started["reasons"][0]["taskTitle"] == "Dishes"
    assert started["childName"] == "Emma" and started["amountOre"] == 0
