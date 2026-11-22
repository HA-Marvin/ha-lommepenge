"""Setup, settings and "Add device"."""

from __future__ import annotations

import hashlib

from homeassistant import config_entries
from homeassistant.core import HomeAssistant
from homeassistant.data_entry_flow import FlowResultType
from pytest_homeassistant_custom_component.common import MockConfigEntry
from pytest_homeassistant_custom_component.test_util.aiohttp import AiohttpClientMocker

from custom_components.lommepenge.const import (
    CONF_CHILD_ID,
    CONF_CURRENCY,
    CONF_DEVICE_ID,
    CONF_FAMILY_NAME,
    CONF_GITHUB_REPO,
    CONF_GITHUB_TOKEN,
    CONF_LANGUAGE,
    CONF_NAME,
    CONF_PIN,
    CONF_PIN_HASH,
    CONF_PIN_SALT,
    CONF_ROLE,
    DOMAIN,
    ROLE_CHILD,
    ROLE_SCREEN,
    SUBENTRY_DEVICE,
)

from .conftest import GITHUB, AppClient, add_child, setup_entry


async def test_user_flow(hass: HomeAssistant) -> None:
    result = await hass.config_entries.flow.async_init(
        DOMAIN, context={"source": config_entries.SOURCE_USER}
    )
    result = await hass.config_entries.flow.async_configure(
        result["flow_id"], {CONF_FAMILY_NAME: "Smith", CONF_PIN: "12"}
    )
    assert result["errors"] == {CONF_PIN: "invalid_pin"}

    result = await hass.config_entries.flow.async_configure(
        result["flow_id"], {CONF_FAMILY_NAME: "Smith", CONF_PIN: "2468"}
    )
    assert result["type"] is FlowResultType.CREATE_ENTRY
    data = result["data"]
    assert result["title"] == "Smith"
    # Only salt + hash are stored - in the same form as the app checks the PIN.
    assert CONF_PIN not in data
    assert data[CONF_PIN_HASH] == hashlib.sha256(f"{data[CONF_PIN_SALT]}:2468".encode()).hexdigest()
    # English and DKK unless something else is chosen.
    assert data[CONF_LANGUAGE] == "en"
    assert data[CONF_CURRENCY] == "DKK"

    # Only one family per HA.
    result = await hass.config_entries.flow.async_init(
        DOMAIN, context={"source": config_entries.SOURCE_USER}
    )
    assert result["type"] is FlowResultType.ABORT


async def test_user_flow_with_language_and_currency(hass: HomeAssistant) -> None:
    result = await hass.config_entries.flow.async_init(
        DOMAIN, context={"source": config_entries.SOURCE_USER}
    )
    base = {CONF_FAMILY_NAME: "Müller", CONF_PIN: "2468", CONF_LANGUAGE: "de"}
    result = await hass.config_entries.flow.async_configure(
        result["flow_id"], {**base, CONF_CURRENCY: "   "}
    )
    assert result["errors"] == {CONF_CURRENCY: "invalid_currency"}
    result = await hass.config_entries.flow.async_configure(
        result["flow_id"], {**base, CONF_CURRENCY: " € "}
    )
    assert result["type"] is FlowResultType.CREATE_ENTRY
    assert result["data"][CONF_LANGUAGE] == "de"
    assert result["data"][CONF_CURRENCY] == "€"


async def test_options_validate_github_token(
    hass: HomeAssistant, config_entry: MockConfigEntry, aioclient_mock: AiohttpClientMocker
) -> None:
    await setup_entry(hass, config_entry)
    repo = "https://api.github.com/repos/HA-Marvin/lommepenge-app"
    aioclient_mock.get(repo, status=401)

    result = await hass.config_entries.options.async_init(config_entry.entry_id)
    result = await hass.config_entries.options.async_configure(
        result["flow_id"],
        {CONF_GITHUB_TOKEN: "wrong", CONF_GITHUB_REPO: "HA-Marvin/lommepenge-app"},
    )
    assert result["errors"] == {CONF_GITHUB_TOKEN: "invalid_token"}

    aioclient_mock.clear_requests()
    aioclient_mock.get(repo, json={"full_name": "HA-Marvin/lommepenge-app"})
    aioclient_mock.get(f"{repo}/releases/latest", status=404)
    aioclient_mock.get(f"{GITHUB}/releases/latest", status=404)
    old_hash = config_entry.data[CONF_PIN_HASH]
    result = await hass.config_entries.options.async_configure(
        result["flow_id"],
        {
            CONF_GITHUB_TOKEN: "ghp_ok",
            CONF_GITHUB_REPO: "HA-Marvin/lommepenge-app",
            CONF_PIN: "9999",
            CONF_LANGUAGE: "fr",
            CONF_CURRENCY: "EUR",
        },
    )
    assert result["type"] is FlowResultType.CREATE_ENTRY
    await hass.async_block_till_done()
    assert config_entry.options[CONF_GITHUB_TOKEN] == "ghp_ok"
    assert config_entry.data[CONF_PIN_HASH] != old_hash
    assert config_entry.data[CONF_LANGUAGE] == "fr"
    assert config_entry.runtime_data.language == "fr"
    assert config_entry.data[CONF_CURRENCY] == "EUR"
    assert config_entry.runtime_data.currency == "EUR"


