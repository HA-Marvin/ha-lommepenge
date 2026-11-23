"""The family's rules: occurrences, deadlines, settings and the child's scope.

Pure functions without I/O. Originally a translation of the app's
`logic/recurrence.dart` and `logic/child_scope.dart`; since Del H only HA
calculates and the app just shows HA's results. The locks (Del H4) live in
`family.py`, because they need the family's stored state. All times are
naive, local `datetime`s (HA's local time).
"""

from __future__ import annotations

from datetime import date, datetime, timedelta
from typing import Any

from .i18n import LocalizedError

AVAILABLE = "available"

RECURRENCES = ("once", "daily", "weekly", "unlimited")


class InvalidSetting(LocalizedError, ValueError):
    """A family setting with an unknown key or an invalid value."""


# ---- Times ------------------------------------------------------------------


def minutes_of_day(value: Any) -> int | None:
    """`"HH:MM"` -> minutes after midnight, or `None` if invalid."""
    if not isinstance(value, str):
        return None
    parts = value.strip().split(":")
    if len(parts) != 2:
        return None
    try:
        hours, minutes = int(parts[0]), int(parts[1])
    except ValueError:
        return None
    if not (0 <= hours <= 23 and 0 <= minutes <= 59):
        return None
    return hours * 60 + minutes


def normalize_time(value: Any) -> str | None:
    """Normalizes a time of day to `"HH:MM"`, or `None`."""
    minutes = minutes_of_day(value)
    if minutes is None:
        return None
    return f"{minutes // 60:02d}:{minutes % 60:02d}"


def parse_dt(value: str) -> datetime:
    """ISO time from the app -> naive local time."""
    parsed = datetime.fromisoformat(value)
    if parsed.tzinfo is not None:
        parsed = parsed.astimezone().replace(tzinfo=None)
    return parsed


def to_iso(value: datetime) -> str:
    """Naive local time -> ISO string the app's `DateTime.parse` understands."""
    return value.isoformat(timespec="milliseconds")


def date_key(value: datetime | date) -> str:
    """`YYYY-MM-DD`."""
    return f"{value.year:04d}-{value.month:02d}-{value.day:02d}"


