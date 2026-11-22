"""Familiens handlinger - samme regler og fejlbeskeder som appens TaskRepository."""

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
    act(family, "add_child", id="oskar", name="Oskar")
    act(
        family,
        "create_task",
        id="t1",
        title="Tøm opvaskeren",
        amountOre=500,
        recurrence="daily",
        mandatory=True,
    )
    return family


def test_complete_approve_and_balance(family: Family) -> None:
    completion = act(family, "complete_task", taskId="t1", childId="emma")
    assert completion["status"] == "pending" and completion["late"] is False
    # Kan ikke markeres igen mens den venter.
    with pytest.raises(FamilyError, match="kan ikke markeres udført"):
        act(family, "complete_task", taskId="t1", childId="emma")
    # ... men søskende kan stadig lave den.
    act(family, "complete_task", taskId="t1", childId="oskar")

    act(family, "approve_completion", completionId=completion["id"])
    assert family.balance_ore("emma") == 500
    assert family.earned_this_week_ore("emma", NOW) == 500
    with pytest.raises(FamilyError, match="allerede behandlet"):
        act(family, "reject_completion", completionId=completion["id"])

    act(family, "adjust_balance", childId="emma", amountOre=-200, note="Slik")
    assert family.balance_ore("emma") == 300
    act(family, "mark_paid_out", childId="emma")
    assert family.balance_ore("emma") == 0


def test_late_uses_ha_clock(family: Family) -> None:
    evening = NOW.replace(hour=19)
    # Tablettens eget tidspunkt ignoreres: HA's ur afgør om det er for sent.
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
        title="Fodre katten",
        amountOre=200,
        recurrence="daily",
        assignedChildIds=["oskar"],
        activeWeekdays=[1],
    )
    with pytest.raises(FamilyError, match="ikke tildelt"):
        act(family, "complete_task", taskId="t2", childId="emma")
    tuesday = NOW + timedelta(days=1)
    with pytest.raises(FamilyError, match="kan ikke markeres"):
        act(family, "complete_task", now=tuesday, taskId="t2", childId="oskar")


def test_update_task_keeps_missing_and_clears_null(family: Family) -> None:
    act(
        family,
        "update_task",
        id="t1",
        title="Tøm opvasker",
        amountOre=600,
        recurrence="daily",
        activeWeekdays=[1, 3],
        dueTime="17:30",
    )
    task = family.task("t1")
    assert task["activeWeekdays"] == [1, 3] and task["dueTime"] == "17:30"
    assert task["mandatory"] is True  # mangler i payload -> beholdt

    act(family, "update_task", id="t1", title="Tøm", amountOre=600, recurrence="daily")
    assert family.task("t1")["activeWeekdays"] == [1, 3]  # nøgle mangler -> behold

    act(
        family,
        "update_task",
        id="t1",
        title="Tøm",
        amountOre=600,
        recurrence="daily",
        activeWeekdays=None,
        dueTime=None,
    )
    assert family.task("t1")["activeWeekdays"] is None
    assert family.task("t1")["dueTime"] is None

    with pytest.raises(FamilyError, match="findes ikke"):
        act(family, "update_task", id="nope", title="x", amountOre=1, recurrence="once")


def test_children_and_settings(family: Family) -> None:
    act(family, "rename_child", id="emma", name="Emilie")
    assert family.child("emma")["name"] == "Emilie"
    act(family, "delete_child", id="oskar")
    act(family, "delete_child", id="emma")
    assert family.children == []  # det sidste barn kan også slettes

    act(family, "set_setting", key="latePauseMinutes", value=20)
    assert family.settings["latePauseMinutes"] == 20
    with pytest.raises(FamilyError, match="mellem 0 og 240"):
        act(family, "set_setting", key="latePauseMinutes", value=999)
    with pytest.raises(FamilyError, match="Ukendt handling"):
        act(family, "hack_the_planet")


def test_summary_and_state(family: Family) -> None:
    act(family, "complete_task", taskId="t1", childId="emma")
    evening = NOW.replace(hour=19)
    summary = family.summary("Familien", evening)
    emma, oskar = summary["children"]
    assert emma["restricted"] is False  # har markeret udført
    assert oskar["restricted"] is True
    assert summary["pending"][0]["childName"] == "Emma"
    assert summary["pending"][0]["taskTitle"] == "Tøm opvaskeren"

    state = family.state_json("Familien", evening)
    assert [c["name"] for c in state["children"]] == ["Emma", "Oskar"]
    assert state["familySettings"]["defaultDueTime"] == "18:00"
