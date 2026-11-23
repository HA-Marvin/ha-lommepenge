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
    """Recalculates the overview every 30 seconds (deadlines pass) and right
    after every action. Fires `lommepenge_event` for new or decided approvals
    and changed restrictions."""

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
        self._last_restricted: dict[str, bool] = {}

    async def _async_update_data(self) -> dict[str, Any]:
        # The midnight cleanup runs on the first update after midnight (and
        # catches up at startup if HA was down at midnight).
        await self.runtime.async_cleanup()
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
        pending = {p["completionId"]: p for p in summary["pending"]}
        restricted = {c["id"]: c for c in summary["children"]}
        if self._last_pending is None:
            # The first calculation after startup is the baseline - no events
            # for what was already waiting.
            self._last_pending = pending
            self._last_restricted = {k: c["restricted"] for k, c in restricted.items()}
            return

        family = self.runtime.family
        events: list[dict[str, Any]] = []
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
        for child_id, child in restricted.items():
            if self._last_restricted.get(child_id, False) == child["restricted"]:
                continue
            events.append(
                {
                    "event": "restriction_changed",
                    "childId": child_id,
                    "childName": child["name"],
                    "restricted": child["restricted"],
                    "reason": child["reason"],
                }
            )

        self._last_pending = pending
        self._last_restricted = {k: c["restricted"] for k, c in restricted.items()}
        for event in events:
            self.hass.bus.async_fire(
                EVENT_LOMMEPENGE, {**event, "config_entry_id": self.config_entry.entry_id}
            )

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