def _at_time(day: datetime, hhmm: str) -> datetime:
    minutes = minutes_of_day(hhmm) or 0
    return datetime(day.year, day.month, day.day, minutes // 60, minutes % 60)


# ---- Tasks ------------------------------------------------------------------


def normalize_weekdays(weekdays: Any) -> list[int] | None:
    """Weekdays 1-7; an empty list or all 7 means "every day" (`None`)."""
    if not weekdays:
        return None
    unique = sorted({int(d) for d in weekdays if 1 <= int(d) <= 7})
    if not unique or len(unique) >= 7:
        return None
    return unique


def normalize_child_ids(child_ids: Any) -> list[str] | None:
    """An empty list means "all children" (`None`); duplicates are removed."""
    if not child_ids:
        return None
    unique: list[str] = []
    for child_id in child_ids:
        if isinstance(child_id, str) and child_id not in unique:
            unique.append(child_id)
    return unique or None


def is_active_on(task: dict[str, Any], day: datetime) -> bool:
    weekdays = task.get("activeWeekdays")
    if not weekdays:
        return True
    return day.isoweekday() in weekdays


# ---- The child's task list (Del H2) -----------------------------------------------
#
# Every task gives the child ONE entry: its next occurrence (a day) and that
# day's deadline. The app shows the entries as they are and calculates nothing.
#
# - A pending completion is the entry ("awaitingApproval") until a parent
#   handles it.
# - An approved or rejected completion consumes its occurrence, and the next
#   normal occurrence comes forward. Exception: a rejected one-off task has no
#   next occurrence, so it simply becomes available again.
# - Missed occurrences (late and not done at midnight, see `Family.cleanup`)
#   are consumed as well. A missed one-off task is deactivated for good.
# - Weekly = 7 rolling days after the last handled completion (its
#   `completedAt` day), or after a missed occurrence's day.
# - An occurrence whose deadline passed before the task existed (or before
#   the child was added) is skipped, so a new task is never overdue at once.

AWAITING_APPROVAL = "awaitingApproval"
OVERDUE = "overdue"
UPCOMING = "upcoming"

# Entries are shown for today and the next 4 days (5 calendar days).
VIEW_DAYS = 5
# How far ahead to look for a day the task is active on (weekdays repeat).
_SEARCH_DAYS = 14


def completion_day(completion: dict[str, Any]) -> date:
    """The occurrence (day) a completion belongs to. Completions from before
    0.5 have no `occurrenceDate`; their completion day is used."""
    value = completion.get("occurrenceDate")
    if isinstance(value, str):
        try:
            return date.fromisoformat(value)
        except ValueError:
            pass
    return parse_dt(completion["completedAt"]).date()


def _due_on(task: dict[str, Any], settings: dict[str, Any], day: date) -> datetime | None:
    return effective_due(task, settings, datetime(day.year, day.month, day.day))


def next_occurrence(
    task: dict[str, Any],
    completions: list[dict[str, Any]],
    missed_days: set[date],
    settings: dict[str, Any],
    now: datetime,
    since: datetime,
) -> dict[str, Any] | None:
    """The child's next occurrence of `task`, without the 5-day limit.

    `completions` are this child's completions of this task, `missed_days` the
    days of this child's missed occurrences of it, and `since` when the task
    started to apply to the child. Returns `None` when there is no further
    occurrence (a one-off task that is done, or no active weekday). The result
    has `date`, `deadline` (`None` for optional tasks), `status` and
    `completion` (the pending one, if any).
    """
    today = now.date()
    pending = [c for c in completions if c["status"] == "pending"]
    if pending:
        day = completion_day(pending[0])
        return {
            "date": day,
            "deadline": _due_on(task, settings, day),
            "status": AWAITING_APPROVAL,
            "completion": pending[0],
        }

    handled = [c for c in completions if c["status"] in ("approved", "rejected")]
    recurrence = task.get("recurrence", "once")

    if recurrence == "once":
        if any(c["status"] == "approved" for c in handled):
            return None
        if not task.get("mandatory"):
            return _occurrence(max(today, since.date()), None, now, completable_early=True)
        # The first deadline after the task was created; it can be done before.
        day = since.date()
        if _due_on(task, settings, day) <= since:
            day += timedelta(days=1)
        return _occurrence(day, _due_on(task, settings, day), now, completable_early=True)

    if recurrence == "unlimited":
        # Always available. A mandatory one is due each day until it has been
        # done (pending or approved) that day.
        done = today in missed_days or any(
            c["status"] == "approved" and completion_day(c) == today for c in handled
        )
        due = _due_on(task, settings, today)
        if done or due is None or due <= since:
            due = None
        return _occurrence(today, due, now)

    consumed = set(missed_days)
    if recurrence == "weekly":
        start = since.date()
        for completion in handled:
            start = max(start, parse_dt(completion["completedAt"]).date() + timedelta(days=7))
        for day in missed_days:
            start = max(start, day + timedelta(days=7))
        if not task.get("mandatory"):
            start = max(start, today)  # an optional task is never overdue
    else:  # daily
        consumed |= {completion_day(c) for c in handled}
        start = max(today, since.date())

    for offset in range(_SEARCH_DAYS):
        day = start + timedelta(days=offset)
        if day in consumed or not is_active_on(task, datetime(day.year, day.month, day.day)):
            continue
        due = _due_on(task, settings, day)
        if due is not None and due <= since:
            continue
        return _occurrence(day, due, now)
    return None


def _occurrence(
    day: date, deadline: datetime | None, now: datetime, completable_early: bool = False
) -> dict[str, Any]:
    if deadline is not None and now > deadline:
        status = OVERDUE
    elif day > now.date() and not completable_early:
        status = UPCOMING
    else:
        status = AVAILABLE
    return {"date": day, "deadline": deadline, "status": status, "completion": None}


def in_view(occurrence: dict[str, Any] | None, now: datetime) -> bool:
    """Whether the entry is shown: within the 5-day horizon."""
    return occurrence is not None and occurrence["date"] < now.date() + timedelta(days=VIEW_DAYS)


# ---- Deadlines -----------------------------------------------------------------


def effective_due(
    task: dict[str, Any], settings: dict[str, Any], day: datetime
) -> datetime | None:
    """The deadline on the day, or `None` for optional tasks."""
    if not task.get("mandatory"):
        return None
    return _at_time(day, task.get("dueTime") or settings["defaultDueTime"])


def is_late(task: dict[str, Any], settings: dict[str, Any], completed_at: datetime) -> bool:
    due = effective_due(task, settings, completed_at)
    return due is not None and completed_at > due


# ---- The family's settings ----------------------------------------------------

DEFAULT_SETTINGS: dict[str, Any] = {
    "defaultDueTime": "18:00",
    # How long a lock runs once the child uses the tablet (Del H4).
    "lockMinutes": 60,
    "latePauseMinutes": 10,
    "warningMinutes": 60,
    "winterFromWeek": 43,
    "winterToWeek": 13,
}

_TIME_SETTINGS = {"defaultDueTime"}
# Settings that existed before; stored values are dropped (Del H removed the
# 15:00-21:00 restriction window).
REMOVED_SETTINGS = ("restrictionStart", "restrictionEnd")
_INT_SETTINGS = {
    "lockMinutes": (1, 480),
    "latePauseMinutes": (0, 240),
    "warningMinutes": (0, 600),
    "winterFromWeek": (1, 53),
    "winterToWeek": (1, 53),
}


def validate_setting(key: str, value: Any) -> Any:
    """A valid value for one setting, otherwise `InvalidSetting` (like the app)."""
    if key in _TIME_SETTINGS:
        normalized = normalize_time(None if value is None else str(value))
        if normalized is None:
            raise InvalidSetting("invalid_time", key=key, value=value)
        return normalized
    if key in _INT_SETTINGS:
        minimum, maximum = _INT_SETTINGS[key]
        try:
            number = int(value)
        except (TypeError, ValueError):
            number = None
        if number is None or isinstance(value, bool) or not minimum <= number <= maximum:
            raise InvalidSetting(
                "setting_out_of_range", key=key, minimum=minimum, maximum=maximum, value=value
            )
        return number
    raise InvalidSetting("unknown_setting", key=key)


def settings_from(raw: Any) -> dict[str, Any]:
    """Settings read defensively: invalid values -> default."""
    settings = dict(DEFAULT_SETTINGS)
    if isinstance(raw, dict):
        for key in DEFAULT_SETTINGS:
            if key in raw:
                try:
                    settings[key] = validate_setting(key, raw[key])
                except ValueError:
                    pass
    return settings


# ---- The child's tablet -------------------------------------------------------

# Actions a child's tablet may send. Everything else requires a parent device.
# `report_use` (the tablet is being used, Del H4) only comes from a tablet.
CHILD_ALLOWED_ACTIONS = frozenset({"complete_task", "report_use"})
CHILD_ONLY_ACTIONS = frozenset({"report_use"})


def is_action_allowed_for_child(action: dict[str, Any], child_id: str) -> bool:
    if action.get("type") not in CHILD_ALLOWED_ACTIONS:
        return False
    payload = action.get("payload")
    return isinstance(payload, dict) and payload.get("childId") == child_id


def task_applies_to_child(task: dict[str, Any], child_id: str) -> bool:
    assigned = task.get("assignedChildIds")
    return not assigned or child_id in assigned
