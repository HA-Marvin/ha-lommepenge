"""The family's data and actions - HA is the "source of truth".

A direct translation of the app's `TaskRepository`: the same actions
(`create_task`, `complete_task`, `approve_completion` ...) with the same
rules and error messages, and the same JSON shape as the app's sync
protocol, so the app can use HA's responses directly as its local cache.
"""

from __future__ import annotations

from datetime import datetime, timedelta
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
    }


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
        task = {
            "id": task_id,
            **self._task_fields(payload, None),
            "createdAt": logic.to_iso(now),
            "active": True,
        }
        # The same id twice (e.g. a repeated offline action) replaces.
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
        if (existing := self.completion(completion_id)) is not None:
            return existing  # the same action sent again (offline queue)
        task = self.task(_require_str(payload, "taskId", "missing_task"))
        if task is None or not task.get("active", True):
            raise FamilyError("task_not_found")
        if child_id not in self.resolved_child_ids(task):
            raise FamilyError("task_not_assigned")
        if (
            logic.compute_availability(task, self._completions_for(child_id, task["id"]), now)
            != logic.AVAILABLE
        ):
            raise FamilyError("task_not_available")
        # HA's clock decides the time (and thereby "late"), not the tablet's -
        # a child cannot cheat by setting the clock back.
        completion = {
            "id": completion_id,
            "taskId": task["id"],
            "childId": child_id,
            "completedAt": logic.to_iso(now),
            "status": "pending",
            "approvedAt": None,
            "amountAtCompletionOre": task["amountOre"],
            "late": logic.is_late(task, self.settings, now),
        }
        self.data["completions"].append(completion)
        return completion

    def _pending_completion(self, payload: dict[str, Any]) -> dict[str, Any]:
        completion = self.completion(_require_str(payload, "completionId", "missing_completion"))
        if completion is None:
            raise FamilyError("completion_not_found")
        if completion["status"] != "pending":
            raise FamilyError("completion_already_handled")
        return completion

    def _action_approve_completion(self, payload: dict[str, Any], now: datetime) -> dict[str, Any]:
        completion = self._pending_completion(payload)
        completion["status"] = "approved"
        completion["approvedAt"] = logic.to_iso(now)
        return completion

    def _action_reject_completion(self, payload: dict[str, Any], now: datetime) -> dict[str, Any]:
        completion = self._pending_completion(payload)
        completion["status"] = "rejected"
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
        child_id = self._existing_child_id(payload, "id")
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

    def state_json(self, family_name: str, now: datetime) -> dict[str, Any]:
        """All the family's data in the app's sync format (`getStateJson`)."""
        return {
            "deviceName": family_name,
            "familyName": family_name,
            "children": self.children,
            "tasks": self.data["tasks"],
            "completions": self.data["completions"],
            "balanceAdjustments": self.data["balanceAdjustments"],
            "totalPaidOutOre": 0,
            "paidOutOreByChild": self.data["paidOutOreByChild"],
            "familySettings": self.settings,
            "restrictionSuspensions": self.data["restrictionSuspensions"],
            "updatedAt": logic.to_iso(now),
        }

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
