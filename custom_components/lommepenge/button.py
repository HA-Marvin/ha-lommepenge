"""Knap pr. barn: ophæv spærringen for resten af i dag."""

from __future__ import annotations

from homeassistant.components.button import ButtonEntity
from homeassistant.core import HomeAssistant
from homeassistant.exceptions import HomeAssistantError
from homeassistant.helpers.entity_platform import AddEntitiesCallback

from .api import LommepengeError
from .coordinator import LommepengeConfigEntry, LommepengeCoordinator
from .entity import LommepengeChildEntity, async_setup_child_entities


async def async_setup_entry(
    hass: HomeAssistant,
    entry: LommepengeConfigEntry,
    async_add_entities: AddEntitiesCallback,
) -> None:
    coordinator = entry.runtime_data
    async_setup_child_entities(
        coordinator,
        async_add_entities,
        lambda child_id: [SuspendRestrictionButton(coordinator, child_id)],
    )


class SuspendRestrictionButton(LommepengeChildEntity, ButtonEntity):
    _attr_icon = "mdi:lock-open-variant-outline"

    def __init__(self, coordinator: LommepengeCoordinator, child_id: str) -> None:
        super().__init__(coordinator, child_id, "suspend_restriction")

    async def async_press(self) -> None:
        try:
            await self.coordinator.async_action(
                "suspend_restriction", {"childId": self.child_id}
            )
        except LommepengeError as err:
            raise HomeAssistantError(f"Lommepenge: {err}") from err
