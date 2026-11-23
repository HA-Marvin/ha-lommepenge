"""Switch per child: pause (Del H4) - no task is mandatory while it is on.

Turned on here, the pause has no end date; a pause with an end date is set
with the `lommepenge.pause` service or in the app.
"""

from __future__ import annotations

from typing import Any

from homeassistant.components.switch import SwitchEntity
from homeassistant.core import HomeAssistant
from homeassistant.exceptions import HomeAssistantError
from homeassistant.helpers.entity_platform import AddConfigEntryEntitiesCallback

from .coordinator import LommepengeConfigEntry, LommepengeCoordinator, LommepengeError
from .entity import LommepengeChildEntity, async_setup_child_entities


async def async_setup_entry(
    hass: HomeAssistant,
    entry: LommepengeConfigEntry,
    async_add_entities: AddConfigEntryEntitiesCallback,
) -> None:
    coordinator = entry.runtime_data.coordinator
    async_setup_child_entities(
        coordinator,
        async_add_entities,
        lambda child_id: [PauseSwitch(coordinator, child_id)],
    )


class PauseSwitch(LommepengeChildEntity, SwitchEntity):
    _attr_icon = "mdi:pause-circle-outline"

    def __init__(self, coordinator: LommepengeCoordinator, child_id: str) -> None:
        super().__init__(coordinator, child_id, "paused")

    @property
    def is_on(self) -> bool | None:
        child = self.child
        return None if child is None else bool(child.get("paused"))

    @property
    def extra_state_attributes(self) -> dict[str, Any]:
        child = self.child or {}
        return {"child_id": self.child_id, "paused_until": child.get("pausedUntil")}

    async def _set(self, paused: bool) -> None:
        try:
            await self.coordinator.async_action(
                "set_pause", {"childId": self.child_id, "paused": paused}
            )
        except LommepengeError as err:
            language = self.coordinator.runtime.language
            raise HomeAssistantError(f"Lommepenge: {err.translate(language)}") from err

    async def async_turn_on(self, **kwargs: Any) -> None:
        await self._set(True)

    async def async_turn_off(self, **kwargs: Any) -> None:
        await self._set(False)
