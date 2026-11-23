"""The family's data and actions - HA is the "source of truth".

Originally a translation of the app's `TaskRepository`: the same actions
(`create_task`, `complete_task`, `approve_completion` ...) with the same
error messages. Since Del H the app is a pure view: HA keeps all history and
sends the app only the current state, calculated here (`state_json`), and the
history on request (`history`). The locks and the child's notifications
(Del H3/H4) are kept here too; `tick` moves them on as time passes.
"""

from __future__ import annotations

from datetime import date, datetime, timedelta
from typing import Any
import uuid

from . import logic
from .const import DEFAULT_CURRENCY
from .i18n import LocalizedError, format_amount, translate


class FamilyError(LocalizedError):
    """An action is not valid in the current state."""


def empty_family() -> dict[str, Any]:
    return {
        "children": [],
        "tasks": [],
        "completions": [],
        "balanceAdjustments": [],
        "paidOutOreByChild": {},
        "familySettings": dict(logic.DEFAULT_SETTINGS),
        # Occurrences that were late and not done at midnight (no money).
        "missed": [],
        # The last day whose midnight cleanup has run ("YYYY-MM-DD").
        "cleanedThrough": None,
        # Every lock ever (Del H4); a child's current lock is the one that is
        # pending or running. The rest are kept for the history.
        "locks": [],
        # The children's notifications (Del H3), kept for 7 days.
        "notifications": [],
    }


HISTORY_TYPES = ("approved", "rejected", "adjustment", "missed", "lock")
HISTORY_PAGE_DAYS = 30
# How many days back a cleanup catches up after HA has been down.
MAX_CLEANUP_DAYS = 31
MAX_ID_LENGTH = 100
MAX_REASON_LENGTH = 500

# ---- Locks (Del H4) ----------------------------------------------------------
#
# A lock is caused by a mandatory task becoming overdue or being rejected.
# Every lock waits ("pending") until the child's tablet reports use (screen on
# or unlocked); then it runs `lockMinutes` and ends by itself. A pending lock
# lapses 24 hours after it began. One lock at a time per child: causes are
# merged into a pending lock, and causes that arrive while a lock runs are
# absorbed by it. One penalty per task occurrence: an occurrence that has
# caused a lock never causes another one (also not after "lift lock").
#
# - A late task done while its lock is pending: its cause becomes "late", and
#   a lock with only "late" causes runs `latePauseMinutes`. It still earns money.
# - When a lock has run out, its overdue tasks that are still not done are
#   "forfeited": done after that they give 0, and the child is told at once.

LOCK_PENDING = "pending"
LOCK_RUNNING = "running"
LOCK_ENDED = "ended"
LOCK_LIFTED = "lifted"
LOCK_LAPSED = "lapsed"
LOCK_CANCELLED = "cancelled"  # only "late" causes and `latePauseMinutes` = 0
CURRENT_LOCK = (LOCK_PENDING, LOCK_RUNNING)

CAUSE_OVERDUE = "overdue"
CAUSE_REJECTED = "rejected"
CAUSE_LATE = "late"
_FULL_CAUSES = (CAUSE_OVERDUE, CAUSE_REJECTED)
_REASON_KEYS = {
    CAUSE_OVERDUE: "lock_reason_overdue",
    CAUSE_REJECTED: "lock_reason_rejected",
    CAUSE_LATE: "lock_reason_late",
}

LOCK_PENDING_LIFETIME = timedelta(hours=24)
# What the child's tablet reports (Android's SCREEN_ON / USER_PRESENT).
USE_EVENTS = ("screen_on", "user_present")

# ---- The child's notifications (Del H3) ---------------------------------------

NOTIFICATION_DEADLINE_WARNING = "deadlineWarning"
NOTIFICATION_OVERDUE = "overdue"
NOTIFICATION_REJECTED = "rejected"
NOTIFICATION_LOCK_STARTED = "lockStarted"
NOTIFICATION_FORGOTTEN = "forgotten"
NOTIFICATION_RETENTION = timedelta(days=7)


def migrate_family(
    data: dict[str, Any], now: datetime, old_minor_version: int = 1
) -> dict[str, Any]:
    """Stored family data from an older storage version -> the current one.

    1.1 -> 1.2 (Del H1/H2):

    - Completions get `occurrenceDate` (the day they were done).
    - Active tasks get `availableFrom` = now, so occurrences from before the
      upgrade are never counted as missed (a one-off task that used to come
      back every day would otherwise be deactivated at the first midnight).
    - `missed` and `cleanedThrough` are added.

    1.2 -> 1.3 (Del H3/H4):

    - The 15:00-21:00 restriction window and "lift today" are gone
      (`restrictionStart`, `restrictionEnd`, `restrictionSuspensions`).
    - `lockMinutes` (default 60), `locks` and `notifications` are added.
    """
    if old_minor_version < 2:
        for completion in data.get("completions", []):
            completion.setdefault(
                "occurrenceDate", logic.date_key(logic.parse_dt(completion["completedAt"]))
            )
        for task in data.get("tasks", []):
            if task.get("active", True):
                task.setdefault("availableFrom", logic.to_iso(now))
        data.setdefault("missed", [])
        data.setdefault("cleanedThrough", logic.date_key(now - timedelta(days=1)))
    if old_minor_version < 3:
        settings = data.setdefault("familySettings", {})
        for key in logic.REMOVED_SETTINGS:
            settings.pop(key, None)
        settings.setdefault("lockMinutes", logic.DEFAULT_SETTINGS["lockMinutes"])
        data.pop("restrictionSuspensions", None)
        data.setdefault("locks", [])
        data.setdefault("notifications", [])
    return data


def _new_id() -> str:
    return str(uuid.uuid4())


def _require_str(payload: dict[str, Any], key: str, error: str) -> str:
    value = payload.get(key)
    if not isinstance(value, str) or not value.strip():
        raise FamilyError(error)
    return value


def _midnight(day: str) -> datetime:
    """00:00 at the start of the day `"YYYY-MM-DD"`."""
    parsed = date.fromisoformat(day)
    return datetime(parsed.year, parsed.month, parsed.day)


def _require_int(payload: dict[str, Any], key: str) -> int:
    value = payload.get(key)
    if not isinstance(value, int) or isinstance(value, bool):
        raise FamilyError("missing_field", field=key)
    return value