async def _start_device_flow(hass: HomeAssistant, entry: MockConfigEntry, name: str, role: str):
    result = await hass.config_entries.subentries.async_init(
        (entry.entry_id, SUBENTRY_DEVICE), context={"source": config_entries.SOURCE_USER}
    )
    assert result["step_id"] == "user"
    return await hass.config_entries.subentries.async_configure(
        result["flow_id"], {CONF_NAME: name, CONF_ROLE: role}
    )


async def test_add_screen_device(
    hass: HomeAssistant, config_entry: MockConfigEntry, hass_client_no_auth
) -> None:
    await setup_entry(hass, config_entry)
    result = await _start_device_flow(hass, config_entry, "Kitchen", ROLE_SCREEN)
    assert result["step_id"] == "pair"
    placeholders = result["description_placeholders"]
    # The dialog shows the code and a link to the page with app download and QR code.
    token = placeholders["code"]
    assert len(token) == 8
    assert placeholders["install_url"].startswith("http://")
    assert placeholders["install_url"].endswith(f":8123/api/lommepenge/install/{token}")
    assert placeholders["expires"]

    # The device connects while the dialog is open.
    client = await hass_client_no_auth()
    assert (await AppClient(client).pair(token))["status"] == 200

    result = await hass.config_entries.subentries.async_configure(result["flow_id"], {})
    assert result["type"] is FlowResultType.CREATE_ENTRY
    await hass.async_block_till_done()

    subentry = next(iter(config_entry.subentries.values()))
    assert subentry.title == "Kitchen"
    assert subentry.data[CONF_ROLE] == ROLE_SCREEN
    device_id = subentry.data[CONF_DEVICE_ID]
    assert config_entry.runtime_data.devices[device_id]["registered"] is True


async def test_add_child_tablet(hass: HomeAssistant, config_entry: MockConfigEntry) -> None:
    runtime = await setup_entry(hass, config_entry)
    result = await _start_device_flow(hass, config_entry, "Emma's tablet", ROLE_CHILD)
    assert result["type"] is FlowResultType.ABORT
    assert result["reason"] == "no_children"

    await add_child(runtime, "emma", "Emma")
    result = await _start_device_flow(hass, config_entry, "Emma's tablet", ROLE_CHILD)
    assert result["step_id"] == "child"
    result = await hass.config_entries.subentries.async_configure(
        result["flow_id"], {CONF_CHILD_ID: "emma"}
    )
    assert result["step_id"] == "pair"
    result = await hass.config_entries.subentries.async_configure(result["flow_id"], {})
    assert result["type"] is FlowResultType.CREATE_ENTRY
    assert result["data"][CONF_CHILD_ID] == "emma"


async def test_reconfigure_gives_new_code(
    hass: HomeAssistant, config_entry: MockConfigEntry, hass_client_no_auth
) -> None:
    await setup_entry(hass, config_entry)
    result = await _start_device_flow(hass, config_entry, "Mum", ROLE_SCREEN)
    await hass.config_entries.subentries.async_configure(result["flow_id"], {})
    await hass.async_block_till_done()
    subentry_id = next(iter(config_entry.subentries))

    result = await config_entry.start_subentry_reconfigure_flow(hass, subentry_id)
    assert result["step_id"] == "reconfigure"
    token = result["description_placeholders"]["install_url"].rsplit("/", 1)[1]
    client = await hass_client_no_auth()
    app = AppClient(client)
    assert (await app.pair(token))["status"] == 200
    assert (await app.state()).status == 200

    result = await hass.config_entries.subentries.async_configure(result["flow_id"], {})
    assert result["reason"] == "reconfigure_successful"
