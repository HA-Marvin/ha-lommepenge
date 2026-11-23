"""The child's task list (Del H2): one entry per task, 5 days ahead, the
midnight cleanup, idempotent completion and the history on request."""

from __future__ import annotations

from datetime import date, datetime, timedelta

import pytest

from custom_components.lommepenge import logic
from custom_components.lommepenge.family import Family, FamilyError, migrate_family

MONDAY = datetime(2026, 11, 23, 9, 0)  # created in the morning, before 18:00


def act(family: Family, action_type: str, now: datetime, **payload):
    return family.apply_action({"type": action_type, "payload": payload}, now)


def make_family(**task) -> Family:
    family = Family()
    family.cleanup(MONDAY)  # a new family: starts cleaning from today
    act(family, "add_child", MONDAY - timedelta(days=30), id="emma", name="Emma")
    act(family, "add_child", MONDAY - timedelta(days=30), id="oscar", name="Oscar")
    if task:
        act(
            family,
            "create_task",
            task.pop("created", MONDAY),
            **{"id": "t1", "title": "Dishes", "amountOre": 500, **task},
        )
    return family


def entries(family: Family, now: datetime, child: str = "emma") -> list[dict]:
    return family.task_entries(child, now)


def only(family: Family, now: datetime, child: str = "emma") -> dict:
    result = entries(family, now, child)
    assert len(result) == 1, result
    return result[0]


def complete(family: Family, now: datetime, child: str = "emma", **extra):
    return act(family, "complete_task", now, taskId="t1", childId=child, **extra)


# ---- One entry per task ---------------------------------------------------------


def test_daily_task_one_entry_and_next_occurrence() -> None:
    family = make_family(recurrence="daily", mandatory=True)
    noon = MONDAY.replace(hour=12)
    entry = only(family, noon)
    assert entry["status"] == "available"
    assert entry["date"] == "2026-11-23"
    assert entry["deadline"] == "2026-11-23T18:00:00.000"
    assert entry["amountOre"] == 500 and entry["mandatory"] is True

    completion = complete(family, noon)
    entry = only(family, noon)
    assert entry["status"] == "awaitingApproval"
    assert entry["completionId"] == completion["id"] and entry["late"] is False
    # Siblings are not affected.
    assert only(family, noon, "oscar")["status"] == "available"

    # Approved: the entry moves on to the next normal occurrence.
    act(family, "approve_completion", noon, completionId=completion["id"])
    entry = only(family, noon)
    assert entry["status"] == "upcoming" and entry["date"] == "2026-11-24"
    with pytest.raises(FamilyError, match="cannot be marked"):
        complete(family, noon)


def test_rejected_completion_consumes_the_occurrence() -> None:
    family = make_family(recurrence="daily", mandatory=True)
    noon = MONDAY.replace(hour=12)
    completion = complete(family, noon)
    act(family, "reject_completion", noon, completionId=completion["id"])
    assert only(family, noon)["date"] == "2026-11-24"


def test_rejected_one_off_task_comes_back() -> None:
    family = make_family(recurrence="once")
    noon = MONDAY.replace(hour=12)
    completion = complete(family, noon)
    act(family, "reject_completion", noon, completionId=completion["id"])
    assert only(family, noon)["status"] == "available"
    completion = complete(family, noon)
    act(family, "approve_completion", noon, completionId=completion["id"])
    assert entries(family, noon) == []  # done for good


def test_five_day_horizon_and_other_weekdays() -> None:
    # Mondays only.
    family = make_family(recurrence="daily", activeWeekdays=[1])
    tuesday = MONDAY + timedelta(days=1)
    assert entries(family, tuesday) == []  # next Monday is 6 days away
    thursday = MONDAY + timedelta(days=3)
    entry = only(family, thursday)  # Monday is the 5th day (today + 4)
    assert entry["status"] == "upcoming" and entry["date"] == "2026-11-30"
    assert entry["deadline"] is None  # optional task
    # Not yet: only today's (or an overdue) occurrence can be marked as done.
    with pytest.raises(FamilyError, match="cannot be marked"):
        complete(family, thursday)
    assert entries(family, MONDAY + timedelta(days=2)) == []  # Monday is today + 5


def test_weekly_is_seven_rolling_days_after_completion() -> None:
    family = make_family(recurrence="weekly", mandatory=True)
    noon = MONDAY.replace(hour=12)
    completion = complete(family, noon)
    tuesday = noon + timedelta(days=1)
    act(family, "approve_completion", tuesday, completionId=completion["id"])
    assert entries(family, tuesday) == []
    entry = only(family, MONDAY + timedelta(days=3))  # Thursday: Monday is within 5 days
    assert entry["date"] == "2026-11-30" and entry["status"] == "upcoming"