def _due_json(entry: dict[str, Any]) -> dict[str, Any]:
    """A task entry for HA's entities: title and deadline as "HH:MM"."""
    return {
        "taskId": entry["taskId"],
        "title": entry["title"],
        "due": f"{logic.parse_dt(entry['deadline']):%H:%M}" if entry["deadline"] else None,
    }


class Family:
    """Wrapper around the family's data dict (stored as JSON in HA's storage)."""

    def __init__(self, data: dict[str, Any] | None = None) -> None:
        self.data = empty_family()
        if data:
            self.data.update(data)
        self.data.pop("restrictionSuspensions", None)
        self.data["familySettings"] = logic.settings_from(self.data.get("familySettings"))
        # Lock events for HA's event bus, collected until the coordinator
        # fires them (`pop_events`). Not stored.
        self.events: list[dict[str, Any]] = []

    # ---- Lookups ---------------------------------------------------------------

    @property
    def children(self) -> list[dict[str, Any]]:
        return sorted(self.data["children"], key=lambda c: (c["sortOrder"], c["createdAt"]))

    @property
    def settings(self) -> dict[str, Any]:
        return self.data["familySettings"]

    def child(self, child_id: str) -> dict[str, Any] | None:
        return next((c for c in self.data["children"] if c["id"] == child_id), None)

    def task(self, task_id: str) -> dict[str, Any] | None:
        return next((t for t in self.data["tasks"] if t["id"] == task_id), None)

    def completion(self, completion_id: str) -> dict[str, Any] | None:
        return next((c for c in self.data["completions"] if c["id"] == completion_id), None)

    @property
    def active_tasks(self) -> list[dict[str, Any]]:
        return [t for t in self.data["tasks"] if t.get("active", True)]

    def resolved_child_ids(self, task: dict[str, Any]) -> list[str]:
        """Children the task applies to now; "all children" is looked up dynamically."""
        child_ids = [c["id"] for c in self.children]
        assigned = task.get("assignedChildIds")
        if not assigned:
            return child_ids
        return [c for c in assigned if c in child_ids]

    def _completions_for(self, child_id: str, task_id: str | None = None) -> list[dict[str, Any]]:
        return [
            c
            for c in self.data["completions"]
            if c["childId"] == child_id and (task_id is None or c["taskId"] == task_id)
        ]

    # ---- The child's task list (Del H2) ------------------------------------------------

    def _since(self, task: dict[str, Any], child_id: str, now: datetime) -> datetime:
        """When the task started to apply to the child. After a pause the
        tasks start over, so nothing from during the pause becomes overdue."""
        since = logic.parse_dt(task.get("availableFrom") or task["createdAt"])
        child = self.child(child_id)
        if child is not None:
            since = max(since, logic.parse_dt(child["createdAt"]))
            resumed = self._resumed_at(child, now)
            if resumed is not None:
                since = max(since, resumed)
        return since

    def _missed_days(self, child_id: str, task_id: str) -> set[date]:
        return {
            date.fromisoformat(m["date"])
            for m in self.data["missed"]
            if m["childId"] == child_id and m["taskId"] == task_id
        }

    def occurrence(
        self, task: dict[str, Any], child_id: str, now: datetime
    ) -> dict[str, Any] | None:
        """The child's next occurrence of the task (see `logic.next_occurrence`).

        While the child is paused no task is mandatory: no deadline, never
        overdue, no lock - but the tasks still earn money.
        """
        if not task.get("active", True):
            return None
        if task.get("mandatory") and self.is_paused(child_id, now):
            task = {**task, "mandatory": False}
        return logic.next_occurrence(
            task,
            self._completions_for(child_id, task["id"]),
            self._missed_days(child_id, task["id"]),
            self.settings,
            now,
            self._since(task, child_id, now),
        )

    def task_entries(self, child_id: str, now: datetime) -> list[dict[str, Any]]:
        """One entry per task for the child, within the 5-day horizon."""
        entries = []
        paused = self.is_paused(child_id, now)
        for task in self.active_tasks:
            if child_id not in self.resolved_child_ids(task):
                continue
            occurrence = self.occurrence(task, child_id, now)
            if not logic.in_view(occurrence, now):
                continue
            completion = occurrence["completion"]
            deadline = occurrence["deadline"]
            day = logic.date_key(occurrence["date"])
            forfeited = occurrence["status"] == logic.OVERDUE and self._forfeited(
                child_id, task["id"], day
            )
            if completion:
                amount = completion["amountAtCompletionOre"]
            else:
                amount = 0 if forfeited else task["amountOre"]
            entries.append(
                {
                    "taskId": task["id"],
                    "title": task["title"],
                    "description": task.get("description"),
                    "amountOre": amount,
                    "recurrence": task.get("recurrence", "once"),
                    "mandatory": bool(task.get("mandatory")) and not paused,
                    "startTime": task.get("startTime"),
                    "dueTime": task.get("dueTime"),
                    "date": day,
                    "deadline": logic.to_iso(deadline) if deadline else None,
                    "status": occurrence["status"],
                    "completionId": completion["id"] if completion else None,
                    "late": bool(completion.get("late")) if completion else False,
                    # The lock for this overdue occurrence has run out: no money.
                    "forfeited": forfeited,
                }
            )
        status_order = {logic.OVERDUE: 0, logic.AVAILABLE: 1, logic.AWAITING_APPROVAL: 2}
        entries.sort(
            key=lambda e: (
                e["date"],
                status_order.get(e["status"], 3),
                e["deadline"] or "~",
                e["title"].lower(),
            )
        )
        return entries

    # ---- Midnight cleanup (Del H2) ------------------------------------------------------

    def cleanup(self, now: datetime) -> list[dict[str, Any]]:
        """Drops every occurrence that was late and not done at midnight.

        Runs for each day that has ended since the last run (HA may have been
        down at midnight), so it is safe to call as often as you like. A missed
        occurrence gives no money; it is kept in `missed` for the history and
        so that the next occurrence moves on (a weekly task: 7 days from the
        missed deadline). A missed one-off task is deactivated for good.
        Returns the new `missed` records.
        """
        today = now.date()
        last = self.data.get("cleanedThrough")
        if last is None:
            # A new family: nothing can have been missed before today.
            self.data["cleanedThrough"] = logic.date_key(today - timedelta(days=1))
            return []
        day = max(
            date.fromisoformat(last) + timedelta(days=1),
            today - timedelta(days=MAX_CLEANUP_DAYS),
        )
        records: list[dict[str, Any]] = []
        while day < today:
            end_of_day = datetime(day.year, day.month, day.day) + timedelta(
                days=1, microseconds=-1
            )
            records.extend(self._cleanup_day(end_of_day, now))
            day += timedelta(days=1)
        self.data["cleanedThrough"] = logic.date_key(today - timedelta(days=1))
        return records

    def _cleanup_day(self, end_of_day: datetime, now: datetime) -> list[dict[str, Any]]:
        records = []
        for task in self.active_tasks:
            once_missed = False
            for child_id in self.resolved_child_ids(task):
                # A weekly task can have several missed occurrences in a row
                # if HA was down for long; each one moves the next by 7 days.
                for _ in range(MAX_CLEANUP_DAYS):
                    occurrence = self.occurrence(task, child_id, end_of_day)
                    if occurrence is None or occurrence["status"] != logic.OVERDUE:
                        break
                    record = {
                        "id": _new_id(),
                        "taskId": task["id"],
                        "childId": child_id,
                        "date": logic.date_key(occurrence["date"]),
                        "deadline": logic.to_iso(occurrence["deadline"]),
                        "amountOre": task["amountOre"],
                        "missedAt": logic.to_iso(now),
                    }
                    self.data["missed"].append(record)
                    records.append(record)
                    # The locks are deliberately left alone (Del H4): a lock
                    # still pending because of this occurrence stays and
                    # lapses 24 hours after it began; a running one runs out.
                    if task.get("recurrence", "once") == "once":
                        once_missed = True
                        break
            if once_missed:
                task["active"] = False  # gone for good; a parent must create it again
        return records

    # ---- Balance -----------------------------------------------------------------

    def total_earned_ore(self, child_id: str) -> int:
        return sum(
            c["amountAtCompletionOre"]
            for c in self._completions_for(child_id)
            if c["status"] == "approved"
        )

    def total_adjustments_ore(self, child_id: str) -> int:
        return sum(
            a["amountOre"] for a in self.data["balanceAdjustments"] if a["childId"] == child_id
        )

    def balance_ore(self, child_id: str) -> int:
        paid_out = self.data["paidOutOreByChild"].get(child_id, 0)
        balance = self.total_earned_ore(child_id) - paid_out + self.total_adjustments_ore(child_id)
        return max(balance, 0)

    def earned_this_week_ore(self, child_id: str, now: datetime) -> int:
        cutoff = now - timedelta(days=7)
        return sum(
            c["amountAtCompletionOre"]
            for c in self._completions_for(child_id)
            if c["status"] == "approved" and logic.parse_dt(c["completedAt"]) > cutoff
        )

    # ---- Pause per child (Del H4) ---------------------------------------------------
    #
    # A child's pause is stored on the child: `pause` = {"from": ISO time,
    # "until": "YYYY-MM-DD" or None}. `until` is the day the tasks are mandatory
    # again (from 00:00). `resumedAt` remembers when the last pause ended.

    def is_paused(self, child_id: str, now: datetime) -> bool:
        child = self.child(child_id)
        pause = child.get("pause") if child else None
        if not pause or logic.parse_dt(pause["from"]) > now:
            return False
        until = pause.get("until")
        return until is None or now < _midnight(until)

    def paused_until(self, child_id: str, now: datetime) -> str | None:
        child = self.child(child_id)
        if child is None or not self.is_paused(child_id, now):
            return None
        return child["pause"].get("until")

    def _resumed_at(self, child: dict[str, Any], now: datetime) -> datetime | None:
        times = []
        if child.get("resumedAt"):
            times.append(logic.parse_dt(child["resumedAt"]))
        pause = child.get("pause")
        if pause and pause.get("until") and _midnight(pause["until"]) <= now:
            times.append(_midnight(pause["until"]))
        return max(times) if times else None

    def _resume_if_due(self, child: dict[str, Any], now: datetime) -> bool:
        """A pause whose end date has come is over (resumes automatically)."""
        pause = child.get("pause")
        if not pause or not pause.get("until") or now < _midnight(pause["until"]):
            return False
        child["resumedAt"] = logic.to_iso(_midnight(pause["until"]))
        del child["pause"]
        return True

    # ---- Locks (Del H4) --------------------------------------------------------------

    def current_lock(self, child_id: str) -> dict[str, Any] | None:
        """The child's pending or running lock (at most one)."""
        for lock in reversed(self.data["locks"]):
            if lock["childId"] == child_id and lock["status"] in CURRENT_LOCK:
                return lock
        return None

    def _cause_for(
        self, child_id: str, task_id: str, day: str
    ) -> tuple[dict[str, Any], dict[str, Any]] | None:
        """The lock and cause an occurrence has already been penalized with."""
        for lock in self.data["locks"]:
            if lock["childId"] != child_id:
                continue
            for cause in lock["causes"]:
                if cause["taskId"] == task_id and cause["date"] == day:
                    return lock, cause
        return None

    def _forfeited(self, child_id: str, task_id: str, day: str) -> bool:
        found = self._cause_for(child_id, task_id, day)
        return found is not None and bool(found[1].get("forfeited"))

    def _lock_minutes(self, lock: dict[str, Any]) -> int:
        """How long the lock runs: `lockMinutes`, or `latePauseMinutes` when
        all its causes are tasks that were done late."""
        full = any(
            c["kind"] in _FULL_CAUSES for c in lock["causes"] if not c.get("absorbed")
        )
        return self.settings["lockMinutes" if full else "latePauseMinutes"]

    def _new_cause(
        self,
        kind: str,
        task: dict[str, Any],
        day: date,
        deadline: datetime | None,
        **extra: Any,
    ) -> dict[str, Any]:
        return {
            "kind": kind,
            "taskId": task["id"],
            "taskTitle": task["title"],
            "date": logic.date_key(day),
            "deadline": logic.to_iso(deadline) if deadline else None,
            "completionId": None,
            "reason": None,
            "absorbed": False,
            "forfeited": False,
            **extra,
        }

    def _add_cause(self, child_id: str, cause: dict[str, Any], now: datetime) -> bool:
        """Penalizes an occurrence - once. Merged into the pending lock,
        absorbed by a running one, or a new pending lock."""
        if self._cause_for(child_id, cause["taskId"], cause["date"]) is not None:
            return False
        cause["at"] = logic.to_iso(now)
        lock = self.current_lock(child_id)
        if lock is None:
            lock = {
                "id": _new_id(),
                "childId": child_id,
                "status": LOCK_PENDING,
                "createdAt": logic.to_iso(now),
                "startedAt": None,
                "endsAt": None,
                "endedAt": None,
                "minutes": None,
                "trigger": None,
                "causes": [],
            }
            self.data["locks"].append(lock)
        elif lock["status"] == LOCK_RUNNING:
            cause["absorbed"] = True
        lock["causes"].append(cause)
        self._cancel_if_nothing_to_run(lock, now)
        return True

    def _cancel_if_nothing_to_run(self, lock: dict[str, Any], now: datetime) -> None:
        if lock["status"] == LOCK_PENDING and self._lock_minutes(lock) <= 0:
            lock["status"] = LOCK_CANCELLED
            lock["endedAt"] = logic.to_iso(now)

    def _late_completion(
        self, child_id: str, task: dict[str, Any], occurrence: dict[str, Any], now: datetime
    ) -> None:
        """A late task is done: a pending lock for it becomes a short one."""
        day = logic.date_key(occurrence["date"])
        found = self._cause_for(child_id, task["id"], day)
        if found is None:
            # Done before the overdue occurrence was noticed (between two ticks).
            self._add_cause(
                child_id,
                self._new_cause(CAUSE_LATE, task, occurrence["date"], occurrence["deadline"]),
                now,
            )
            return
        lock, cause = found
        if lock["status"] == LOCK_PENDING and cause["kind"] == CAUSE_OVERDUE:
            cause["kind"] = CAUSE_LATE
            self._cancel_if_nothing_to_run(lock, now)

    def _start_lock(self, lock: dict[str, Any], now: datetime, trigger: dict[str, Any]) -> None:
        minutes = self._lock_minutes(lock)
        lock.update(
            status=LOCK_RUNNING,
            startedAt=logic.to_iso(now),
            minutes=minutes,
            endsAt=logic.to_iso(now + timedelta(minutes=minutes)),
            trigger=trigger,
        )
        self._notify(
            lock["childId"],
            NOTIFICATION_LOCK_STARTED,
            now,
            minutes=minutes,
            endsAt=lock["endsAt"],
            causes=[self._cause_summary(c) for c in lock["causes"]],
        )
        self.events.append(
            {"event": "lock_started", "childId": lock["childId"], "lockId": lock["id"]}
        )

    def _end_lock(self, lock: dict[str, Any], now: datetime) -> None:
        """The lock has run out. Its overdue tasks that are still not done
        give no money any more, and the child is told."""
        child_id = lock["childId"]
        lock["status"] = LOCK_ENDED
        lock["endedAt"] = lock["endsAt"]
        for cause in lock["causes"]:
            if cause["kind"] != CAUSE_OVERDUE:
                continue
            task = self.task(cause["taskId"])
            if task is None:
                continue
            occurrence = self.occurrence(task, child_id, now)
            if (
                occurrence is not None
                and occurrence["status"] == logic.OVERDUE
                and logic.date_key(occurrence["date"]) == cause["date"]
            ):
                cause["forfeited"] = True
                self._notify(
                    child_id,
                    NOTIFICATION_FORGOTTEN,
                    now,
                    taskId=task["id"],
                    taskTitle=task["title"],
                    date=cause["date"],
                )
        self.events.append({"event": "lock_ended", "childId": child_id, "lockId": lock["id"]})

    def _lift(self, child_id: str, now: datetime) -> None:
        lock = self.current_lock(child_id)
        if lock is None:
            return
        was_running = lock["status"] == LOCK_RUNNING
        lock["status"] = LOCK_LIFTED
        lock["endedAt"] = lock["liftedAt"] = logic.to_iso(now)
        self.events.append(
            {
                "event": "lock_lifted",
                "childId": child_id,
                "lockId": lock["id"],
                "wasRunning": was_running,
            }
        )

    def pop_events(self) -> list[dict[str, Any]]:
        events, self.events = self.events, []
        return events

    def _cause_summary(self, cause: dict[str, Any]) -> dict[str, Any]:
        return {
            "kind": cause["kind"],
            "taskTitle": cause["taskTitle"],
            "deadline": cause.get("deadline"),
        }

    def _cause_json(self, cause: dict[str, Any]) -> dict[str, Any]:
        task = self.task(cause["taskId"]) or {}
        return {
            "kind": cause["kind"],
            "taskId": cause["taskId"],
            "taskTitle": task.get("title", cause["taskTitle"]),
            "date": cause["date"],
            "deadline": cause.get("deadline"),
            "reason": cause.get("reason"),
            "absorbed": bool(cause.get("absorbed")),
        }

    @staticmethod
    def reason_text(causes: list[dict[str, Any]], language: str | None = None) -> str | None:
        """The lock's reason, e.g. "Missing: Dishes (due 18:00); Rejected: Tidy up"."""
        texts = []
        for cause in causes:
            deadline = cause.get("deadline")
            texts.append(
                translate(
                    _REASON_KEYS[cause["kind"]],
                    language,
                    title=cause["taskTitle"],
                    due=f"{logic.parse_dt(deadline):%H:%M}" if deadline else "",
                )
            )
        return "; ".join(texts) or None

    def lock_json(
        self, child_id: str, now: datetime, language: str | None = None
    ) -> dict[str, Any]:
        """The child's lock as the app and HA's entities see it."""
        lock = self.current_lock(child_id)
        if lock is not None and (
            (lock["status"] == LOCK_RUNNING and logic.parse_dt(lock["endsAt"]) <= now)
            or (
                lock["status"] == LOCK_PENDING
                and logic.parse_dt(lock["createdAt"]) + LOCK_PENDING_LIFETIME <= now
            )
        ):
            lock = None  # over, but the next tick has not recorded it yet
        if lock is None:
            return {
                "status": "none",
                "reason": None,
                "reasons": [],
                "minutes": None,
                "pendingSince": None,
                "pendingUntil": None,
                "startedAt": None,
                "endsAt": None,
            }
        causes = [self._cause_json(c) for c in lock["causes"]]
        pending = lock["status"] == LOCK_PENDING
        return {
            "status": lock["status"],
            "reason": self.reason_text(causes, language),
            "reasons": causes,
            "minutes": self._lock_minutes(lock) if pending else lock["minutes"],
            "pendingSince": lock["createdAt"],
            "pendingUntil": (
                logic.to_iso(logic.parse_dt(lock["createdAt"]) + LOCK_PENDING_LIFETIME)
                if pending
                else None
            ),
            "startedAt": lock["startedAt"],
            "endsAt": lock["endsAt"],
        }

    # ---- Notifications for the child (Del H3) -----------------------------------------

    def _notify(self, child_id: str, kind: str, now: datetime, **fields: Any) -> None:
        self.data["notifications"].append(
            {
                "id": _new_id(),
                "childId": child_id,
                "type": kind,
                "at": logic.to_iso(now),
                "taskId": None,
                "taskTitle": None,
                "date": None,
                "deadline": None,
                "reason": None,
                **fields,
            }
        )

    def _notify_once(
        self,
        child_id: str,
        kind: str,
        now: datetime,
        task: dict[str, Any],
        occurrence: dict[str, Any],
    ) -> bool:
        """One notification of this kind per task occurrence."""
        day = logic.date_key(occurrence["date"])
        if any(
            n["childId"] == child_id
            and n["type"] == kind
            and n["taskId"] == task["id"]
            and n["date"] == day
            for n in self.data["notifications"]
        ):
            return False
        self._notify(
            child_id,
            kind,
            now,
            taskId=task["id"],
            taskTitle=task["title"],
            date=day,
            deadline=logic.to_iso(occurrence["deadline"]),
        )
        return True

    def notifications_json(
        self, child_id: str, now: datetime, language: str | None = None
    ) -> list[dict[str, Any]]:
        """The child's notifications from the last 7 days, newest first, each
        with a ready-made `message` in `language`."""
        cutoff = now - NOTIFICATION_RETENTION
        items = [
            n
            for n in self.data["notifications"]
            if n["childId"] == child_id and logic.parse_dt(n["at"]) > cutoff
        ]
        items.sort(key=lambda n: n["at"], reverse=True)
        return [
            {
                "id": n["id"],
                "type": n["type"],
                "at": n["at"],
                "taskId": n.get("taskId"),
                "taskTitle": n.get("taskTitle"),
                "date": n.get("date"),
                "deadline": n.get("deadline"),
                "reason": (
                    self.reason_text(n.get("causes") or [], language)
                    if n["type"] == NOTIFICATION_LOCK_STARTED
                    else n.get("reason")
                ),
                "minutes": n.get("minutes"),
                "endsAt": n.get("endsAt"),
                "message": self._notification_message(n, language),
            }
            for n in items
        ]

    def _notification_message(self, n: dict[str, Any], language: str | None) -> str:
        title = n.get("taskTitle") or ""
        due = f"{logic.parse_dt(n['deadline']):%H:%M}" if n.get("deadline") else ""
        kind = n["type"]
        if kind == NOTIFICATION_DEADLINE_WARNING:
            return translate("notification_deadline_warning", language, title=title, due=due)
        if kind == NOTIFICATION_OVERDUE:
            return translate("notification_overdue", language, title=title, due=due)
        if kind == NOTIFICATION_REJECTED:
            if n.get("reason"):
                return translate(
                    "notification_rejected_reason", language, title=title, reason=n["reason"]
                )
            return translate("notification_rejected", language, title=title)
        if kind == NOTIFICATION_LOCK_STARTED:
            return translate(
                "notification_lock_started",
                language,
                minutes=n.get("minutes"),
                reason=self.reason_text(n.get("causes") or [], language) or "",
            ).strip()
        return translate("notification_forgotten", language, title=title)

    # ---- Time passes -------------------------------------------------------------------

    def tick(self, now: datetime) -> bool:
        """Moves pauses, locks and notifications on to `now`. Called every 30
        seconds and around every action; safe to call as often as you like.
        Returns whether anything changed (so it must be saved)."""
        changed = False
        warning = timedelta(minutes=self.settings["warningMinutes"])
        for child in self.children:
            child_id = child["id"]
            changed |= self._resume_if_due(child, now)
            lock = self.current_lock(child_id)
            if lock is not None and lock["status"] == LOCK_PENDING:
                lapses = logic.parse_dt(lock["createdAt"]) + LOCK_PENDING_LIFETIME
                if now >= lapses:
                    lock["status"] = LOCK_LAPSED
                    lock["endedAt"] = logic.to_iso(lapses)
                    changed = True
            elif lock is not None and now >= logic.parse_dt(lock["endsAt"]):
                self._end_lock(lock, now)
                changed = True
            if self.is_paused(child_id, now):
                continue
            for task in self.active_tasks:
                if not task.get("mandatory") or child_id not in self.resolved_child_ids(task):
                    continue
                occurrence = self.occurrence(task, child_id, now)
                if occurrence is None or occurrence["deadline"] is None:
                    continue
                if occurrence["status"] == logic.OVERDUE:
                    cause = self._new_cause(
                        CAUSE_OVERDUE, task, occurrence["date"], occurrence["deadline"]
                    )
                    changed |= self._add_cause(child_id, cause, now)
                    changed |= self._notify_once(
                        child_id, NOTIFICATION_OVERDUE, now, task, occurrence
                    )
                elif (
                    occurrence["status"] == logic.AVAILABLE
                    and warning
                    and occurrence["deadline"] - warning <= now
                ):
                    changed |= self._notify_once(
                        child_id, NOTIFICATION_DEADLINE_WARNING, now, task, occurrence
                    )
        cutoff = now - NOTIFICATION_RETENTION
        kept = [n for n in self.data["notifications"] if logic.parse_dt(n["at"]) > cutoff]
        if len(kept) != len(self.data["notifications"]):
            self.data["notifications"] = kept
            changed = True
        return changed

    # ---- Actions -------------------------------------------------------------------

    def apply_action(self, action: dict[str, Any], now: datetime) -> dict[str, Any] | None:
        """Performs one action. Returns the affected completion, if any.

        Raises `FamilyError`, whose message the app shows in its own language.
        """
        action_type = action.get("type")
        payload = action.get("payload")
        if not isinstance(payload, dict):
            payload = {}
        handler = getattr(self, f"_action_{action_type}", None)
        if not isinstance(action_type, str) or handler is None:
            raise FamilyError("unknown_action", action=action_type)
        # The locks must be up to date before (e.g. a lock that has just run
        # out decides the money) and after the action (e.g. a new rejection).
        self.tick(now)
        result = handler(payload, now)
        self.tick(now)
        return result

    def _task_fields(self, payload: dict[str, Any], existing: dict[str, Any] | None) -> dict[str, Any]:
        """Fields from a create/update payload. On update a missing key means
        "keep", while an explicit `null` resets (like in the app)."""
        title = _require_str(payload, "title", "task_title_required").strip()
        amount = _require_int(payload, "amountOre")
        if amount < 0:
            raise FamilyError("negative_amount")
        recurrence = payload.get("recurrence")
        if recurrence not in logic.RECURRENCES:
            recurrence = "once"
        old = existing or {}

        def keep_or_set(key: str, normalize):
            if existing is not None and key not in payload:
                return old.get(key)
            return normalize(payload.get(key))

        mandatory = payload.get("mandatory")
        show_in_calendar = payload.get("showInCalendar")
        fields = {
            "title": title,
            # The description is always sent; if it is missing, it was removed.
            "description": payload.get("description") or None,
            "amountOre": amount,
            "recurrence": recurrence,
            "mandatory": bool(mandatory) if mandatory is not None else bool(old.get("mandatory")),
            "activeWeekdays": keep_or_set("activeWeekdays", logic.normalize_weekdays),
            "assignedChildIds": keep_or_set("assignedChildIds", logic.normalize_child_ids),
            "startTime": keep_or_set("startTime", logic.normalize_time),
            "dueTime": keep_or_set("dueTime", logic.normalize_time),
            "showInCalendar": (
                bool(show_in_calendar)
                if show_in_calendar is not None
                else bool(old.get("showInCalendar"))
            ),
        }
        if recurrence == "once":
            fields["activeWeekdays"] = None
        return fields

    def _action_create_task(self, payload: dict[str, Any], now: datetime) -> None:
        task_id = payload.get("id") or _new_id()
        existing = self.task(task_id)
        task = {
            "id": task_id,
            **self._task_fields(payload, None),
            # A retry keeps the original creation time.
            "createdAt": existing["createdAt"] if existing else logic.to_iso(now),
            "active": True,
        }
        # The same id twice (e.g. a retried action) replaces.
        self.data["tasks"] = [t for t in self.data["tasks"] if t["id"] != task_id] + [task]

    def _action_update_task(self, payload: dict[str, Any], now: datetime) -> None:
        task = self.task(_require_str(payload, "id", "missing_id"))
        if task is None:
            raise FamilyError("task_not_found")
        task.update(self._task_fields(payload, task))

    def _action_delete_task(self, payload: dict[str, Any], now: datetime) -> None:
        task = self.task(_require_str(payload, "id", "missing_id"))
        if task is not None:
            task["active"] = False

    def _action_complete_task(self, payload: dict[str, Any], now: datetime) -> dict[str, Any]:
        child_id = _require_str(payload, "childId", "missing_child_id")
        completion_id = payload.get("completionId") or _new_id()
        if not isinstance(completion_id, str) or len(completion_id) > MAX_ID_LENGTH:
            raise FamilyError("missing_field", field="completionId")
        if (existing := self.completion(completion_id)) is not None:
            # The same action sent again (e.g. after a timeout): success,
            # without a second completion.
            return existing
        task = self.task(_require_str(payload, "taskId", "missing_task"))
        if task is None or not task.get("active", True):
            raise FamilyError("task_not_found")
        if child_id not in self.resolved_child_ids(task):
            raise FamilyError("task_not_assigned")
        occurrence = self.occurrence(task, child_id, now)
        if occurrence is None or occurrence["status"] not in (logic.AVAILABLE, logic.OVERDUE):
            raise FamilyError("task_not_available")
        # HA's clock decides the time (and thereby "late"), not the tablet's -
        # a child cannot cheat by setting the clock back.
        late = occurrence["status"] == logic.OVERDUE
        amount = task["amountOre"]
        if late:
            if self._forfeited(child_id, task["id"], logic.date_key(occurrence["date"])):
                amount = 0  # the lock for it has run out
            else:
                self._late_completion(child_id, task, occurrence, now)
        completion = {
            "id": completion_id,
            "taskId": task["id"],
            "childId": child_id,
            "completedAt": logic.to_iso(now),
            "occurrenceDate": logic.date_key(occurrence["date"]),
            "status": "pending",
            "approvedAt": None,
            "amountAtCompletionOre": amount,
            "late": late,
        }
        self.data["completions"].append(completion)
        return completion

    def _decide(self, payload: dict[str, Any], status: str, now: datetime) -> dict[str, Any]:
        """Approves or rejects. The first answer counts; the same answer again
        (a retry, or the other parent) is a success without changes."""
        completion = self.completion(_require_str(payload, "completionId", "missing_completion"))
        if completion is None:
            raise FamilyError("completion_not_found")
        if completion["status"] == status:
            return completion
        if completion["status"] != "pending":
            raise FamilyError("completion_already_handled")
        completion["status"] = status
        completion["approvedAt" if status == "approved" else "rejectedAt"] = logic.to_iso(now)
        return completion

    def _action_approve_completion(self, payload: dict[str, Any], now: datetime) -> dict[str, Any]:
        return self._decide(payload, "approved", now)

    def _action_reject_completion(self, payload: dict[str, Any], now: datetime) -> dict[str, Any]:
        """Rejects, with the parent's optional `reason`. The child is told,
        and a rejected mandatory task locks the tablet (Del H4)."""
        reason = payload.get("reason")
        reason = reason.strip()[:MAX_REASON_LENGTH] or None if isinstance(reason, str) else None
        completion = self.completion(_require_str(payload, "completionId", "missing_completion"))
        already = completion is not None and completion["status"] == "rejected"
        completion = self._decide(payload, "rejected", now)
        if already:
            return completion
        completion["rejectReason"] = reason
        child_id = completion["childId"]
        task = self.task(completion["taskId"])
        if task is None or self.child(child_id) is None:
            return completion
        day = logic.completion_day(completion)
        self._notify(
            child_id,
            NOTIFICATION_REJECTED,
            now,
            taskId=task["id"],
            taskTitle=task["title"],
            date=logic.date_key(day),
            reason=reason,
        )
        if task.get("mandatory") and not self.is_paused(child_id, now):
            deadline = logic.effective_due(
                task, self.settings, datetime(day.year, day.month, day.day)
            )
            cause = self._new_cause(
                CAUSE_REJECTED, task, day, deadline, completionId=completion["id"], reason=reason
            )
            self._add_cause(child_id, cause, now)
        return completion

    def _existing_child_id(self, payload: dict[str, Any], key: str = "childId") -> str:
        child_id = _require_str(payload, key, "missing_child_id")
        if self.child(child_id) is None:
            raise FamilyError("child_not_found")
        return child_id

    def _action_mark_paid_out(self, payload: dict[str, Any], now: datetime) -> None:
        child_id = self._existing_child_id(payload)
        self.data["paidOutOreByChild"][child_id] = self.total_earned_ore(
            child_id
        ) + self.total_adjustments_ore(child_id)

    def _action_adjust_balance(self, payload: dict[str, Any], now: datetime) -> None:
        child_id = self._existing_child_id(payload)
        amount = _require_int(payload, "amountOre")
        note = payload.get("note")
        if not isinstance(note, str) or not note.strip():
            raise FamilyError("adjustment_note_required")
        adjustment_id = payload.get("id") or _new_id()
        if any(a["id"] == adjustment_id for a in self.data["balanceAdjustments"]):
            return
        self.data["balanceAdjustments"].append(
            {
                "id": adjustment_id,
                "amountOre": amount,
                "note": note.strip(),
                "childId": child_id,
                "createdAt": logic.to_iso(now),
            }
        )

    def _action_add_child(self, payload: dict[str, Any], now: datetime) -> None:
        name = _require_str(payload, "name", "child_name_required").strip()
        child_id = payload.get("id") or _new_id()
        if self.child(child_id) is not None:
            return
        self.data["children"].append(
            {
                "id": child_id,
                "name": name,
                "sortOrder": len(self.data["children"]),
                "createdAt": logic.to_iso(now),
            }
        )

    def _action_rename_child(self, payload: dict[str, Any], now: datetime) -> None:
        child_id = self._existing_child_id(payload, "id")
        name = _require_str(payload, "name", "child_name_required").strip()
        self.child(child_id)["name"] = name

    def _action_delete_child(self, payload: dict[str, Any], now: datetime) -> None:
        # Deleting a child that is already gone (a retry) is a success.
        child_id = _require_str(payload, "id", "missing_child_id")
        self.data["children"] = [c for c in self.data["children"] if c["id"] != child_id]

    def _action_lift_lock(self, payload: dict[str, Any], now: datetime) -> None:
        """Clears the child's pending and running lock. The occurrences that
        caused it never lock again, but new causes can."""
        self._lift(self._existing_child_id(payload), now)

    # Before Del H4: "lift the restriction today". Kept for older apps.
    _action_suspend_restriction = _action_lift_lock

    def _action_set_pause(self, payload: dict[str, Any], now: datetime) -> None:
        """Pauses the child (`paused` true, optional `until` = the date the
        tasks are mandatory again) or ends the pause (`paused` false).
        Pausing also lifts the child's lock."""
        child_id = self._existing_child_id(payload)
        child = self.child(child_id)
        paused = payload.get("paused")
        if not isinstance(paused, bool):
            raise FamilyError("missing_field", field="paused")
        if not paused:
            if child.pop("pause", None) is not None:
                child["resumedAt"] = logic.to_iso(now)
            return
        until = payload.get("until")
        if until is not None:
            try:
                until_day = date.fromisoformat(until)
            except (TypeError, ValueError) as err:
                raise FamilyError("invalid_pause_until", value=until) from err
            if until_day <= now.date():
                raise FamilyError("invalid_pause_until", value=until)
            until = logic.date_key(until_day)
        started = child["pause"]["from"] if self.is_paused(child_id, now) else logic.to_iso(now)
        child["pause"] = {"from": started, "until": until}
        self._lift(child_id, now)

    def _action_report_use(self, payload: dict[str, Any], now: datetime) -> None:
        """The child's tablet is being used (screen on or unlocked): a pending
        lock starts now - by HA's clock, the tablet's `at` is only recorded."""
        child_id = self._existing_child_id(payload)
        event = payload.get("event")
        if event not in USE_EVENTS:
            raise FamilyError("missing_field", field="event")
        reported = payload.get("at")
        if not isinstance(reported, int) or isinstance(reported, bool):
            reported = None
        lock = self.current_lock(child_id)
        if lock is not None and lock["status"] == LOCK_PENDING:
            self._start_lock(lock, now, {"event": event, "at": reported})

    def _action_set_setting(self, payload: dict[str, Any], now: datetime) -> None:
        key = _require_str(payload, "key", "missing_setting")
        try:
            self.settings[key] = logic.validate_setting(key, payload.get("value"))
        except logic.InvalidSetting as err:
            raise FamilyError(err.key, **err.params) from err

    # ---- Exports -------------------------------------------------------------------

    def state_json(
        self,
        family_name: str,
        now: datetime,
        child_id: str | None = None,
        language: str | None = None,
    ) -> dict[str, Any]:
        """The current state for the app (Del H1), calculated by HA - no history.

        With `child_id` (a child's tablet) only that child's own data, plus
        the child's notifications; otherwise all children plus what the parent
        part needs: the approval list, the full task list for editing and the
        settings. Texts (lock reason, notification messages) are in `language`.
        """
        children = [
            c for c in self.children if child_id is None or c["id"] == child_id
        ]
        state: dict[str, Any] = {
            "familyName": family_name,
            "now": logic.to_iso(now),  # HA's local time (not the Unix `serverTime` of a 401)
            "today": logic.date_key(now),
            "children": [
                {
                    "id": child["id"],
                    "name": child["name"],
                    "sortOrder": child["sortOrder"],
                    "balanceOre": self.balance_ore(child["id"]),
                    "earnedThisWeekOre": self.earned_this_week_ore(child["id"], now),
                    "tasks": self.task_entries(child["id"], now),
                    "lock": self.lock_json(child["id"], now, language),
                    "paused": self.is_paused(child["id"], now),
                    "pausedUntil": self.paused_until(child["id"], now),
                }
                for child in children
            ],
        }
        if child_id is not None:
            for child in state["children"]:
                child["notifications"] = self.notifications_json(child["id"], now, language)
            return state
        state["approvals"] = [
            {
                key: value
                for key, value in self.completion_json(c).items()
                if key not in ("message", "reason")
            }
            for c in sorted(self.data["completions"], key=lambda c: c["completedAt"])
            if c["status"] == "pending" and self.child(c["childId"]) is not None
        ]
        state["tasks"] = [
            {
                key: task.get(key)
                for key in (
                    "id",
                    "title",
                    "description",
                    "amountOre",
                    "recurrence",
                    "mandatory",
                    "activeWeekdays",
                    "assignedChildIds",
                    "startTime",
                    "dueTime",
                    "showInCalendar",
                    "createdAt",
                )
            }
            for task in sorted(self.active_tasks, key=lambda t: t["createdAt"])
        ]
        state["settings"] = dict(self.settings)
        return state

    # ---- History on request (Del H2) ---------------------------------------------------

    def history(
        self,
        before: date,
        child_id: str | None = None,
        types: set[str] | None = None,
        language: str | None = None,
    ) -> dict[str, Any]:
        """One page of history: the 30 days before `before` (exclusive), newest
        first. `nextBefore` is the `before` of the next (older) page, or `None`
        when nothing older exists."""
        start = before - timedelta(days=HISTORY_PAGE_DAYS)
        items = [
            item
            for item in self._history_items(language)
            if (child_id is None or item["childId"] == child_id)
            and (types is None or item["type"] in types)
        ]
        page = [i for i in items if start <= logic.parse_dt(i["at"]).date() < before]
        page.sort(key=lambda i: logic.parse_dt(i["at"]), reverse=True)
        older = any(logic.parse_dt(i["at"]).date() < start for i in items)
        return {
            "from": logic.date_key(start),
            "before": logic.date_key(before),
            "items": page,
            "nextBefore": logic.date_key(start) if older else None,
        }

    def _history_items(self, language: str | None = None) -> list[dict[str, Any]]:
        def names(child_id: str, task_id: str | None) -> dict[str, Any]:
            child = self.child(child_id) or {}
            task = (self.task(task_id) if task_id else None) or {}
            return {
                "childId": child_id,
                "childName": child.get("name", ""),
                "taskId": task_id,
                "taskTitle": task.get("title") if task_id else None,
            }

        items: list[dict[str, Any]] = []
        for c in self.data["completions"]:
            if c["status"] == "pending":
                continue
            decided = c.get("approvedAt") if c["status"] == "approved" else c.get("rejectedAt")
            items.append(
                {
                    "id": c["id"],
                    "type": c["status"],  # "approved" or "rejected"
                    "at": decided or c["completedAt"],
                    **names(c["childId"], c["taskId"]),
                    "amountOre": c["amountAtCompletionOre"],
                    "completedAt": c["completedAt"],
                    "late": bool(c.get("late")),
                    # The parent's reason for a rejection.
                    "note": c.get("rejectReason"),
                }
            )
        for a in self.data["balanceAdjustments"]:
            items.append(
                {
                    "id": a["id"],
                    "type": "adjustment",
                    "at": a["createdAt"],
                    **names(a["childId"], None),
                    "amountOre": a["amountOre"],
                    "completedAt": None,
                    "late": False,
                    "note": a.get("note"),
                }
            )
        for m in self.data["missed"]:
            items.append(
                {
                    "id": m["id"],
                    "type": "missed",
                    "at": m["deadline"],
                    **names(m["childId"], m["taskId"]),
                    "amountOre": m["amountOre"],
                    "completedAt": None,
                    "late": False,
                    "note": None,
                }
            )
        # Locks: one item when a lock starts, and one when it ends or is
        # lifted. Pending locks that lapsed or were never needed are left out.
        for lock in self.data["locks"]:
            causes = [self._cause_json(c) for c in lock["causes"]]
            common = {
                "type": "lock",
                **names(lock["childId"], None),
                "amountOre": 0,
                "completedAt": None,
                "late": False,
                "note": self.reason_text(causes, language),
                "minutes": lock.get("minutes"),
                "reasons": causes,
            }
            events = []
            if lock.get("startedAt"):
                events.append(("started", lock["startedAt"]))
            if lock["status"] == LOCK_ENDED:
                events.append(("ended", lock["endedAt"]))
            if lock["status"] == LOCK_LIFTED:
                events.append(("lifted", lock["liftedAt"]))
            for event, at in events:
                items.append(
                    {"id": f"{lock['id']}-{event}", "at": at, "lockEvent": event, **common}
                )
        return items

    def completion_json(
        self,
        completion: dict[str, Any],
        language: str | None = None,
        currency: str = DEFAULT_CURRENCY,
    ) -> dict[str, Any]:
        """A completion with names - used in events and sensors. `message` is a
        ready-made notification text in `language` (used by the blueprints)."""
        child = self.child(completion["childId"]) or {}
        task = self.task(completion["taskId"]) or {}
        late = completion.get("late", False)
        message = translate(
            "notify_completion",
            language,
            child=child.get("name", ""),
            task=task.get("title", ""),
            amount=format_amount(completion["amountAtCompletionOre"], language, currency),
        )
        if late:
            message += translate("notify_late", language)
        return {
            "completionId": completion["id"],
            "childId": completion["childId"],
            "childName": child.get("name", ""),
            "taskId": completion["taskId"],
            "taskTitle": task.get("title", ""),
            "amountOre": completion["amountAtCompletionOre"],
            "completedAt": completion["completedAt"],
            "late": late,
            "reason": completion.get("rejectReason"),
            "message": message,
        }

    def summary(
        self,
        family_name: str,
        now: datetime,
        language: str | None = None,
        currency: str = DEFAULT_CURRENCY,
    ) -> dict[str, Any]:
        """Overview for HA's entities and events."""
        children = []
        for child in self.children:
            lock = self.lock_json(child["id"], now, language)
            entries = self.task_entries(child["id"], now)
            children.append(
                {
                    "id": child["id"],
                    "name": child["name"],
                    "balanceOre": self.balance_ore(child["id"]),
                    "earnedThisWeekOre": self.earned_this_week_ore(child["id"], now),
                    "lock": lock,
                    # The tablet is restricted exactly while a lock runs.
                    "restricted": lock["status"] == LOCK_RUNNING,
                    "paused": self.is_paused(child["id"], now),
                    "pausedUntil": self.paused_until(child["id"], now),
                    "overdue": [
                        _due_json(e) for e in entries if e["status"] == logic.OVERDUE
                    ],
                    "dueToday": [
                        _due_json(e)
                        for e in entries
                        if e["status"] == logic.AVAILABLE
                        and e["deadline"]
                        and e["date"] == logic.date_key(now)
                    ],
                }
            )
        return {
            "familyName": family_name,
            "updatedAt": logic.to_iso(now),
            "settings": dict(self.settings),
            "children": children,
            "pending": [
                self.completion_json(c, language, currency)
                for c in self.data["completions"]
                if c["status"] == "pending"
            ],
        }
