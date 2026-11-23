"""The family's data and actions - HA is the "source of truth".

Originally a translation of the app's `TaskRepository`: the same actions
(`create_task`, `complete_task`, `approve_completion` ...) with the same
error messages. Since Del H the app is a pure view: HA keeps all history and
sends the app only the current state, calculated here (`state_json`), and the
history on request (`history`).
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
        "restrictionSuspensions": {},
        # Occurrences that were late and not done at midnight (no money).
        "missed": [],
        # The last day whose midnight cleanup has run ("YYYY-MM-DD").
        "cleanedThrough": None,
    }


# History types. Locks (Del H4) will be added as their own type.
HISTORY_TYPES = ("approved", "rejected", "adjustment", "missed")
HISTORY_PAGE_DAYS = 30
# How many days back a cleanup catches up after HA has been down.
MAX_CLEANUP_DAYS = 31
MAX_ID_LENGTH = 100


def migrate_family(data: dict[str, Any], now: datetime) -> dict[str, Any]:
    """Stored family data from before Del H (storage 1.1) -> 1.2.

    - Completions get `occurrenceDate` (the day they were done).
    - Active tasks get `availableFrom` = now, so occurrences from before the
      upgrade are never counted as missed (a one-off task that used to come
      back every day would otherwise be deactivated at the first midnight).
    - `missed` and `cleanedThrough` are added.
    """
    for completion in data.get("completions", []):
        completion.setdefault(
            "occurrenceDate", logic.date_key(logic.parse_dt(completion["completedAt"]))
        )
    for task in data.get("tasks", []):
        if task.get("active", True):
            task.setdefault("availableFrom", logic.to_iso(now))
    data.setdefault("missed", [])
    data.setdefault("cleanedThrough", logic.date_key(now - timedelta(days=1)))
    return data


def _new_id() -> str:
    return str(uuid.uuid4())


def _require_str(payload: dict[str, Any], key: str, error: str) -> str:
    value = payload.get(key)
    if not isinstance(value, str) or not value.strip():
        raise FamilyError(error)
    return value


def _require_int(payload: dict[str, Any], key: str) -> int:
    value = payload.get(key)
    if not isinstance(value, int) or isinstance(value, bool):
        raise FamilyError("missing_field", field=key)
    return value


class Family:
    """Wrapper around the family's data dict (stored as JSON in HA's storage)."""

    def __init__(self, data: dict[str, Any] | None = None) -> None:
        self.data = empty_family()
        if data:
            self.data.update(data)
        self.data["familySettings"] = logic.settings_from(self.data.get("familySettings"))

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

    def _since(self, task: dict[str, Any], child_id: str) -> datetime:
        """When the task started to apply to the child."""
        since = logic.parse_dt(task.get("availableFrom") or task["createdAt"])
        child = self.child(child_id)
        if child is not None:
            since = max(since, logic.parse_dt(child["createdAt"]))
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
        """The child's next occurrence of the task (see `logic.next_occurrence`)."""
        if not task.get("active", True):
            return None
        return logic.next_occurrence(
            task,
            self._completions_for(child_id, task["id"]),
            self._missed_days(child_id, task["id"]),
            self.settings,
            now,
            self._since(task, child_id),
        )

    def task_entries(self, child_id: str, now: datetime) -> list[dict[str, Any]]:
        """One entry per task for the child, within the 5-day horizon."""
        entries = []
        for task in self.active_tasks:
            if child_id not in self.resolved_child_ids(task):
                continue
            occurrence = self.occurrence(task, child_id, now)
            if not logic.in_view(occurrence, now):
                continue
            completion = occurrence["completion"]
            deadline = occurrence["deadline"]
            entries.append(
                {
                    "taskId": task["id"],
                    "title": task["title"],
                    "description": task.get("description"),
                    "amountOre": (
                        completion["amountAtCompletionOre"] if completion else task["amountOre"]
                    ),
                    "recurrence": task.get("recurrence", "once"),
                    "mandatory": bool(task.get("mandatory")),
                    "startTime": task.get("startTime"),
                    "dueTime": task.get("dueTime"),
                    "date": logic.date_key(occurrence["date"]),
                    "deadline": logic.to_iso(deadline) if deadline else None,
                    "status": occurrence["status"],
                    "completionId": completion["id"] if completion else None,
                    "late": bool(completion.get("late")) if completion else False,
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
                    # Hook for the locks (Del H4, session 3a): a lock that is
                    # still waiting because of this occurrence must stay (and
                    # expire after 24 hours) - the cleanup does NOT clear it.
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

    # ---- Follow-up -----------------------------------------------------------------

    def follow_up(
        self, child_id: str, now: datetime, language: str | None = None
    ) -> dict[str, Any]:
        tasks = [t for t in self.active_tasks if child_id in self.resolved_child_ids(t)]
        return logic.compute_follow_up(
            tasks,
            self._completions_for(child_id),
            self.settings,
            now,
            self.data["restrictionSuspensions"].get(child_id),
            language,
        )

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
        return handler(payload, now)

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
        completion = {
            "id": completion_id,
            "taskId": task["id"],
            "childId": child_id,
            "completedAt": logic.to_iso(now),
            "occurrenceDate": logic.date_key(occurrence["date"]),
            "status": "pending",
            "approvedAt": None,
            "amountAtCompletionOre": task["amountOre"],
            "late": occurrence["status"] == logic.OVERDUE,
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
        return self._decide(payload, "rejected", now)

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

    def _action_suspend_restriction(self, payload: dict[str, Any], now: datetime) -> None:
        child_id = self._existing_child_id(payload)
        self.data["restrictionSuspensions"][child_id] = logic.date_key(now)

    def _action_set_setting(self, payload: dict[str, Any], now: datetime) -> None:
        key = _require_str(payload, "key", "missing_setting")
        try:
            self.settings[key] = logic.validate_setting(key, payload.get("value"))
        except logic.InvalidSetting as err:
            raise FamilyError(err.key, **err.params) from err

    # ---- Exports -------------------------------------------------------------------

    def state_json(
        self, family_name: str, now: datetime, child_id: str | None = None
    ) -> dict[str, Any]:
        """The current state for the app (Del H1), calculated by HA - no history.

        With `child_id` (a child's tablet) only that child's own data;
        otherwise all children plus what the parent part needs: the approval
        list, the full task list for editing and the settings.
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
                    # Session 3a adds the child's lock status here.
                }
                for child in children
            ],
        }
        if child_id is not None:
            return state
        state["approvals"] = [
            {key: value for key, value in self.completion_json(c).items() if key != "message"}
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
    ) -> dict[str, Any]:
        """One page of history: the 30 days before `before` (exclusive), newest
        first. `nextBefore` is the `before` of the next (older) page, or `None`
        when nothing older exists."""
        start = before - timedelta(days=HISTORY_PAGE_DAYS)
        items = [
            item
            for item in self._history_items()
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

    def _history_items(self) -> list[dict[str, Any]]:
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
                    "note": None,
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
        # Session 3a: locks are added here as type "lock".
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
            children.append(
                {
                    "id": child["id"],
                    "name": child["name"],
                    "balanceOre": self.balance_ore(child["id"]),
                    "earnedThisWeekOre": self.earned_this_week_ore(child["id"], now),
                    **self.follow_up(child["id"], now, language),
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
