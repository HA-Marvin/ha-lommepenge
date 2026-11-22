"""Numbers from the family's settings - can be changed directly from HA."""

from __future__ import annotations

from dataclasses import dataclass

from homeassistant.components.number import NumberEntity, NumberMode
from homeassistant.const import EntityCategory, UnitOfTime
from homeassistant.core import HomeAssistant
from homeassistant.exceptions import HomeAssistantError
from homeassistant.helpers.entity_platform import AddConfigEntryEntitiesCallback


from .coordinator import LommepengeConfigEntry, LommepengeCoordinator, LommepengeError
from .entity import LommepengeEntity


@dataclass(frozen=True)
class NumberSetting:
    key: str
    setting: str  # the app's setting key (see FamilySettings in the app)
    minimum: int
    maximum: int
    unit: str | None
    icon: str


# The limits must match the app's validation in FamilySettings.withValue.
NUMBER_SETTINGS = (
    NumberSetting("late_pause_minutes", "latePauseMinutes", 0, 240, UnitOfTime.MINUTES, "mdi:timer-sand"),
    NumberSetting("warning_minutes", "warningMinutes", 0, 600, UnitOfTime.MINUTES, "mdi:alarm"),
    NumberSetting("winter_from_week", "winterFromWeek", 1, 53, None, "mdi:snowflake"),
    NumberSetting("winter_to_week", "winterToWeek", 1, 53, None, "mdi:white-balance-sunny"),
)


async def async_setup_entry(
    hass: HomeAssistant,
    entry: LommepengeConfigEntry,
    async_add_entities: AddConfigEntryEntitiesCallback,
) -> None:
    coordinator = entry.runtime_data.coordinator
    async_add_entities(SettingNumber(coordinator, s) for s in NUMBER_SETTINGS)


class SettingNumber(LommepengeEntity, NumberEntity):
    _attr_entity_category = EntityCategory.CONFIG
    _attr_mode = NumberMode.BOX
    _attr_native_step = 1

    def __init__(self, coordinator: LommepengeCoordinator, setting: NumberSetting) -> None:
        super().__init__(coordinator, setting.key)
        self._setting = setting
        self._attr_native_min_value = setting.minimum
        self._attr_native_max_value = setting.maximum
        self._attr_native_unit_of_measurement = setting.unit
        self._attr_icon = setting.icon

    @property
    def native_value(self) -> float | None:
        value = self.coordinator.settings.get(self._setting.setting)
        return float(value) if isinstance(value, (int, float)) else None

    async def async_set_native_value(self, value: float) -> None:
        try:
            await self.coordinator.async_action(
                "set_setting", {"key": self._setting.setting, "value": int(value)}
            )
        except LommepengeError as err:
            language = self.coordinator.runtime.language
            raise HomeAssistantError(f"Lommepenge: {err.translate(language)}") from err
