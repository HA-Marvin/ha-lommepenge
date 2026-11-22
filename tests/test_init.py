"""Tests for entiteter, services, webhook og genparring."""

from __future__ import annotations

from homeassistant.config_entries import ConfigEntryState
from homeassistant.core import HomeAssistant
from homeassistant.helpers import device_registry as dr, entity_registry as er
from pytest_homeassistant_custom_component.common import async_capture_events
from pytest_homeassistant_custom_component.test_util.aiohttp import AiohttpClientMocker

from custom_components.lommepenge.const import DOMAIN, EVENT_LOMMEPENGE

from .conftest import BASE, SCREEN_ID, WEBHOOK_ID


def _entity_id(hass: HomeAssistant, platform: str, unique_id: str) -> str:
    entity_id = er.async_get(hass).async_get_entity_id(platform, DOMAIN, unique_id)
    assert entity_id, f"Ingen {platform} med unique_id {unique_id}"
    return entity_id


def _action_calls(aioclient_mock: AiohttpClientMocker) -> list[dict]:
    return [c[2] for c in aioclient_mock.mock_calls if str(c[1]).endswith("/ha/action")]


async def test_entities(hass: HomeAssistant, setup_integration) -> None:
    assert setup_integration.state is ConfigEntryState.LOADED

    balance = hass.states.get(_entity_id(hass, "sensor", f"{SCREEN_ID}_emma_balance"))
    assert float(balance.state) == 12.5
    assert balance.attributes["unit_of_measurement"] == "DKK"

    restricted = hass.states.get(
        _entity_id(hass, "binary_sensor", f"{SCREEN_ID}_emma_restricted")
    )
    assert restricted.state == "on"
    assert restricted.attributes["child_id"] == "emma"
    assert restricted.attributes["overdue"] == [{"task": "Tøm opvaskeren", "due": "18:00"}]

    oskar = hass.states.get(_entity_id(hass, "binary_sensor", f"{SCREEN_ID}_oskar_restricted"))
    assert oskar.state == "off"

    pending = hass.states.get(_entity_id(hass, "sensor", f"{SCREEN_ID}_pending_approvals"))
    assert pending.state == "1"
    assert pending.attributes["pending"][0]["completion_id"] == "c-1"

    due = hass.states.get(_entity_id(hass, "time", f"{SCREEN_ID}_default_due_time"))
    assert due.state == "18:00:00"
    pause = hass.states.get(_entity_id(hass, "number", f"{SCREEN_ID}_late_pause_minutes"))
    assert float(pause.state) == 10


async def test_webhook_url_is_registered(
    hass: HomeAssistant, setup_integration, aioclient_mock: AiohttpClientMocker
) -> None:
    calls = [c[2] for c in aioclient_mock.mock_calls if str(c[1]).endswith("/ha/webhook")]
    assert calls == [{"url": f"http://10.0.0.2:8123/api/webhook/{WEBHOOK_ID}"}]


async def test_approve_service(
    hass: HomeAssistant, setup_integration, aioclient_mock: AiohttpClientMocker
) -> None:
    await hass.services.async_call(
        DOMAIN, "approve", {"completion_id": "c-1"}, blocking=True
    )
    assert _action_calls(aioclient_mock)[-1] == {
        "type": "approve_completion",
        "payload": {"completionId": "c-1"},
    }


async def test_reject_and_suspend_services(
    hass: HomeAssistant, setup_integration, aioclient_mock: AiohttpClientMocker
) -> None:
    await hass.services.async_call(DOMAIN, "reject", {"completion_id": "c-1"}, blocking=True)
    await hass.services.async_call(
        DOMAIN, "suspend_restriction", {"child_id": "emma"}, blocking=True
    )
    assert _action_calls(aioclient_mock)[-2:] == [
        {"type": "reject_completion", "payload": {"completionId": "c-1"}},
        {"type": "suspend_restriction", "payload": {"childId": "emma"}},
    ]


async def test_suspend_button(
    hass: HomeAssistant, setup_integration, aioclient_mock: AiohttpClientMocker
) -> None:
    button = _entity_id(hass, "button", f"{SCREEN_ID}_emma_suspend_restriction")
    await hass.services.async_call("button", "press", {"entity_id": button}, blocking=True)
    assert _action_calls(aioclient_mock)[-1] == {
        "type": "suspend_restriction",
        "payload": {"childId": "emma"},
    }


