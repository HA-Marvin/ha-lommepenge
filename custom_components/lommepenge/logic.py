"""The family's rules: availability, deadlines, restriction and child filtering.

Pure functions without I/O - a direct translation of the app's
`logic/recurrence.dart`, `logic/follow_up.dart` and `logic/child_scope.dart`,
so HA (the server) and the app (which displays the data) calculate exactly
the same. All times are naive, local `datetime`s just like the app's
`DateTime.now()`.
"""

from __future__ import annotations

from datetime import date, datetime, timedelta
from typing import Any

from .i18n import LocalizedError, translate

AVAILABLE = "available"
PENDING_APPROVAL = "pendingApproval"
DONE_TODAY = "doneToday"
DONE_THIS_WEEK = "doneThisWeek"
COMPLETED_ONCE = "completedOnce"
NOT_SCHEDULED_TODAY = "notScheduledToday"

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


def compute_availability(
    task: dict[str, Any], completions: list[dict[str, Any]], now: datetime
) -> str:
    """Whether the child can mark the task as done now (this child's completions only)."""
    if any(c["status"] == "pending" for c in completions):
        return PENDING_APPROVAL
    recurrence = task.get("recurrence", "once")
    if recurrence != "once" and not is_active_on(task, now):
        return NOT_SCHEDULED_TODAY

    approved = sorted(
        (c for c in completions if c["status"] == "approved"),
        key=lambda c: parse_dt(c["completedAt"]),
        reverse=True,
    )
    if not approved:
        return AVAILABLE
    last = parse_dt(approved[0]["completedAt"]).date()

    if recurrence == "once":
        return COMPLETED_ONCE
    if recurrence == "daily":
        return DONE_TODAY if last == now.date() else AVAILABLE
    if recurrence == "weekly":
        return DONE_THIS_WEEK if (now.date() - last).days < 7 else AVAILABLE
    return AVAILABLE


# ---- Follow-up ----------------------------------------------------------------


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


def in_restriction_window(settings: dict[str, Any], now: datetime) -> bool:
    """Whether `now` is in the restriction window; windows across midnight work."""
    start = minutes_of_day(settings["restrictionStart"]) or 0
    end = minutes_of_day(settings["restrictionEnd"]) or 0
    current = now.hour * 60 + now.minute
    if start == end:
        return False
    if start < end:
        return start <= current < end
    return current >= start or current < end


def _due_json(task: dict[str, Any], due: datetime) -> dict[str, Any]:
    return {"taskId": task["id"], "title": task["title"], "due": f"{due:%H:%M}"}


def compute_follow_up(
    tasks: list[dict[str, Any]],
    completions: list[dict[str, Any]],
    settings: dict[str, Any],
    now: datetime,
    suspended_on: str | None,
    language: str | None = None,
) -> dict[str, Any]:
    """Follow-up for one child.

    `tasks` are the active tasks that apply to the child, `completions` the
    child's own (all tasks). `reason` is written in `language`.
    """
    due_today: list[tuple[datetime, dict[str, Any]]] = []
    overdue: list[tuple[datetime, dict[str, Any]]] = []

    for task in tasks:
        if not task.get("active", True) or not task.get("mandatory"):
            continue
        if task.get("recurrence") != "once" and not is_active_on(task, now):
            continue
        for_task = [c for c in completions if c["taskId"] == task["id"]]
        if compute_availability(task, for_task, now) != AVAILABLE:
            continue  # awaiting approval, already done, or not today
        # 'unlimited' tasks are always available - an approved completion
        # today still counts as today's duty being done.
        if any(
            c["status"] == "approved" and parse_dt(c["completedAt"]).date() == now.date()
            for c in for_task
        ):
            continue
        due = effective_due(task, settings, now)
        (due_today if now < due else overdue).append((due, task))

    late_pause_until: datetime | None = None
    pause = timedelta(minutes=settings["latePauseMinutes"])
    for completion in completions:
        if not completion.get("late") or completion["status"] == "rejected":
            continue
        until = parse_dt(completion["completedAt"]) + pause
        if now < until and (late_pause_until is None or until > late_pause_until):
            late_pause_until = until

    in_window = in_restriction_window(settings, now)
    suspended = suspended_on is not None and suspended_on == date_key(now)
    restricted = in_window and not suspended and (bool(overdue) or late_pause_until is not None)

    reason: str | None = None
    if restricted:
        if overdue:
            names = ", ".join(
                translate("reason_overdue_task", language, title=t["title"], due=f"{d:%H:%M}")
                for d, t in overdue
            )
            reason = translate("reason_overdue", language, tasks=names)
        else:
            reason = translate("reason_late", language, until=f"{late_pause_until:%H:%M}")

    return {
        "dueToday": [_due_json(t, d) for d, t in due_today],
        "overdue": [_due_json(t, d) for d, t in overdue],
        "latePauseUntil": to_iso(late_pause_until) if late_pause_until else None,
        "inWindow": in_window,
        "suspended": suspended,
        "restricted": restricted,
        "reason": reason,
    }


# ---- The family's settings ----------------------------------------------------

DEFAULT_SETTINGS: dict[str, Any] = {
    "defaultDueTime": "18:00",
    "restrictionStart": "15:00",
    "restrictionEnd": "21:00",
    "latePauseMinutes": 10,
    "warningMinutes": 60,
    "winterFromWeek": 43,
    "winterToWeek": 13,
}

_TIME_SETTINGS = {"defaultDueTime", "restrictionStart", "restrictionEnd"}
_INT_SETTINGS = {
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
CHILD_ALLOWED_ACTIONS = frozenset({"complete_task"})


def is_action_allowed_for_child(action: dict[str, Any], child_id: str) -> bool:
    if action.get("type") not in CHILD_ALLOWED_ACTIONS:
        return False
    payload = action.get("payload")
    return isinstance(payload, dict) and payload.get("childId") == child_id


def task_applies_to_child(task: dict[str, Any], child_id: str) -> bool:
    assigned = task.get("assignedChildIds")
    return not assigned or child_id in assigned


def filter_state_for_child(state: dict[str, Any], child_id: str) -> dict[str, Any]:
    """Only what one child's tablet needs - no siblings' data."""
    paid_out = state.get("paidOutOreByChild") or {}
    suspensions = state.get("restrictionSuspensions") or {}
    return {
        **state,
        "children": [c for c in state.get("children", []) if c["id"] == child_id],
        "tasks": [t for t in state.get("tasks", []) if task_applies_to_child(t, child_id)],
        "completions": [c for c in state.get("completions", []) if c["childId"] == child_id],
        "balanceAdjustments": [
            a for a in state.get("balanceAdjustments", []) if a["childId"] == child_id
        ],
        "totalPaidOutOre": 0,
        "paidOutOreByChild": {child_id: paid_out[child_id]} if child_id in paid_out else {},
        "restrictionSuspensions": (
            {child_id: suspensions[child_id]} if child_id in suspensions else {}
        ),
    }
