"""Henter og deler overblikket fra køleskabsskærmen."""

from __future__ import annotations

import logging
from typing import Any

from homeassistant.config_entries import ConfigEntry
from homeassistant.core import HomeAssistant
from homeassistant.exceptions import ConfigEntryAuthFailed
from homeassistant.helpers.update_coordinator import DataUpdateCoordinator, UpdateFailed

from .api import InvalidAuth, LommepengeApi, LommepengeError
from .const import DOMAIN, SCAN_INTERVAL

_LOGGER = logging.getLogger(__name__)

type LommepengeConfigEntry = ConfigEntry[LommepengeCoordinator]


class LommepengeCoordinator(DataUpdateCoordinator[dict[str, Any]]):
    """Poller `/ha/summary` og opdateres med det samme ved webhook/handling."""

    config_entry: LommepengeConfigEntry

    def __init__(
        self,
        hass: HomeAssistant,
        entry: LommepengeConfigEntry,
        api: LommepengeApi,
    ) -> None:
        super().__init__(
            hass,
            _LOGGER,
            config_entry=entry,
            name=DOMAIN,
            update_interval=SCAN_INTERVAL,
        )
        self.api = api

    async def _async_update_data(self) -> dict[str, Any]:
        try:
            return await self.api.summary()
        except InvalidAuth as err:
            # Nøglen er tilbagekaldt i appen ("Afbryd forbindelsen") -
            # bed brugeren om PIN igen.
            raise ConfigEntryAuthFailed(str(err)) from err
        except LommepengeError as err:
            raise UpdateFailed(f"Køleskabsskærmen svarer ikke: {err}") from err

    async def async_action(self, action_type: str, payload: dict[str, Any]) -> None:
        """Udfører en handling på skærmen og bruger svaret som ny tilstand."""
        data = await self.api.action(action_type, payload)
        self.async_set_updated_data(data)

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