async def test_settings_can_be_changed_from_ha(
    hass: HomeAssistant, setup_integration, aioclient_mock: AiohttpClientMocker
) -> None:
    due = _entity_id(hass, "time", f"{SCREEN_ID}_default_due_time")
    await hass.services.async_call(
        "time", "set_value", {"entity_id": due, "time": "17:30:00"}, blocking=True
    )
    pause = _entity_id(hass, "number", f"{SCREEN_ID}_late_pause_minutes")
    await hass.services.async_call(
        "number", "set_value", {"entity_id": pause, "value": 15}, blocking=True
    )
    assert _action_calls(aioclient_mock)[-2:] == [
        {"type": "set_setting", "payload": {"key": "defaultDueTime", "value": "17:30"}},
        {"type": "set_setting", "payload": {"key": "latePauseMinutes", "value": 15}},
    ]


async def test_webhook_fires_event(
    hass: HomeAssistant, setup_integration, hass_client_no_auth
) -> None:
    events = async_capture_events(hass, EVENT_LOMMEPENGE)
    client = await hass_client_no_auth()
    response = await client.post(
        f"/api/webhook/{WEBHOOK_ID}",
        json={"event": "completion_pending", "completionId": "c-2", "childName": "Emma"},
    )
    assert response.status == 200
    await hass.async_block_till_done()
    assert len(events) == 1
    assert events[0].data["event"] == "completion_pending"
    assert events[0].data["completionId"] == "c-2"
    assert events[0].data["config_entry_id"] == setup_integration.entry_id


async def test_revoked_token_starts_reauth(
    hass: HomeAssistant, config_entry, aioclient_mock: AiohttpClientMocker
) -> None:
    aioclient_mock.get(f"{BASE}/ha/summary", status=401, json={"error": "Ugyldig"})
    config_entry.add_to_hass(hass)
    await hass.config_entries.async_setup(config_entry.entry_id)
    await hass.async_block_till_done()

    assert config_entry.state is ConfigEntryState.SETUP_ERROR
    flows = hass.config_entries.flow.async_progress()
    assert any(f["context"]["source"] == "reauth" for f in flows)


async def test_new_child_gets_entities(
    hass: HomeAssistant,
    setup_integration,
    aioclient_mock: AiohttpClientMocker,
    summary,
) -> None:
    summary["children"].append({**summary["children"][1], "id": "bella", "name": "Bella"})
    aioclient_mock.clear_requests()
    aioclient_mock.get(f"{BASE}/ha/summary", json=summary)
    await setup_integration.runtime_data.async_refresh()
    await hass.async_block_till_done()

    _entity_id(hass, "binary_sensor", f"{SCREEN_ID}_bella_restricted")


async def test_renamed_and_deleted_children_follow_the_app(
    hass: HomeAssistant,
    setup_integration,
    aioclient_mock: AiohttpClientMocker,
    summary,
) -> None:
    dev_reg = dr.async_get(hass)
    emma = dev_reg.async_get_device(identifiers={(DOMAIN, f"{SCREEN_ID}_emma")})
    oskar_entity = _entity_id(hass, "binary_sensor", f"{SCREEN_ID}_oskar_restricted")
    assert emma.name == "Lommepenge Emma"

    summary["children"][0]["name"] = "Emilie"
    del summary["children"][1]
    aioclient_mock.clear_requests()
    aioclient_mock.get(f"{BASE}/ha/summary", json=summary)
    await setup_integration.runtime_data.async_refresh()
    await hass.async_block_till_done()

    assert dev_reg.async_get(emma.id).name == "Lommepenge Emilie"
    assert dev_reg.async_get_device(identifiers={(DOMAIN, f"{SCREEN_ID}_oskar")}) is None
    assert er.async_get(hass).async_get(oskar_entity) is None
    # Skærmens egen enhed bliver stående.
    assert dev_reg.async_get_device(identifiers={(DOMAIN, SCREEN_ID)}) is not None


async def test_no_children_gives_only_screen_device(
    hass: HomeAssistant,
    config_entry,
    aioclient_mock: AiohttpClientMocker,
    summary,
) -> None:
    summary["children"] = []
    summary["pending"] = []
    aioclient_mock.get(f"{BASE}/ha/summary", json=summary)
    aioclient_mock.post(f"{BASE}/ha/webhook", json={"ok": True})
    config_entry.add_to_hass(hass)
    assert await hass.config_entries.async_setup(config_entry.entry_id)
    await hass.async_block_till_done()

    devices = dr.async_entries_for_config_entry(dr.async_get(hass), config_entry.entry_id)
    assert [d.identifiers for d in devices] == [{(DOMAIN, SCREEN_ID)}]


async def test_unload(hass: HomeAssistant, setup_integration) -> None:
    assert await hass.config_entries.async_unload(setup_integration.entry_id)
    assert setup_integration.state is ConfigEntryState.NOT_LOADED
