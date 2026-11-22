"""Opsætning: find køleskabsskærmen og bekræft med forælder-PIN."""

from __future__ import annotations

from collections.abc import Mapping
import logging
from typing import Any

import voluptuous as vol

from homeassistant.components import webhook
from homeassistant.config_entries import ConfigFlow, ConfigFlowResult
from homeassistant.const import CONF_HOST, CONF_PORT
from homeassistant.helpers.aiohttp_client import async_get_clientsession

try:
    from homeassistant.helpers.service_info.zeroconf import ZeroconfServiceInfo
except ImportError:  # HA før 2025.1
    from homeassistant.components.zeroconf import ZeroconfServiceInfo

from .api import CannotConnect, InvalidAuth, LommepengeApi, LommepengeError, TooManyAttempts
from .const import CONF_PIN, CONF_TOKEN, CONF_WEBHOOK_ID, DEFAULT_PORT, DOMAIN

_LOGGER = logging.getLogger(__name__)

_PIN_SCHEMA = vol.Schema({vol.Required(CONF_PIN): str})


class LommepengeConfigFlow(ConfigFlow, domain=DOMAIN):
    """Config flow for Lommepenge."""

    VERSION = 1

    def __init__(self) -> None:
        self._host: str | None = None
        self._port: int = DEFAULT_PORT
        self._name: str | None = None

    async def _async_pair(self, host: str, port: int, pin: str) -> tuple[dict[str, Any] | None, str | None]:
        """Returnerer (svar, fejl-nøgle)."""
        api = LommepengeApi(async_get_clientsession(self.hass), host, port)
        try:
            return await api.pair(pin), None
        except InvalidAuth:
            return None, "invalid_auth"
        except TooManyAttempts:
            return None, "too_many_attempts"
        except CannotConnect:
            return None, "cannot_connect"
        except LommepengeError:
            _LOGGER.exception("Uventet svar fra køleskabsskærmen")
            return None, "unknown"

    async def _async_finish(self, host: str, port: int, result: dict[str, Any]) -> ConfigFlowResult:
        await self.async_set_unique_id(result["screenId"])
        self._abort_if_unique_id_configured(
            updates={CONF_HOST: host, CONF_PORT: port, CONF_TOKEN: result["token"]}
        )
        return self.async_create_entry(
            title=result.get("familyName") or "Lommepenge",
            data={
                CONF_HOST: host,
                CONF_PORT: port,
                CONF_TOKEN: result["token"],
                CONF_WEBHOOK_ID: webhook.async_generate_id(),
            },
        )

    async def async_step_user(self, user_input: dict[str, Any] | None = None) -> ConfigFlowResult:
        """Manuel opsætning: IP, port og forælder-PIN."""
        errors: dict[str, str] = {}
        if user_input is not None:
            host = user_input[CONF_HOST].strip()
            port = user_input[CONF_PORT]
            result, error = await self._async_pair(host, port, user_input[CONF_PIN])
            if result is not None:
                return await self._async_finish(host, port, result)
            errors["base"] = error or "unknown"

        return self.async_show_form(
            step_id="user",
            data_schema=vol.Schema(
                {
                    vol.Required(CONF_HOST, default=(user_input or {}).get(CONF_HOST, "")): str,
                    vol.Required(CONF_PORT, default=DEFAULT_PORT): int,
                    vol.Required(CONF_PIN): str,
                }
            ),
            errors=errors,
        )

    async def async_step_zeroconf(self, discovery_info: ZeroconfServiceInfo) -> ConfigFlowResult:
        """Skærmen er fundet automatisk på netværket."""
        self._host = str(discovery_info.ip_address)
        self._port = discovery_info.port or DEFAULT_PORT
        self._name = discovery_info.name.split(".")[0]

        # Skærmens id kendes først efter parring, så kendte skærme genkendes
        # her på adressen.
        self._async_abort_entries_match({CONF_HOST: self._host})
        await self._async_handle_discovery_without_unique_id()

        self.context["title_placeholders"] = {"name": self._name}
        return await self.async_step_zeroconf_confirm()

    async def async_step_zeroconf_confirm(self, user_input: dict[str, Any] | None = None) -> ConfigFlowResult:
        errors: dict[str, str] = {}
        assert self._host is not None
        if user_input is not None:
            result, error = await self._async_pair(self._host, self._port, user_input[CONF_PIN])
            if result is not None:
                return await self._async_finish(self._host, self._port, result)
            errors["base"] = error or "unknown"

        return self.async_show_form(
            step_id="zeroconf_confirm",
            data_schema=_PIN_SCHEMA,
            description_placeholders={"name": self._name or "", "host": self._host},
            errors=errors,
        )

    async def async_step_reauth(self, entry_data: Mapping[str, Any]) -> ConfigFlowResult:
        """Nøglen er tilbagekaldt i appen - bed om PIN igen."""
        return await self.async_step_reauth_confirm()

    async def async_step_reauth_confirm(self, user_input: dict[str, Any] | None = None) -> ConfigFlowResult:
        errors: dict[str, str] = {}
        entry = self._get_reauth_entry()
        if user_input is not None:
            host, port = entry.data[CONF_HOST], entry.data[CONF_PORT]
            result, error = await self._async_pair(host, port, user_input[CONF_PIN])
            if result is not None:
                await self.async_set_unique_id(result["screenId"])
                self._abort_if_unique_id_mismatch(reason="wrong_screen")
                return self.async_update_reload_and_abort(
                    entry, data_updates={CONF_TOKEN: result["token"]}
                )
            errors["base"] = error or "unknown"

        return self.async_show_form(
            step_id="reauth_confirm", data_schema=_PIN_SCHEMA, errors=errors
        )