def test_new_task_after_the_deadline_starts_tomorrow() -> None:
    evening = MONDAY.replace(hour=20)
    family = make_family(recurrence="daily", mandatory=True, created=evening)
    entry = only(family, evening)
    assert entry["date"] == "2026-11-24" and entry["status"] == "upcoming"


def test_one_off_task_can_be_done_before_its_day() -> None:
    evening = MONDAY.replace(hour=20)
    family = make_family(recurrence="once", mandatory=True, created=evening)
    entry = only(family, evening)
    # The first deadline after it was created is tomorrow, but it can be done now.
    assert entry["deadline"] == "2026-11-24T18:00:00.000"
    assert entry["status"] == "available"
    assert complete(family, evening)["late"] is False


def test_overdue_and_late_completion() -> None:
    family = make_family(recurrence="daily", mandatory=True, dueTime="17:00")
    evening = MONDAY.replace(hour=19)
    assert only(family, evening)["status"] == "overdue"
    completion = complete(family, evening)
    assert completion["late"] is True
    assert completion["occurrenceDate"] == "2026-11-23"
    assert only(family, evening)["late"] is True


def test_unlimited_and_optional_tasks() -> None:
    family = make_family(recurrence="unlimited", mandatory=True)
    noon = MONDAY.replace(hour=12)
    completion = complete(family, noon)
    act(family, "approve_completion", noon, completionId=completion["id"])
    entry = only(family, noon.replace(hour=19))
    # Still available, but today's duty is done: no deadline, not overdue.
    assert entry["status"] == "available" and entry["deadline"] is None
    assert only(family, noon + timedelta(days=1))["deadline"] == "2026-11-24T18:00:00.000"

    optional = make_family(recurrence="daily")
    assert only(optional, MONDAY.replace(hour=23))["status"] == "available"


def test_assigned_and_entries_are_sorted() -> None:
    family = make_family(recurrence="daily", mandatory=True)
    act(family, "create_task", MONDAY, id="t2", title="Bed", amountOre=100,
        recurrence="daily", assignedChildIds=["oscar"])
    act(family, "create_task", MONDAY, id="t3", title="Apple", amountOre=100, recurrence="daily")
    noon = MONDAY.replace(hour=12)
    assert [e["taskId"] for e in entries(family, noon)] == ["t1", "t3"]
    assert [e["taskId"] for e in entries(family, noon, "oscar")] == ["t1", "t3", "t2"]


# ---- Idempotent actions ----------------------------------------------------------


def test_complete_task_with_the_same_id_is_idempotent() -> None:
    family = make_family(recurrence="daily")
    noon = MONDAY.replace(hour=12)
    first = complete(family, noon, completionId="app-1")
    assert complete(family, noon, completionId="app-1") is first
    act(family, "approve_completion", noon, completionId="app-1")
    # Even after approval a retry is a success and creates nothing.
    assert complete(family, noon, completionId="app-1") is first
    assert len(family.data["completions"]) == 1
    # Approving again (retry / the other parent) is fine; rejecting is not.
    act(family, "approve_completion", noon, completionId="app-1")
    with pytest.raises(FamilyError, match="already been handled"):
        act(family, "reject_completion", noon, completionId="app-1")
    with pytest.raises(FamilyError):
        complete(family, noon, completionId="x" * 101)


# ---- Midnight cleanup --------------------------------------------------------------


def test_cleanup_drops_late_occurrences_without_money() -> None:
    family = make_family(recurrence="daily", mandatory=True)
    tuesday = MONDAY + timedelta(days=1, hours=-9)  # 00:00
    records = family.cleanup(tuesday)
    assert {(r["childId"], r["date"]) for r in records} == {
        ("emma", "2026-11-23"),
        ("oscar", "2026-11-23"),
    }
    assert family.balance_ore("emma") == 0
    entry = only(family, tuesday)
    assert entry["date"] == "2026-11-24" and entry["status"] == "available"
    # Calling again the same day does nothing.
    assert family.cleanup(tuesday.replace(hour=12)) == []


def test_cleanup_keeps_done_and_pending_occurrences() -> None:
    family = make_family(recurrence="daily", mandatory=True)
    evening = MONDAY.replace(hour=19)
    completion = complete(family, evening)  # late, but done before midnight
    records = family.cleanup(MONDAY + timedelta(days=1))
    assert [r["childId"] for r in records] == ["oscar"]
    act(family, "approve_completion", MONDAY + timedelta(days=1), completionId=completion["id"])
    assert family.balance_ore("emma") == 500


def test_missed_one_off_task_is_gone_for_good() -> None:
    family = make_family(recurrence="once", mandatory=True)
    family.cleanup(MONDAY + timedelta(days=1))
    assert family.task("t1")["active"] is False
    assert entries(family, MONDAY + timedelta(days=1)) == []
    assert len(family.data["missed"]) == 2  # both children missed it


