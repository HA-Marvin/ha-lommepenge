"""Button per child: lift the lock (Del H4)."""

from __future__ import annotations

from homeassistant.components.button import ButtonEntity
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
        lambda child_id: [LiftLockButton(coordinator, child_id)],
    )


class LiftLockButton(LommepengeChildEntity, ButtonEntity):
    """Clears the child's pending and running lock. New causes can lock again."""

    _attr_icon = "mdi:lock-open-variant-outline"

    def __init__(self, coordinator: LommepengeCoordinator, child_id: str) -> None:
        super().__init__(coordinator, child_id, "lift_lock")

    async def async_press(self) -> None:
        try:
            await self.coordinator.async_action("lift_lock", {"childId": self.child_id})
        except LommepengeError as err:
            language = self.coordinator.runtime.language
            raise HomeAssistantError(f"Lommepenge: {err.translate(language)}") from err
