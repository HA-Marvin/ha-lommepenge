"""Opsætning: familie + PIN, GitHub-nøgle og "Tilføj enhed" med QR-kode."""

from __future__ import annotations

import hashlib
import re
import secrets
from typing import Any
import uuid

import voluptuous as vol

from homeassistant.config_entries import (
    ConfigEntry,
    ConfigEntryState,
    ConfigFlow,
    ConfigFlowResult,
    ConfigSubentryFlow,
    OptionsFlow,
    SubentryFlowResult,
)
from homeassistant.core import callback
from homeassistant.helpers.aiohttp_client import async_get_clientsession
from homeassistant.helpers.selector import (
    SelectOptionDict,
    SelectSelector,
    SelectSelectorConfig,
    SelectSelectorMode,
    TextSelector,
    TextSelectorConfig,
    TextSelectorType,
)
from homeassistant.util import dt as dt_util

from .const import (
    API_PREFIX,
    CONF_CHILD_ID,
    CONF_DEVICE_ID,
    CONF_FAMILY_NAME,
    CONF_GITHUB_REPO,
    CONF_GITHUB_TOKEN,
    CONF_NAME,
    CONF_PIN,
    CONF_PIN_HASH,
    CONF_PIN_SALT,
    CONF_ROLE,
    DEFAULT_GITHUB_REPO,
    DOMAIN,
    ROLE_CHILD,
    ROLES,
    SUBENTRY_DEVICE,
)
from .http import install_url
from .releases import GitHubAuthError, GitHubError, GitHubReleases

PIN_PATTERN = re.compile(r"^\d{4,8}$")


def hash_pin(pin: str) -> dict[str, str]:
    """Salt + SHA-256("salt:pin") - samme form som appens CryptoService."""
    salt = secrets.token_hex(16)
    return {
        CONF_PIN_SALT: salt,
        CONF_PIN_HASH: hashlib.sha256(f"{salt}:{pin}".encode()).hexdigest(),
    }


_PASSWORD = TextSelector(TextSelectorConfig(type=TextSelectorType.PASSWORD))


class LommepengeConfigFlow(ConfigFlow, domain=DOMAIN):
    """Én familie pr. Home Assistant."""

    VERSION = 2

    async def async_step_user(self, user_input: dict[str, Any] | None = None) -> ConfigFlowResult:
        errors: dict[str, str] = {}
        if user_input is not None:
            name = user_input[CONF_FAMILY_NAME].strip()
            if not name:
                errors[CONF_FAMILY_NAME] = "name_required"
            if not PIN_PATTERN.match(user_input[CONF_PIN]):
                errors[CONF_PIN] = "invalid_pin"
            if not errors:
                return self.async_create_entry(
                    title=name,
                    data={CONF_FAMILY_NAME: name, **hash_pin(user_input[CONF_PIN])},
                )
        return self.async_show_form(
            step_id="user",
            data_schema=vol.Schema(
                {
                    vol.Required(CONF_FAMILY_NAME, default="Familien"): str,
                    vol.Required(CONF_PIN): _PASSWORD,
                }
            ),
            errors=errors,
        )

    @staticmethod
    @callback
    def async_get_options_flow(config_entry: ConfigEntry) -> OptionsFlow:
        return LommepengeOptionsFlow()

    @classmethod
    @callback
    def async_get_supported_subentry_types(
        cls, config_entry: ConfigEntry
    ) -> dict[str, type[ConfigSubentryFlow]]:
        return {SUBENTRY_DEVICE: DeviceSubentryFlow}


class LommepengeOptionsFlow(OptionsFlow):
    """GitHub-nøgle til appens versioner og skift af forælder-PIN."""

    async def async_step_init(self, user_input: dict[str, Any] | None = None) -> ConfigFlowResult:
        errors: dict[str, str] = {}
        options = self.config_entry.options
        if user_input is not None:
            token = (user_input.get(CONF_GITHUB_TOKEN) or "").strip()
            repo = user_input[CONF_GITHUB_REPO].strip()
            new_pin = (user_input.get(CONF_PIN) or "").strip()
            if new_pin and not PIN_PATTERN.match(new_pin):
                errors[CONF_PIN] = "invalid_pin"
            if token and not errors:
                try:
                    await GitHubReleases(async_get_clientsession(self.hass), repo, token).validate()
                except GitHubAuthError:
                    errors[CONF_GITHUB_TOKEN] = "invalid_token"
                except GitHubError:
                    errors["base"] = "cannot_connect"
            if not errors:
                if new_pin:
                    self.hass.config_entries.async_update_entry(
                        self.config_entry, data={**self.config_entry.data, **hash_pin(new_pin)}
                    )
                return self.async_create_entry(
                    data={CONF_GITHUB_TOKEN: token, CONF_GITHUB_REPO: repo}
                )
        return self.async_show_form(
            step_id="init",
            data_schema=vol.Schema(
                {
                    vol.Optional(
                        CONF_GITHUB_TOKEN,
                        description={"suggested_value": options.get(CONF_GITHUB_TOKEN)},
                    ): _PASSWORD,
                    vol.Required(
                        CONF_GITHUB_REPO,
                        default=options.get(CONF_GITHUB_REPO, DEFAULT_GITHUB_REPO),
                    ): str,
                    vol.Optional(CONF_PIN): _PASSWORD,
                }
            ),
            errors=errors,
        )


