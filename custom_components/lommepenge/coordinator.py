"""Overview for entities and events - calculated by HA itself."""

from __future__ import annotations

import logging
from typing import Any

from homeassistant.config_entries import ConfigEntry
from homeassistant.core import HomeAssistant, callback
from homeassistant.helpers.update_coordinator import DataUpdateCoordinator

from .const import DOMAIN, EVENT_LOMMEPENGE, FOLLOW_UP_INTERVAL
from .family import FamilyError
from .runtime import LommepengeRuntime, local_now

_LOGGER = logging.getLogger(__name__)

type LommepengeConfigEntry = ConfigEntry[LommepengeRuntime]

# Used by the entities; same name as before to keep them simple.
LommepengeError = FamilyError


class LommepengeCoordinator(DataUpdateCoordinator[dict[str, Any]]):
    """Recalculates the overview every 30 seconds (deadlines pass, locks run
    out) and right after every action. Fires `lommepenge_event` for new or
    decided approvals and for locks that start, end or are lifted."""

    config_entry: LommepengeConfigEntry

    def __init__(
        self, hass: HomeAssistant, entry: LommepengeConfigEntry, runtime: LommepengeRuntime
    ) -> None:
        super().__init__(
            hass,
            _LOGGER,
            config_entry=entry,
            name=DOMAIN,
            update_interval=FOLLOW_UP_INTERVAL,
            always_update=False,
        )
        self.runtime = runtime
        self._last_pending: dict[str, dict[str, Any]] | None = None

    async def _async_update_data(self) -> dict[str, Any]:
        # The midnight cleanup runs on the first update after midnight (and
        # catches up at startup if HA was down at midnight); then the locks,
        # pauses and notifications move on.
        await self.runtime.async_tick()
        return self._compute()

    @callback
    def async_refresh_now(self) -> None:
        """After an action: a new overview and events right away."""
        self.async_set_updated_data(self._compute())

    @callback
    def _compute(self) -> dict[str, Any]:
        family = self.runtime.family
        runtime = self.runtime
        summary = family.summary(
            runtime.family_name, local_now(), runtime.language, runtime.currency
        )
        self._fire_events(summary)
        return summary

    @callback
    def _fire_events(self, summary: dict[str, Any]) -> None:
        family = self.runtime.family
        pending = {p["completionId"]: p for p in summary["pending"]}
        # Lock events happen once (started, ended, lifted) - also right after
        # startup, e.g. a lock that ran out while HA was down.
        events: list[dict[str, Any]] = [
            self._lock_event(event) for event in family.pop_events()
        ]
        if self._last_pending is None:
            # The first calculation after startup is the baseline - no events
            # for what was already waiting.
            self._last_pending = pending
        for completion_id in pending.keys() - self._last_pending.keys():
            events.append({"event": "completion_pending", **pending[completion_id]})
        for completion_id in self._last_pending.keys() - pending.keys():
            completion = family.completion(completion_id)
            if completion is None:
                continue
            events.append(
                {
                    "event": "completion_approved"
                    if completion["status"] == "approved"
                    else "completion_rejected",
                    **family.completion_json(
                        completion, self.runtime.language, self.runtime.currency
                    ),
                }
            )

        self._last_pending = pending
        for event in events:
            self.hass.bus.async_fire(
                EVENT_LOMMEPENGE, {**event, "config_entry_id": self.config_entry.entry_id}
            )

    def _lock_event(self, event: dict[str, Any]) -> dict[str, Any]:
        """`lock_started`, `lock_ended` or `lock_lifted` with the lock's details;
        `reason` is in the integration's language."""
        family = self.runtime.family
        lock = next(lock for lock in family.data["locks"] if lock["id"] == event["lockId"])
        child = family.child(event["childId"]) or {}
        return {
            **event,
            "childName": child.get("name", ""),
            "reason": family.reason_text(lock["causes"], self.runtime.language),
            "minutes": lock.get("minutes"),
            "startedAt": lock.get("startedAt"),
            "endsAt": lock.get("endsAt"),
        }

    async def async_action(self, action_type: str, payload: dict[str, Any]) -> None:
        """An action from HA itself (entity or service)."""
        await self.runtime.async_apply({"type": action_type, "payload": payload})

    # ---- Lookups used by entities -------------------------------------------

    @property
    def children(self) -> list[dict[str, Any]]:
        return list((self.data or {}).get("children", []))

    def child(self, child_id: str) -> dict[str, Any] | None:
        for child in self.children:
            if child.get("id") == child_id:
                return child
        return None

    @property
    def pending(self) -> list[dict[str, Any]]:
        return list((self.data or {}).get("pending", []))

    @property
    def settings(self) -> dict[str, Any]:
        return dict((self.data or {}).get("settings", {}))
