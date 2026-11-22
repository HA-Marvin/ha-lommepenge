"""Overblik til entiteter og hændelser - beregnes af HA selv."""

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

# Bruges af entiteterne; samme navn som før for at holde dem enkle.
LommepengeError = FamilyError


class LommepengeCoordinator(DataUpdateCoordinator[dict[str, Any]]):
    """Genberegner overblikket hvert 30. sekund (frister passerer) og
    straks efter hver handling. Sender `lommepenge_event` ved nye eller
    afgjorte godkendelser og ændret spærring."""

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
        return self._compute()

    @callback
    def async_refresh_now(self) -> None:
        """Efter en handling: nyt overblik og hændelser med det samme."""
        self.async_set_updated_data(self._compute())

    @callback
    def _compute(self) -> dict[str, Any]:
        family = self.runtime.family
        summary = family.summary(self.runtime.family_name, local_now())
        self._fire_events(summary)
        return summary

    @callback
    def _fire_events(self, summary: dict[str, Any]) -> None:
        pending = {p["completionId"]: p for p in summary["pending"]}
        restricted = {c["id"]: c for c in summary["children"]}
        if self._last_pending is None:
            # Første beregning efter opstart er udgangspunktet - ingen
            # hændelser for det, der allerede ventede.
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
                    **family.completion_json(completion),
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
        """Handling fra HA selv (entitet eller service)."""
        await self.runtime.async_apply({"type": action_type, "payload": payload})

    # ---- Opslag brugt af entiteter ----------------------------------------

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
