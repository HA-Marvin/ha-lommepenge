"""The pure rules: times, settings and the child's scope."""

from __future__ import annotations

from datetime import datetime

from custom_components.lommepenge import logic

SETTINGS = dict(logic.DEFAULT_SETTINGS)
MONDAY = datetime(2026, 11, 23, 12, 0)


def task(**fields):
    return {
        "id": "t1",
        "title": "Empty the dishwasher",
        "amountOre": 500,
        "recurrence": "daily",
        "active": True,
        "mandatory": True,
        "activeWeekdays": None,
        "assignedChildIds": None,
        "dueTime": None,
        **fields,
    }


def test_time_helpers() -> None:
    assert logic.normalize_time("7:5") == "07:05"
    assert logic.normalize_time("24:00") is None
    assert logic.normalize_time(None) is None
    assert logic.normalize_weekdays([3, 1, 1]) == [1, 3]
    assert logic.normalize_weekdays([1, 2, 3, 4, 5, 6, 7]) is None
    assert logic.normalize_child_ids(["a", "a", "b"]) == ["a", "b"]
    assert logic.normalize_child_ids([]) is None
    assert logic.parse_dt("2026-11-23T18:30:00.000") == datetime(2026, 11, 23, 18, 30)


def test_is_late() -> None:
    done = MONDAY.replace(hour=18, minute=30)
    assert logic.is_late(task(), SETTINGS, done) is True
    assert logic.is_late(task(dueTime="19:00"), SETTINGS, done) is False
    assert logic.is_late(task(mandatory=False), SETTINGS, done) is False


def test_restriction_window_is_gone() -> None:
    """Del H4: no 15:00-21:00 window; a lock lasts lockMinutes instead."""
    assert "restrictionStart" not in logic.DEFAULT_SETTINGS
    assert logic.DEFAULT_SETTINGS["lockMinutes"] == 60
    # Old stored values are dropped, not kept.
    settings = logic.settings_from({"restrictionStart": "15:00", "lockMinutes": 30})
    assert settings == {**SETTINGS, "lockMinutes": 30}
    for value in (0, 481):
        try:
            logic.validate_setting("lockMinutes", value)
        except ValueError:
            continue
        raise AssertionError(f"lockMinutes={value} should fail")


def test_settings_validation() -> None:
    assert logic.validate_setting("defaultDueTime", "7:30") == "07:30"
    assert logic.validate_setting("latePauseMinutes", 15) == 15
    for key, value in (("latePauseMinutes", 241), ("winterFromWeek", 0), ("defaultDueTime", "x")):
        try:
            logic.validate_setting(key, value)
        except ValueError:
            continue
        raise AssertionError(f"{key}={value} should fail")
    assert logic.settings_from({"latePauseMinutes": "oops", "warningMinutes": 30}) == {
        **SETTINGS,
        "warningMinutes": 30,
    }


def test_child_scope() -> None:
    assert logic.is_action_allowed_for_child(
        {"type": "complete_task", "payload": {"childId": "emma"}}, "emma"
    )
    assert not logic.is_action_allowed_for_child(
        {"type": "complete_task", "payload": {"childId": "oscar"}}, "emma"
    )
    assert not logic.is_action_allowed_for_child(
        {"type": "approve_completion", "payload": {"childId": "emma"}}, "emma"
    )
    # The tablet reports its own use only.
    assert logic.is_action_allowed_for_child(
        {"type": "report_use", "payload": {"childId": "emma"}}, "emma"
    )
    assert not logic.is_action_allowed_for_child(
        {"type": "report_use", "payload": {"childId": "oscar"}}, "emma"
    )
    assert not logic.is_action_allowed_for_child(
        {"type": "lift_lock", "payload": {"childId": "emma"}}, "emma"
    )
    assert logic.task_applies_to_child({"assignedChildIds": None}, "emma")
    assert not logic.task_applies_to_child({"assignedChildIds": ["oscar"]}, "emma")
