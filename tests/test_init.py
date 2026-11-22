"""Entiteter, services, hændelser og gemning."""

from __future__ import annotations

from datetime import datetime

from homeassistant.config_entries import ConfigEntryState
from homeassistant.core import HomeAssistant
from homeassistant.helpers import device_registry as dr, entity_registry as er
from pytest_homeassistant_custom_component.common import (
    MockConfigEntry,
    async_capture_events,
    async_fire_time_changed,
)

from custom_components.lommepenge.const import DOMAIN, EVENT_LOMMEPENGE

from .conftest import add_child, setup_entry


def _entity_id(hass: HomeAssistant, platform: str, unique_id: str) -> str:
    entity_id = er.async_get(hass).async_get_entity_id(platform, DOMAIN, unique_id)
    assert entity_id, f"Ingen {platform} med unique_id {unique_id}"
    return entity_id


async def _family_with_task(hass: HomeAssistant, entry: MockConfigEntry):
    runtime = await setup_entry(hass, entry)
    await add_child(runtime, "emma", "Emma")
    await runtime.async_apply(
        {
            "type": "create_task",
            "payload": {
                "id": "t1",
                "title": "Tøm opvaskeren",
                "amountOre": 500,
                "recurrence": "daily",
                "mandatory": True,
            },
        }
    )
    await hass.async_block_till_done()
    return runtime


async def test_restriction_and_events(
    hass: HomeAssistant, config_entry: MockConfigEntry, freezer
) -> None:
    freezer.move_to("2026-11-23 16:00:00+01:00")
    await hass.config.async_set_time_zone("Europe/Copenhagen")
    runtime = await _family_with_task(hass, config_entry)
    events = async_capture_events(hass, EVENT_LOMMEPENGE)
    entry_id = config_entry.entry_id

    restricted_id = _entity_id(hass, "binary_sensor", f"{entry_id}_emma_restricted")
    assert hass.states.get(restricted_id).state == "off"

    # Fristen passerer: spærret, uden at nogen har gjort noget.
    freezer.move_to("2026-11-23 18:05:00+01:00")
    async_fire_time_changed(hass)
    await hass.async_block_till_done()
    state = hass.states.get(restricted_id)
    assert state.state == "on"
    assert state.attributes["reason"] == "Mangler: Tøm opvaskeren (frist 18:00)"
    assert [e.data["event"] for e in events] == ["restriction_changed"]

    # Barnet markerer udført (for sent): afventer godkendelse + pausetid.
    completion = await runtime.async_apply(
        {"type": "complete_task", "payload": {"taskId": "t1", "childId": "emma"}}
    )
    await hass.async_block_till_done()
    pending_event = events[-1]
    assert pending_event.data["event"] == "completion_pending"
    assert pending_event.data["childName"] == "Emma"
    assert pending_event.data["taskTitle"] == "Tøm opvaskeren"
    assert pending_event.data["late"] is True
    assert pending_event.data["config_entry_id"] == entry_id
    pending_id = _entity_id(hass, "sensor", f"{entry_id}_pending_approvals")
    assert hass.states.get(pending_id).state == "1"
    assert hass.states.get(restricted_id).state == "on"  # pausetid

    freezer.move_to("2026-11-23 18:16:00+01:00")
    async_fire_time_changed(hass)
    await hass.async_block_till_done()
    assert hass.states.get(restricted_id).state == "off"

    await hass.services.async_call(
        DOMAIN, "approve", {"completion_id": completion["id"]}, blocking=True
    )
    await hass.async_block_till_done()
    assert events[-1].data["event"] == "completion_approved"
    balance_id = _entity_id(hass, "sensor", f"{entry_id}_emma_balance")
    assert float(hass.states.get(balance_id).state) == 5.0


async def test_settings_and_suspend_from_ha(
    hass: HomeAssistant, config_entry: MockConfigEntry, freezer
) -> None:
    freezer.move_to("2026-11-23 19:00:00+01:00")
    await hass.config.async_set_time_zone("Europe/Copenhagen")
    runtime = await _family_with_task(hass, config_entry)
    entry_id = config_entry.entry_id

    restricted_id = _entity_id(hass, "binary_sensor", f"{entry_id}_emma_restricted")
    assert hass.states.get(restricted_id).state == "on"
    button = _entity_id(hass, "button", f"{entry_id}_emma_suspend_restriction")
    await hass.services.async_call("button", "press", {"entity_id": button}, blocking=True)
    await hass.async_block_till_done()
    assert hass.states.get(restricted_id).state == "off"

    due = _entity_id(hass, "time", f"{entry_id}_default_due_time")
    await hass.services.async_call(
        "time", "set_value", {"entity_id": due, "time": "17:15"}, blocking=True
    )
    pause = _entity_id(hass, "number", f"{entry_id}_late_pause_minutes")
    await hass.services.async_call(
        "number", "set_value", {"entity_id": pause, "value": 25}, blocking=True
    )
    assert runtime.family.settings["defaultDueTime"] == "17:15"
    assert runtime.family.settings["latePauseMinutes"] == 25


async def test_child_devices_follow_the_app(
    hass: HomeAssistant, config_entry: MockConfigEntry
) -> None:
    runtime = await setup_entry(hass, config_entry)
    dev_reg = dr.async_get(hass)
    # Ingen børn: kun familiens egen enhed.
    devices = dr.async_entries_for_config_entry(dev_reg, config_entry.entry_id)
    assert [d.identifiers for d in devices] == [{(DOMAIN, config_entry.entry_id)}]

    await add_child(runtime, "emma", "Emma")
    await hass.async_block_till_done()
    identifier = (DOMAIN, f"{config_entry.entry_id}_emma")
    assert dev_reg.async_get_device(identifiers={identifier}).name == "Lommepenge Emma"

    await runtime.async_apply({"type": "rename_child", "payload": {"id": "emma", "name": "Emilie"}})
    await hass.async_block_till_done()
    assert dev_reg.async_get_device(identifiers={identifier}).name == "Lommepenge Emilie"

    await runtime.async_apply({"type": "delete_child", "payload": {"id": "emma"}})
    await hass.async_block_till_done()
    assert dev_reg.async_get_device(identifiers={identifier}) is None


async def test_data_survives_restart(hass: HomeAssistant, config_entry: MockConfigEntry) -> None:
    runtime = await setup_entry(hass, config_entry)
    await add_child(runtime, "emma", "Emma")
    assert await hass.config_entries.async_reload(config_entry.entry_id)
    await hass.async_block_till_done()
    assert config_entry.runtime_data.family.child("emma")["name"] == "Emma"

    assert await hass.config_entries.async_unload(config_entry.entry_id)
    assert config_entry.state is ConfigEntryState.NOT_LOADED


async def test_old_version_asks_for_new_setup(hass: HomeAssistant) -> None:
    old = MockConfigEntry(domain=DOMAIN, version=1, data={"host": "192.168.1.50"})
    old.add_to_hass(hass)
    assert not await hass.config_entries.async_setup(old.entry_id)
    assert old.state is ConfigEntryState.MIGRATION_ERROR


def test_now_is_naive_local() -> None:
    from custom_components.lommepenge.runtime import local_now

    assert isinstance(local_now(), datetime) and local_now().tzinfo is None
