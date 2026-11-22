"""Sensorer: saldo pr. barn og opgaver der venter på godkendelse."""

from __future__ import annotations

from typing import Any

from homeassistant.components.sensor import SensorDeviceClass, SensorEntity, SensorStateClass
from homeassistant.core import HomeAssistant
from homeassistant.helpers.entity_platform import AddEntitiesCallback

from .coordinator import LommepengeConfigEntry, LommepengeCoordinator
from .entity import LommepengeChildEntity, LommepengeEntity, async_setup_child_entities


async def async_setup_entry(
    hass: HomeAssistant,
    entry: LommepengeConfigEntry,
    async_add_entities: AddEntitiesCallback,
) -> None:
    coordinator = entry.runtime_data
    async_add_entities([PendingApprovalsSensor(coordinator)])
    async_setup_child_entities(
        coordinator,
        async_add_entities,
        lambda child_id: [
            KronerSensor(coordinator, child_id, "balance", "balanceOre"),
            KronerSensor(coordinator, child_id, "earned_this_week", "earnedThisWeekOre"),
        ],
    )


class PendingApprovalsSensor(LommepengeEntity, SensorEntity):
    """Antal opgaver der venter på en forælders godkendelse."""

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
                    "amount_kr": (p.get("amountOre") or 0) / 100,
                    "completed_at": p.get("completedAt"),
                    "late": p.get("late", False),
                }
                for p in self.coordinator.pending
            ]
        }


class KronerSensor(LommepengeChildEntity, SensorEntity):
    """Et beløb for ét barn (appen regner i øre)."""

    _attr_device_class = SensorDeviceClass.MONETARY
    _attr_native_unit_of_measurement = "DKK"
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

    @property
    def native_value(self) -> float | None:
        child = self.child
        if child is None or child.get(self._field) is None:
            return None
        return child[self._field] / 100
