"""Binary sensors per child: restricted (a lock runs) and overdue."""

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
    """On = a lock is running for the child (Del H4) - drives e.g. a UniFi rule.

    A pending lock (waiting for the child to use the tablet) is off; the
    attribute `lock_status` shows it.
    """

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
        lock = child.get("lock") or {}
        return {
            "child_id": self.child_id,
            "child_name": child.get("name"),
            "lock_status": lock.get("status", "none"),
            "reason": lock.get("reason"),
            "started_at": lock.get("startedAt"),
            "ends_at": lock.get("endsAt"),
            "pending_since": lock.get("pendingSince"),
            "paused": child.get("paused", False),
            "overdue": _tasks(child.get("overdue")),
            "due_today": _tasks(child.get("dueToday")),
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
