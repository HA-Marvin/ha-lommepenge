"""Sensors: balance per child, approvals waiting, and the devices' last contact."""

from __future__ import annotations

from datetime import datetime
from typing import Any

from homeassistant.components.sensor import SensorDeviceClass, SensorEntity, SensorStateClass
from homeassistant.config_entries import ConfigSubentry
from homeassistant.const import EntityCategory
from homeassistant.core import HomeAssistant
from homeassistant.helpers.entity_platform import AddConfigEntryEntitiesCallback
from homeassistant.util import dt as dt_util

from .coordinator import LommepengeConfigEntry, LommepengeCoordinator
from .entity import (
    LommepengeAppDeviceEntity,
    LommepengeChildEntity,
    LommepengeEntity,
    async_setup_app_device_entities,
    async_setup_child_entities,
)
from .runtime import LommepengeRuntime


async def async_setup_entry(
    hass: HomeAssistant,
    entry: LommepengeConfigEntry,
    async_add_entities: AddConfigEntryEntitiesCallback,
) -> None:
    coordinator = entry.runtime_data.coordinator
    async_add_entities([PendingApprovalsSensor(coordinator)])
    async_setup_child_entities(
        coordinator,
        async_add_entities,
        lambda child_id: [
            AmountSensor(coordinator, child_id, "balance", "balanceOre"),
            AmountSensor(coordinator, child_id, "earned_this_week", "earnedThisWeekOre"),
        ],
    )
    async_setup_app_device_entities(
        entry, async_add_entities, lambda subentry: [LastSeenSensor(entry.runtime_data, subentry)]
    )


class PendingApprovalsSensor(LommepengeEntity, SensorEntity):
    """Number of tasks waiting for a parent's approval."""

    _attr_state_class = SensorStateClass.MEASUREMENT
    _attr_icon = "mdi:clipboard-check-outline"

    def __init__(self, coordinator: LommepengeCoordinator) -> None:
        super().__init__(coordinator, "pending_approvals")

    @property
    def native_value(self) -> int:
        return len(self.coordinator.pending)

    @property
    def extra_state_attributes(self) -> dict[str, Any]:
        return {
            "pending": [
                {
                    "completion_id": p.get("completionId"),
                    "child_id": p.get("childId"),
                    "child_name": p.get("childName"),
                    "task": p.get("taskTitle"),
                    "amount": (p.get("amountOre") or 0) / 100,
                    "currency": self.coordinator.runtime.currency,
                    # Old name, kept for existing automations.
                    "amount_kr": (p.get("amountOre") or 0) / 100,
                    "completed_at": p.get("completedAt"),
                    "late": p.get("late", False),
                }
                for p in self.coordinator.pending
            ]
        }


class AmountSensor(LommepengeChildEntity, SensorEntity):
    """An amount for one child (the app counts in 1/100 of the currency),
    in the currency chosen for the integration."""

    _attr_device_class = SensorDeviceClass.MONETARY
    _attr_suggested_display_precision = 2

    def __init__(
        self,
        coordinator: LommepengeCoordinator,
        child_id: str,
        key: str,
        field: str,
    ) -> None:
        super().__init__(coordinator, child_id, key)
        self._field = field
        self._attr_native_unit_of_measurement = coordinator.runtime.currency

    @property
    def native_value(self) -> float | None:
        child = self.child
        if child is None or child.get(self._field) is None:
            return None
        return child[self._field] / 100


class LastSeenSensor(LommepengeAppDeviceEntity, SensorEntity):
    """When the device last fetched data from HA (empty = not paired yet)."""

    _attr_device_class = SensorDeviceClass.TIMESTAMP
    _attr_entity_category = EntityCategory.DIAGNOSTIC

    def __init__(self, runtime: LommepengeRuntime, subentry: ConfigSubentry) -> None:
        super().__init__(runtime, subentry, "last_seen")

    @property
    def native_value(self) -> datetime | None:
        device = self.device
        return dt_util.parse_datetime(device["lastSeen"]) if device else None