class DeviceSubentryFlow(ConfigSubentryFlow):
    """Tilføj enhed: vælg rolle (og barn), og scan QR-koden på enheden."""

    def __init__(self) -> None:
        self._name = ""
        self._role = ROLE_CHILD
        self._child_id: str | None = None
        self._device_id = ""
        self._token: str | None = None
        self._expires = ""

    def _runtime(self):
        entry = self._get_entry()
        if entry.state is not ConfigEntryState.LOADED:
            return None
        return entry.runtime_data

    async def async_step_user(self, user_input: dict[str, Any] | None = None) -> SubentryFlowResult:
        if self._runtime() is None:
            return self.async_abort(reason="not_loaded")
        errors: dict[str, str] = {}
        if user_input is not None:
            self._name = user_input[CONF_NAME].strip()
            self._role = user_input[CONF_ROLE]
            if not self._name:
                errors[CONF_NAME] = "name_required"
            elif self._role == ROLE_CHILD:
                return await self.async_step_child()
            else:
                return await self.async_step_pair()
        return self.async_show_form(
            step_id="user",
            data_schema=vol.Schema(
                {
                    vol.Required(CONF_NAME): str,
                    vol.Required(CONF_ROLE, default=ROLE_CHILD): SelectSelector(
                        SelectSelectorConfig(
                            options=list(ROLES),
                            translation_key="role",
                            mode=SelectSelectorMode.LIST,
                        )
                    ),
                }
            ),
            errors=errors,
        )

    async def async_step_child(self, user_input: dict[str, Any] | None = None) -> SubentryFlowResult:
        children = self._runtime().family.children
        if not children:
            return self.async_abort(reason="no_children")
        if user_input is not None:
            self._child_id = user_input[CONF_CHILD_ID]
            return await self.async_step_pair()
        return self.async_show_form(
            step_id="child",
            data_schema=vol.Schema(
                {
                    vol.Required(CONF_CHILD_ID): SelectSelector(
                        SelectSelectorConfig(
                            options=[
                                SelectOptionDict(value=c["id"], label=c["name"]) for c in children
                            ],
                            mode=SelectSelectorMode.LIST,
                        )
                    )
                }
            ),
        )

    async def async_step_pair(self, user_input: dict[str, Any] | None = None) -> SubentryFlowResult:
        if user_input is not None:
            return self.async_create_entry(
                title=self._name,
                data={
                    CONF_DEVICE_ID: self._device_id,
                    CONF_ROLE: self._role,
                    CONF_CHILD_ID: self._child_id,
                },
                unique_id=self._device_id,
            )
        if self._token is None:
            self._device_id = uuid.uuid4().hex
            self._new_pairing()
        return self._show_qr("pair")

    async def async_step_reconfigure(
        self, user_input: dict[str, Any] | None = None
    ) -> SubentryFlowResult:
        """Ny QR-kode til en eksisterende enhed (fx efter geninstallation)."""
        subentry = self._get_reconfigure_subentry()
        if user_input is not None:
            return self.async_update_and_abort(self._get_entry(), subentry)
        if self._runtime() is None:
            return self.async_abort(reason="not_loaded")
        if self._token is None:
            self._device_id = subentry.data[CONF_DEVICE_ID]
            self._name = subentry.title
            self._role = subentry.data[CONF_ROLE]
            self._child_id = subentry.data.get(CONF_CHILD_ID)
            self._new_pairing()
        return self._show_qr("reconfigure")

    def _new_pairing(self) -> None:
        self._token, expires = self._runtime().async_create_pairing(
            self._device_id, self._name, self._role, self._child_id
        )
        self._expires = dt_util.as_local(expires).strftime("%H:%M")

    def _show_qr(self, step_id: str) -> SubentryFlowResult:
        return self.async_show_form(
            step_id=step_id,
            data_schema=vol.Schema({}),
            description_placeholders={
                "name": self._name,
                "qr_url": f"{API_PREFIX}/qr/{self._token}.svg",
                "install_url": install_url(self.hass, self._token),
                "expires": self._expires,
            },
        )
