"""Entities, services, events, saving and migration."""

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

from custom_components.lommepenge.config_flow import hash_pin
from custom_components.lommepenge.const import (
    CONF_FAMILY_NAME,
    CONF_LANGUAGE,
    DOMAIN,
    EVENT_LOMMEPENGE,
)

from .conftest import PIN, add_child, family_entry, setup_entry


def _entity_id(hass: HomeAssistant, platform: str, unique_id: str) -> str:
    entity_id = er.async_get(hass).async_get_entity_id(platform, DOMAIN, unique_id)
    assert entity_id, f"No {platform} with unique_id {unique_id}"
    return entity_id


async def _family_with_task(hass: HomeAssistant, entry: MockConfigEntry):
    runtime = await setup_entry(hass, entry)
    await add_child(runtime, "emma", "Emma")
    await runtime.async_apply(
        {
            "type": "create_task",
            "payload": {
                "id": "t1",
                "title": "Empty the dishwasher",
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

    # The deadline passes: restricted, without anyone doing anything.
    freezer.move_to("2026-11-23 18:05:00+01:00")
    async_fire_time_changed(hass)
    await hass.async_block_till_done()
    state = hass.states.get(restricted_id)
    assert state.state == "on"
    assert state.attributes["reason"] == "Missing: Empty the dishwasher (due 18:00)"
    assert [e.data["event"] for e in events] == ["restriction_changed"]

    # The child marks it as done (late): awaiting approval + pause.
    completion = await runtime.async_apply(
        {"type": "complete_task", "payload": {"taskId": "t1", "childId": "emma"}}
    )
    await hass.async_block_till_done()
    pending_event = events[-1]
    assert pending_event.data["event"] == "completion_pending"
    assert pending_event.data["childName"] == "Emma"
    assert pending_event.data["taskTitle"] == "Empty the dishwasher"
    assert pending_event.data["late"] is True
    assert pending_event.data["message"] == 'Emma did "Empty the dishwasher" – 5 DKK (late)'
    assert pending_event.data["config_entry_id"] == entry_id
    pending_id = _entity_id(hass, "sensor", f"{entry_id}_pending_approvals")
    assert hass.states.get(pending_id).state == "1"
    assert hass.states.get(restricted_id).state == "on"  # pause

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
    assert hass.states.get(balance_id).attributes["unit_of_measurement"] == "DKK"


async def test_texts_follow_the_chosen_language(hass: HomeAssistant, freezer) -> None:
    """HA itself runs in English, but the family chose Spanish and euro: the
    entity names, texts and amounts follow the integration, not HA."""
    freezer.move_to("2026-11-23 19:00:00+01:00")
    await hass.config.async_set_time_zone("Europe/Copenhagen")
    assert hass.config.language == "en"
    entry = family_entry("es", "€")
    await _family_with_task(hass, entry)
    restricted_id = _entity_id(hass, "binary_sensor", f"{entry.entry_id}_emma_restricted")
    restricted = hass.states.get(restricted_id)
    assert restricted.attributes["reason"] == "Falta: Empty the dishwasher (límite 18:00)"
    assert restricted.attributes["friendly_name"] == "Lommepenge Emma Tableta bloqueada"
    balance = hass.states.get(_entity_id(hass, "sensor", f"{entry.entry_id}_emma_balance"))
    assert balance.attributes["friendly_name"] == "Lommepenge Emma Saldo"
    assert balance.attributes["unit_of_measurement"] == "€"
    pending = hass.states.get(_entity_id(hass, "sensor", f"{entry.entry_id}_pending_approvals"))
    assert pending.attributes["friendly_name"] == "The Family Pendiente de aprobación"
    device = dr.async_get(hass).async_get_device(identifiers={(DOMAIN, entry.entry_id)})
    assert device.model == "Familia"


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
    # No children: only the family's own device.
    devices = dr.async_entries_for_config_entry(dev_reg, config_entry.entry_id)
    assert [d.identifiers for d in devices] == [{(DOMAIN, config_entry.entry_id)}]

    await add_child(runtime, "emma", "Emma")
    await hass.async_block_till_done()
    identifier = (DOMAIN, f"{config_entry.entry_id}_emma")
    assert dev_reg.async_get_device(identifiers={identifier}).name == "Lommepenge Emma"

    await runtime.async_apply({"type": "rename_child", "payload": {"id": "emma", "name": "Emily"}})
    await hass.async_block_till_done()
    assert dev_reg.async_get_device(identifiers={identifier}).name == "Lommepenge Emily"

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


async def test_existing_install_keeps_danish(hass: HomeAssistant) -> None:
    """Installations from before the language choice (2.1) were Danish-only."""
    old = MockConfigEntry(
        domain=DOMAIN,
        version=2,
        minor_version=1,
        title="Familien",
        data={CONF_FAMILY_NAME: "Familien", **hash_pin(PIN)},
    )
    runtime = await setup_entry(hass, old)
    assert old.minor_version == 2
    assert old.data[CONF_LANGUAGE] == "da"
    assert runtime.language == "da"


async def test_old_version_asks_for_new_setup(hass: HomeAssistant) -> None:
    old = MockConfigEntry(domain=DOMAIN, version=1, data={"host": "192.168.1.50"})
    old.add_to_hass(hass)
    assert not await hass.config_entries.async_setup(old.entry_id)
    assert old.state is ConfigEntryState.MIGRATION_ERROR


def test_now_is_naive_local() -> None:
    from custom_components.lommepenge.runtime import local_now

    assert isinstance(local_now(), datetime) and local_now().tzinfo is None


async def test_old_storage_is_migrated(
    hass: HomeAssistant, config_entry: MockConfigEntry, hass_storage, freezer
) -> None:
    """Storage 1.1 (before Del H) -> 1.2: completions get their occurrence day."""
    freezer.move_to("2026-11-23 12:00:00+01:00")
    await hass.config.async_set_time_zone("Europe/Copenhagen")
    hass_storage[f"{DOMAIN}.{config_entry.entry_id}"] = {
        "version": 1,
        "key": f"{DOMAIN}.{config_entry.entry_id}",
        "data": {
            "family": {
                "children": [
                    {"id": "emma", "name": "Emma", "sortOrder": 0,
                     "createdAt": "2026-01-01T10:00:00.000"}
                ],
                "tasks": [
                    {"id": "t1", "title": "Tidy up", "amountOre": 300, "recurrence": "once",
                     "mandatory": True, "createdAt": "2026-10-01T10:00:00.000", "active": True}
                ],
                "completions": [
                    {"id": "c1", "taskId": "t1", "childId": "emma",
                     "completedAt": "2026-11-20T10:00:00.000", "status": "rejected",
                     "approvedAt": None, "amountAtCompletionOre": 300, "late": False}
                ],
                "balanceAdjustments": [],
                "paidOutOreByChild": {},
                "familySettings": {"defaultDueTime": "18:00"},
                "restrictionSuspensions": {},
            },
            "devices": {},
            "pairings": {},
        },
    }
    runtime = await setup_entry(hass, config_entry)
    family = runtime.family
    assert family.completion("c1")["occurrenceDate"] == "2026-11-20"
    # The old one-off task is still there (not missed for its old deadline).
    assert family.task("t1")["active"] is True
    assert family.task_entries("emma", datetime(2026, 11, 23, 12))[0]["status"] == "available"
    stored = hass_storage[f"{DOMAIN}.{config_entry.entry_id}"]
    assert stored["minor_version"] == 2


async def test_cleanup_runs_at_midnight(
    hass: HomeAssistant, config_entry: MockConfigEntry, freezer
) -> None:
    freezer.move_to("2026-11-23 16:00:00+01:00")
    await hass.config.async_set_time_zone("Europe/Copenhagen")
    runtime = await _family_with_task(hass, config_entry)
    assert runtime.family.data["missed"] == []

    freezer.move_to("2026-11-23 23:59:00+01:00")
    async_fire_time_changed(hass)
    await hass.async_block_till_done()
    assert runtime.family.data["missed"] == []

    freezer.move_to("2026-11-24 00:00:30+01:00")
    async_fire_time_changed(hass)
    await hass.async_block_till_done()
    missed = runtime.family.data["missed"]
    assert [(m["childId"], m["date"]) for m in missed] == [("emma", "2026-11-23")]
    entry = runtime.family.task_entries("emma", datetime(2026, 11, 24, 0, 1))[0]
    assert entry["date"] == "2026-11-24" and entry["status"] == "available"