def test_missed_weekly_task_counts_from_the_missed_deadline() -> None:
    family = make_family(recurrence="weekly", mandatory=True)
    family.cleanup(MONDAY + timedelta(days=1))
    entry = only(family, MONDAY + timedelta(days=3))
    assert entry["date"] == "2026-11-30" and entry["status"] == "upcoming"


def test_cleanup_catches_up_after_downtime() -> None:
    family = make_family(recurrence="daily", mandatory=True, assignedChildIds=["emma"])
    act(family, "create_task", MONDAY, id="w", title="Weekly", amountOre=100,
        recurrence="weekly", mandatory=True, assignedChildIds=["emma"])
    # HA was down from Monday until Tuesday the week after (9 days).
    records = family.cleanup(MONDAY + timedelta(days=9))
    daily = sorted(r["date"] for r in records if r["taskId"] == "t1")
    assert daily == [f"2026-11-{d}" for d in range(23, 31)] + ["2026-12-01"]
    weekly = sorted(r["date"] for r in records if r["taskId"] == "w")
    assert weekly == ["2026-11-23", "2026-11-30"]
    assert only(family, MONDAY + timedelta(days=9, hours=3))["taskId"] == "t1"


# ---- History -------------------------------------------------------------------------


def test_history_pages_and_filters() -> None:
    family = make_family(recurrence="daily")
    old = MONDAY - timedelta(days=40)
    act(family, "adjust_balance", old, id="a-old", childId="emma", amountOre=100, note="Gift")
    noon = MONDAY.replace(hour=12)
    first = complete(family, noon, completionId="c1")
    act(family, "approve_completion", noon, completionId="c1")
    later = noon + timedelta(minutes=1)
    complete(family, later, child="oscar", completionId="c2")
    act(family, "reject_completion", later, completionId="c2")
    complete(family, noon + timedelta(days=1), completionId="c3")  # pending: not history

    page = family.history(date(2026, 11, 24))
    assert page["from"] == "2026-10-25" and page["before"] == "2026-11-24"
    # Newest first.
    assert [(i["type"], i["childName"]) for i in page["items"]] == [
        ("rejected", "Oscar"),
        ("approved", "Emma"),
    ]
    approved = next(i for i in page["items"] if i["type"] == "approved")
    assert approved["taskTitle"] == "Dishes" and approved["amountOre"] == 500
    assert approved["completedAt"] == first["completedAt"]
    assert page["nextBefore"] == "2026-10-25"

    older = family.history(date(2026, 10, 25))
    assert [i["id"] for i in older["items"]] == ["a-old"]
    assert older["items"][0]["note"] == "Gift"
    assert older["nextBefore"] is None

    emma = family.history(date(2026, 11, 24), child_id="emma")
    assert [i["id"] for i in emma["items"]] == ["c1"]
    assert family.history(date(2026, 11, 24), types={"rejected"})["items"][0]["id"] == "c2"


def test_missed_occurrences_are_in_the_history() -> None:
    family = make_family(recurrence="daily", mandatory=True, assignedChildIds=["emma"])
    family.cleanup(MONDAY + timedelta(days=1))
    item = family.history(date(2026, 11, 24))["items"][0]
    assert item["type"] == "missed" and item["taskTitle"] == "Dishes"
    assert item["at"] == "2026-11-23T18:00:00.000"


# ---- Storage migration ----------------------------------------------------------------


def test_migration_of_old_data() -> None:
    old = {
        "children": [{"id": "emma", "name": "Emma", "sortOrder": 0,
                      "createdAt": "2026-01-01T10:00:00.000"}],
        "tasks": [{"id": "t1", "title": "Old one-off", "amountOre": 100, "recurrence": "once",
                   "mandatory": True, "createdAt": "2026-10-01T10:00:00.000", "active": True}],
        "completions": [{"id": "c1", "taskId": "x", "childId": "emma",
                         "completedAt": "2026-11-20T10:00:00.000", "status": "approved",
                         "approvedAt": None, "amountAtCompletionOre": 100, "late": False}],
        "balanceAdjustments": [],
        "paidOutOreByChild": {},
        "familySettings": {},
        "restrictionSuspensions": {},
    }
    migrate_family(old, MONDAY)
    assert old["completions"][0]["occurrenceDate"] == "2026-11-20"
    assert old["cleanedThrough"] == "2026-11-22" and old["missed"] == []
    family = Family(old)
    # The one-off task from before the upgrade is not counted as missed for
    # its old deadline - it is due at the first deadline after the upgrade.
    assert family.cleanup(MONDAY) == []
    assert only(family, MONDAY)["deadline"] == "2026-11-23T18:00:00.000"


def test_next_occurrence_without_active_weekday_in_reach() -> None:
    task = {"id": "t", "recurrence": "daily", "activeWeekdays": [8], "mandatory": False}
    assert logic.next_occurrence(task, [], set(), logic.DEFAULT_SETTINGS, MONDAY, MONDAY) is None
