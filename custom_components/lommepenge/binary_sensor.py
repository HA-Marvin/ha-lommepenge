"""Binary sensors per child: restricted and overdue."""

from __future__ import annotations

from typing import Any

from homeassistant.components.binary_sensor import BinarySensorDeviceClass, BinarySensorEntity
from homeassistant.core import HomeAssistant
from homeassistant.helpers.entity_platform import AddConfigEntryEntitiesCallback

from .coordinator import LommepengeConfigEntry, LommepengeCoordinator
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
        lambda child_id: [
            RestrictedSensor(coordinator, child_id),
            OverdueSensor(coordinator, child_id),
        ],
    )


def _tasks(items: list[dict[str, Any]] | None) -> list[dict[str, Any]]:
    return [{"task": t.get("title"), "due": t.get("due")} for t in items or []]


class RestrictedSensor(LommepengeChildEntity, BinarySensorEntity):
    """On = the child's tablet should be restricted now (e.g. drive a UniFi rule)."""

    _attr_icon = "mdi:tablet-cellphone"

    def __init__(self, coordinator: LommepengeCoordinator, child_id: str) -> None:
        super().__init__(coordinator, child_id, "restricted")

    @property
    def is_on(self) -> bool | None:
        child = self.child
        return None if child is None else bool(child.get("restricted"))

    @property
    def extra_state_attributes(self) -> dict[str, Any]:
        child = self.child or {}
        return {
            "child_id": self.child_id,
            "child_name": child.get("name"),
            "reason": child.get("reason"),
            "overdue": _tasks(child.get("overdue")),
            "due_today": _tasks(child.get("dueToday")),
            "late_pause_until": child.get("latePauseUntil"),
            "suspended_today": child.get("suspended", False),
            "in_restriction_window": child.get("inWindow", False),
        }


class OverdueSensor(LommepengeChildEntity, BinarySensorEntity):
    """On = the child has a mandatory task whose deadline has passed."""

    _attr_device_class = BinarySensorDeviceClass.PROBLEM

    def __init__(self, coordinator: LommepengeCoordinator, child_id: str) -> None:
        super().__init__(coordinator, child_id, "overdue")

    @property
    def is_on(self) -> bool | None:
        child = self.child
        return None if child is None else bool(child.get("overdue"))

    @property
    def extra_state_attributes(self) -> dict[str, Any]:
        child = self.child or {}
        return {"child_id": self.child_id, "tasks": _tasks(child.get("overdue"))}
