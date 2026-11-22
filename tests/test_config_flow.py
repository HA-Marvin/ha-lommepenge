"""Tests for opsætningen (config flow)."""

from __future__ import annotations

from ipaddress import ip_address
from unittest.mock import patch

import pytest

from homeassistant import config_entries
from homeassistant.const import CONF_HOST, CONF_PORT
from homeassistant.core import HomeAssistant
from homeassistant.data_entry_flow import FlowResultType
from pytest_homeassistant_custom_component.test_util.aiohttp import AiohttpClientMocker

from custom_components.lommepenge.config_flow import ZeroconfServiceInfo
from custom_components.lommepenge.const import CONF_PIN, CONF_TOKEN, CONF_WEBHOOK_ID, DOMAIN

from .conftest import BASE, HOST, PORT, SCREEN_ID, TOKEN

PAIR_OK = {"token": TOKEN, "screenId": SCREEN_ID, "familyName": "Familien"}


@pytest.fixture(autouse=True)
def mock_setup_entry():
    """Config-flow-tests tester kun flowet - ikke selve opsætningen."""
    with patch(
        "custom_components.lommepenge.async_setup_entry", return_value=True
    ) as mock:
        yield mock


async def test_user_flow_pairs_with_pin(
    hass: HomeAssistant, aioclient_mock: AiohttpClientMocker, mock_screen
) -> None:
    aioclient_mock.post(f"{BASE}/ha/pair", json=PAIR_OK)

    result = await hass.config_entries.flow.async_init(
        DOMAIN, context={"source": config_entries.SOURCE_USER}
    )
    assert result["type"] is FlowResultType.FORM

    result = await hass.config_entries.flow.async_configure(
        result["flow_id"], {CONF_HOST: HOST, CONF_PORT: PORT, CONF_PIN: "1234"}
    )
    assert result["type"] is FlowResultType.CREATE_ENTRY
    assert result["title"] == "Familien"
    assert result["data"][CONF_TOKEN] == TOKEN
    assert result["data"][CONF_WEBHOOK_ID]
    assert result["result"].unique_id == SCREEN_ID
    # PIN'en sendes til skærmen, men gemmes ikke i HA.
    assert CONF_PIN not in result["data"]
    pair_call = next(c for c in aioclient_mock.mock_calls if str(c[1]).endswith("/ha/pair"))
    assert pair_call[2] == {"pin": "1234"}


async def test_user_flow_wrong_pin(
    hass: HomeAssistant, aioclient_mock: AiohttpClientMocker
) -> None:
    aioclient_mock.post(f"{BASE}/ha/pair", status=401, json={"error": "Forkert PIN-kode."})

    result = await hass.config_entries.flow.async_init(
        DOMAIN, context={"source": config_entries.SOURCE_USER}
    )
    result = await hass.config_entries.flow.async_configure(
        result["flow_id"], {CONF_HOST: HOST, CONF_PORT: PORT, CONF_PIN: "0000"}
    )
    assert result["type"] is FlowResultType.FORM
    assert result["errors"] == {"base": "invalid_auth"}


async def test_user_flow_too_many_attempts(
    hass: HomeAssistant, aioclient_mock: AiohttpClientMocker
) -> None:
    aioclient_mock.post(f"{BASE}/ha/pair", status=429, json={"error": "Vent"})

    result = await hass.config_entries.flow.async_init(
        DOMAIN, context={"source": config_entries.SOURCE_USER}
    )
    result = await hass.config_entries.flow.async_configure(
        result["flow_id"], {CONF_HOST: HOST, CONF_PORT: PORT, CONF_PIN: "0000"}
    )
    assert result["errors"] == {"base": "too_many_attempts"}


async def test_user_flow_cannot_connect(
    hass: HomeAssistant, aioclient_mock: AiohttpClientMocker
) -> None:
    aioclient_mock.post(f"{BASE}/ha/pair", exc=TimeoutError())

    result = await hass.config_entries.flow.async_init(
        DOMAIN, context={"source": config_entries.SOURCE_USER}
    )
    result = await hass.config_entries.flow.async_configure(
        result["flow_id"], {CONF_HOST: HOST, CONF_PORT: PORT, CONF_PIN: "1234"}
    )
    assert result["errors"] == {"base": "cannot_connect"}


async def test_zeroconf_flow(
    hass: HomeAssistant, aioclient_mock: AiohttpClientMocker, mock_screen
) -> None:
    aioclient_mock.post(f"{BASE}/ha/pair", json=PAIR_OK)
    info = ZeroconfServiceInfo(
        ip_address=ip_address(HOST),
        ip_addresses=[ip_address(HOST)],
        hostname="skaerm.local.",
        name="Familien._lommepenge._tcp.local.",
        port=PORT,
        type="_lommepenge._tcp.local.",
        properties={},
    )
    result = await hass.config_entries.flow.async_init(
        DOMAIN, context={"source": config_entries.SOURCE_ZEROCONF}, data=info
    )
    assert result["type"] is FlowResultType.FORM
    assert result["step_id"] == "zeroconf_confirm"

    result = await hass.config_entries.flow.async_configure(
        result["flow_id"], {CONF_PIN: "1234"}
    )
    assert result["type"] is FlowResultType.CREATE_ENTRY
    assert result["data"][CONF_HOST] == HOST
