"""Tidspunkter fra familiens indstillinger - kan rettes direkte fra HA."""

from __future__ import annotations

from datetime import time

from homeassistant.components.time import TimeEntity
from homeassistant.const import EntityCategory
from homeassistant.core import HomeAssistant
from homeassistant.exceptions import HomeAssistantError
from homeassistant.helpers.entity_platform import AddConfigEntryEntitiesCallback


from .coordinator import LommepengeConfigEntry, LommepengeCoordinator, LommepengeError
from .entity import LommepengeEntity

# HA-nøgle -> appens indstillingsnøgle (se FamilySettings i appen).
TIME_SETTINGS = {
    "default_due_time": "defaultDueTime",
    "restriction_start": "restrictionStart",
    "restriction_end": "restrictionEnd",
}


async def async_setup_entry(
    hass: HomeAssistant,
    entry: LommepengeConfigEntry,
    async_add_entities: AddConfigEntryEntitiesCallback,
) -> None:
    coordinator = entry.runtime_data.coordinator
    async_add_entities(
        SettingTime(coordinator, key, setting) for key, setting in TIME_SETTINGS.items()
    )


class SettingTime(LommepengeEntity, TimeEntity):
    _attr_entity_category = EntityCategory.CONFIG
    _attr_icon = "mdi:clock-outline"

    def __init__(self, coordinator: LommepengeCoordinator, key: str, setting: str) -> None:
        super().__init__(coordinator, key)
        self._setting = setting

    @property
    def native_value(self) -> time | None:
        value = self.coordinator.settings.get(self._setting)
        if not isinstance(value, str):
            return None
        try:
            hours, minutes = (int(part) for part in value.split(":"))
            return time(hours, minutes)
        except ValueError:
            return None

    async def async_set_value(self, value: time) -> None:
        try:
            await self.coordinator.async_action(
                "set_setting",
                {"key": self._setting, "value": f"{value.hour:02d}:{value.minute:02d}"},
            )
        except LommepengeError as err:
            raise HomeAssistantError(f"Lommepenge: {err}") from err
