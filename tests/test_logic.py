"""The rules - the same expectations as the app's follow_up_test/task_balance_test."""

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


def completion(status: str, at: datetime, **fields):
    return {
        "id": f"c-{status}-{at:%d%H%M}",
        "taskId": "t1",
        "childId": "emma",
        "completedAt": logic.to_iso(at),
        "status": status,
        "amountAtCompletionOre": 500,
        "late": False,
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


def test_availability_rules() -> None:
    daily = task()
    assert logic.compute_availability(daily, [], MONDAY) == logic.AVAILABLE
    assert (
        logic.compute_availability(daily, [completion("pending", MONDAY)], MONDAY)
        == logic.PENDING_APPROVAL
    )
    approved_today = [completion("approved", MONDAY.replace(hour=8))]
    assert logic.compute_availability(daily, approved_today, MONDAY) == logic.DONE_TODAY
    # A rejected completion does not block.
    rejected = [completion("rejected", MONDAY.replace(hour=8))]
    assert logic.compute_availability(daily, rejected, MONDAY) == logic.AVAILABLE

    once = task(recurrence="once")
    assert logic.compute_availability(once, approved_today, MONDAY) == logic.COMPLETED_ONCE

    weekly = task(recurrence="weekly")
    four_days_ago = [completion("approved", datetime(2026, 11, 19, 9, 0))]
    assert logic.compute_availability(weekly, four_days_ago, MONDAY) == logic.DONE_THIS_WEEK

    tuesdays = task(activeWeekdays=[2])
    assert logic.compute_availability(tuesdays, [], MONDAY) == logic.NOT_SCHEDULED_TODAY

    unlimited = task(recurrence="unlimited")
    assert logic.compute_availability(unlimited, approved_today, MONDAY) == logic.AVAILABLE


def test_follow_up_overdue_and_restricted() -> None:
    evening = MONDAY.replace(hour=19)
    result = logic.compute_follow_up([task()], [], SETTINGS, evening, None)
    assert result["restricted"] is True
    assert result["overdue"] == [{"taskId": "t1", "title": "Empty the dishwasher", "due": "18:00"}]
    assert result["reason"] == "Missing: Empty the dishwasher (due 18:00)"

    # Before the deadline: on the list, but not restricted.
    afternoon = MONDAY.replace(hour=16)
    result = logic.compute_follow_up([task()], [], SETTINGS, afternoon, None)
    assert result["restricted"] is False
    assert result["dueToday"][0]["due"] == "18:00"

    # Marked as done (awaiting approval): the restriction is lifted.
    pending = [completion("pending", evening)]
    result = logic.compute_follow_up([task()], pending, SETTINGS, evening, None)
    assert result["overdue"] == []

    # Optional tasks are not followed up.
    result = logic.compute_follow_up([task(mandatory=False)], [], SETTINGS, evening, None)
    assert result["overdue"] == []


def test_follow_up_reason_in_each_language() -> None:
    evening = MONDAY.replace(hour=19)
    reasons = {
        language: logic.compute_follow_up([task()], [], SETTINGS, evening, None, language)[
            "reason"
        ]
        for language in ("en", "da", "de", "es", "fr")
    }
    assert reasons == {
        "en": "Missing: Empty the dishwasher (due 18:00)",
        "da": "Mangler: Empty the dishwasher (frist 18:00)",
        "de": "Fehlt: Empty the dishwasher (fällig 18:00)",
        "es": "Falta: Empty the dishwasher (límite 18:00)",
        "fr": "Manquant : Empty the dishwasher (échéance 18:00)",
    }


def test_follow_up_window_and_suspension() -> None:
    late_night = MONDAY.replace(hour=22)
    result = logic.compute_follow_up([task()], [], SETTINGS, late_night, None)
    assert result["overdue"] and result["inWindow"] is False and result["restricted"] is False

    evening = MONDAY.replace(hour=19)
    result = logic.compute_follow_up([task()], [], SETTINGS, evening, "2026-11-23")
    assert result["suspended"] is True and result["restricted"] is False
    # A suspension from yesterday does not apply today.
    result = logic.compute_follow_up([task()], [], SETTINGS, evening, "2026-11-22")
    assert result["restricted"] is True


def test_late_completion_gives_pause() -> None:
    done = MONDAY.replace(hour=18, minute=30)
    late = [completion("pending", done, late=True)]
    result = logic.compute_follow_up([task()], late, SETTINGS, done.replace(minute=35), None)
    assert result["restricted"] is True
    assert result["reason"] == "The task was done late - unlocks at 18:40"

    result = logic.compute_follow_up([task()], late, SETTINGS, done.replace(minute=41), None)
    assert result["restricted"] is False
    assert logic.is_late(task(), SETTINGS, done) is True
    assert logic.is_late(task(dueTime="19:00"), SETTINGS, done) is False


def test_window_over_midnight() -> None:
    settings = {**SETTINGS, "restrictionStart": "22:00", "restrictionEnd": "02:00"}
    assert logic.in_restriction_window(settings, MONDAY.replace(hour=23))
    assert logic.in_restriction_window(settings, MONDAY.replace(hour=1))
    assert not logic.in_restriction_window(settings, MONDAY.replace(hour=12))


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
    assert logic.task_applies_to_child({"assignedChildIds": None}, "emma")
    assert not logic.task_applies_to_child({"assignedChildIds": ["oscar"]}, "emma")
