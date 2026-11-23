"""The family's actions - the same rules and error messages as the app's TaskRepository."""

from __future__ import annotations

from datetime import datetime, timedelta

import pytest

from custom_components.lommepenge.family import Family, FamilyError

NOW = datetime(2026, 11, 23, 16, 0)


def act(family: Family, action_type: str, now: datetime = NOW, **payload):
    return family.apply_action({"type": action_type, "payload": payload}, now)


@pytest.fixture
def family() -> Family:
    family = Family()
    act(family, "add_child", id="emma", name="Emma")
    act(family, "add_child", id="oscar", name="Oscar")
    act(
        family,
        "create_task",
        id="t1",
        title="Empty the dishwasher",
        amountOre=500,
        recurrence="daily",
        mandatory=True,
    )
    return family


def test_complete_approve_and_balance(family: Family) -> None:
    completion = act(family, "complete_task", taskId="t1", childId="emma")
    assert completion["status"] == "pending" and completion["late"] is False
    # Cannot be marked again while it is waiting.
    with pytest.raises(FamilyError, match="cannot be marked as done"):
        act(family, "complete_task", taskId="t1", childId="emma")
    # ... but siblings can still do it.
    act(family, "complete_task", taskId="t1", childId="oscar")

    act(family, "approve_completion", completionId=completion["id"])
    assert family.balance_ore("emma") == 500
    assert family.earned_this_week_ore("emma", NOW) == 500
    with pytest.raises(FamilyError, match="already been handled"):
        act(family, "reject_completion", completionId=completion["id"])

    act(family, "adjust_balance", childId="emma", amountOre=-200, note="Sweets")
    assert family.balance_ore("emma") == 300
    act(family, "mark_paid_out", childId="emma")
    assert family.balance_ore("emma") == 0


def test_late_uses_ha_clock(family: Family) -> None:
    evening = NOW.replace(hour=19)
    # The tablet's own time is ignored: HA's clock decides whether it is late.
    completion = act(
        family,
        "complete_task",
        now=evening,
        taskId="t1",
        childId="emma",
        completedAt="2026-11-23T10:00:00.000",
    )
    assert completion["late"] is True
    assert completion["completedAt"].startswith("2026-11-23T19:00")


def test_repeated_offline_action_is_idempotent(family: Family) -> None:
    first = act(family, "complete_task", taskId="t1", childId="emma", completionId="c-1")
    again = act(family, "complete_task", taskId="t1", childId="emma", completionId="c-1")
    assert first is again
    assert len(family.data["completions"]) == 1


def test_assignment_and_weekdays(family: Family) -> None:
    act(
        family,
        "create_task",
        id="t2",
        title="Feed the cat",
        amountOre=200,
        recurrence="daily",
        assignedChildIds=["oscar"],
        activeWeekdays=[1],
    )
    with pytest.raises(FamilyError, match="not assigned"):
        act(family, "complete_task", taskId="t2", childId="emma")
    tuesday = NOW + timedelta(days=1)
    with pytest.raises(FamilyError, match="cannot be marked"):
        act(family, "complete_task", now=tuesday, taskId="t2", childId="oscar")


def test_update_task_keeps_missing_and_clears_null(family: Family) -> None:
    act(
        family,
        "update_task",
        id="t1",
        title="Empty dishwasher",
        amountOre=600,
        recurrence="daily",
        activeWeekdays=[1, 3],
        dueTime="17:30",
    )
    task = family.task("t1")
    assert task["activeWeekdays"] == [1, 3] and task["dueTime"] == "17:30"
    assert task["mandatory"] is True  # missing in payload -> kept

    act(family, "update_task", id="t1", title="Empty", amountOre=600, recurrence="daily")
    assert family.task("t1")["activeWeekdays"] == [1, 3]  # key missing -> keep

    act(
        family,
        "update_task",
        id="t1",
        title="Empty",
        amountOre=600,
        recurrence="daily",
        activeWeekdays=None,
        dueTime=None,
    )
    assert family.task("t1")["activeWeekdays"] is None
    assert family.task("t1")["dueTime"] is None

    with pytest.raises(FamilyError, match="no longer exists"):
        act(family, "update_task", id="nope", title="x", amountOre=1, recurrence="once")


def test_children_and_settings(family: Family) -> None:
    act(family, "rename_child", id="emma", name="Emily")
    assert family.child("emma")["name"] == "Emily"
    act(family, "delete_child", id="oscar")
    act(family, "delete_child", id="emma")
    assert family.children == []  # the last child can be deleted too

    act(family, "set_setting", key="latePauseMinutes", value=20)
    assert family.settings["latePauseMinutes"] == 20
    with pytest.raises(FamilyError, match="between 0 and 240"):
        act(family, "set_setting", key="latePauseMinutes", value=999)
    with pytest.raises(FamilyError, match="Unknown action"):
        act(family, "hack_the_planet")


def test_errors_are_translated(family: Family) -> None:
    with pytest.raises(FamilyError) as err:
        act(family, "set_setting", key="latePauseMinutes", value=999)
    assert err.value.translate("da") == "latePauseMinutes skal være mellem 0 og 240: 999"
    assert err.value.translate("de").startswith("latePauseMinutes muss zwischen 0 und 240")
    # Unknown language -> English.
    assert err.value.translate("xx") == str(err.value)


def test_summary_and_state(family: Family) -> None:
    act(family, "complete_task", taskId="t1", childId="emma")
    evening = NOW.replace(hour=19)
    summary = family.summary("The Family", evening)
    emma, oscar = summary["children"]
    assert emma["restricted"] is False  # has marked it as done
    assert oscar["restricted"] is True
    assert oscar["reason"] == "Missing: Empty the dishwasher (due 18:00)"
    pending = summary["pending"][0]
    assert pending["childName"] == "Emma"
    assert pending["taskTitle"] == "Empty the dishwasher"

    assert pending["message"] == 'Emma did "Empty the dishwasher" – 5 DKK'

    danish = family.summary("The Family", evening, "da", "kr")
    assert danish["children"][1]["reason"] == "Mangler: Empty the dishwasher (frist 18:00)"
    assert danish["pending"][0]["message"] == 'Emma har lavet "Empty the dishwasher" – 5 kr'

    state = family.state_json("The Family", evening)
    assert [c["name"] for c in state["children"]] == ["Emma", "Oscar"]
    assert state["settings"]["defaultDueTime"] == "18:00"
