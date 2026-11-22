"""Setup: family, PIN, language and currency, GitHub token and "Add device" with a code."""

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
    DEFAULT_CURRENCY,
    DEFAULT_GITHUB_REPO,
    DEFAULT_LANGUAGE,
    DOMAIN,
    LANGUAGES,
    MAX_CURRENCY_LENGTH,
    ROLE_CHILD,
    ROLES,
    SUBENTRY_DEVICE,
)
from .http import install_url
from .i18n import normalize_language
from .releases import GitHubAuthError, GitHubError, GitHubReleases

PIN_PATTERN = re.compile(r"^\d{4,8}$")


def hash_pin(pin: str) -> dict[str, str]:
    """Salt + SHA-256("salt:pin") - the same form as the app's CryptoService."""
    salt = secrets.token_hex(16)
    return {
        CONF_PIN_SALT: salt,
        CONF_PIN_HASH: hashlib.sha256(f"{salt}:{pin}".encode()).hexdigest(),
    }


_PASSWORD = TextSelector(TextSelectorConfig(type=TextSelectorType.PASSWORD))


def _currency(value: str | None) -> str | None:
    """The currency as written by the user, or `None` if empty/too long."""
    currency = (value or "").strip()
    if not currency or len(currency) > MAX_CURRENCY_LENGTH:
        return None
    return currency

# The languages are shown by their own names (see "selector" in strings.json).
_LANGUAGE = SelectSelector(
    SelectSelectorConfig(
        options=list(LANGUAGES),
        translation_key="language",
        mode=SelectSelectorMode.DROPDOWN,
    )
)


class LommepengeConfigFlow(ConfigFlow, domain=DOMAIN):
    """One family per Home Assistant."""

    VERSION = 2
    # 2.2: the language for HA's own texts is stored in the entry's data.
    MINOR_VERSION = 2

    async def async_step_user(self, user_input: dict[str, Any] | None = None) -> ConfigFlowResult:
        errors: dict[str, str] = {}
        if user_input is not None:
            name = user_input[CONF_FAMILY_NAME].strip()
            if not name:
                errors[CONF_FAMILY_NAME] = "name_required"
            if not PIN_PATTERN.match(user_input[CONF_PIN]):
                errors[CONF_PIN] = "invalid_pin"
            currency = _currency(user_input.get(CONF_CURRENCY, DEFAULT_CURRENCY))
            if currency is None:
                errors[CONF_CURRENCY] = "invalid_currency"
            if not errors:
                return self.async_create_entry(
                    title=name,
                    data={
                        CONF_FAMILY_NAME: name,
                        CONF_LANGUAGE: normalize_language(user_input.get(CONF_LANGUAGE))
                        or DEFAULT_LANGUAGE,
                        CONF_CURRENCY: currency,
                        **hash_pin(user_input[CONF_PIN]),
                    },
                )
        return self.async_show_form(
            step_id="user",
            data_schema=vol.Schema(
                {
                    vol.Required(CONF_FAMILY_NAME, default="Family"): str,
                    vol.Required(CONF_PIN): _PASSWORD,
                    vol.Required(CONF_LANGUAGE, default=DEFAULT_LANGUAGE): _LANGUAGE,
                    vol.Required(CONF_CURRENCY, default=DEFAULT_CURRENCY): str,
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
    """Language, currency, GitHub token for the app's versions and a new parent PIN."""

    async def async_step_init(self, user_input: dict[str, Any] | None = None) -> ConfigFlowResult:
        errors: dict[str, str] = {}
        options = self.config_entry.options
        data = self.config_entry.data
        if user_input is not None:
            token = (user_input.get(CONF_GITHUB_TOKEN) or "").strip()
            repo = user_input[CONF_GITHUB_REPO].strip()
            new_pin = (user_input.get(CONF_PIN) or "").strip()
            language = normalize_language(user_input.get(CONF_LANGUAGE)) or DEFAULT_LANGUAGE
            if new_pin and not PIN_PATTERN.match(new_pin):
                errors[CONF_PIN] = "invalid_pin"
            currency = _currency(user_input.get(CONF_CURRENCY, DEFAULT_CURRENCY))
            if currency is None:
                errors[CONF_CURRENCY] = "invalid_currency"
            if not errors:
                try:
                    await GitHubReleases(
                        async_get_clientsession(self.hass), repo, token or None
                    ).validate()
                except GitHubAuthError:
                    errors[CONF_GITHUB_TOKEN] = "invalid_token"
                except GitHubError:
                    errors["base"] = "cannot_connect"
            if not errors:
                new_data = {**data, CONF_LANGUAGE: language, CONF_CURRENCY: currency}
                if new_pin:
                    new_data.update(hash_pin(new_pin))
                if new_data != data:
                    self.hass.config_entries.async_update_entry(self.config_entry, data=new_data)
                return self.async_create_entry(
                    data={CONF_GITHUB_TOKEN: token, CONF_GITHUB_REPO: repo}
                )
        return self.async_show_form(
            step_id="init",
            data_schema=vol.Schema(
                {
                    vol.Required(
                        CONF_LANGUAGE,
                        default=normalize_language(data.get(CONF_LANGUAGE)) or DEFAULT_LANGUAGE,
                    ): _LANGUAGE,
                    vol.Required(
                        CONF_CURRENCY,
                        default=data.get(CONF_CURRENCY) or DEFAULT_CURRENCY,
                    ): str,
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
    """Add device: choose a role (and child), and enter the code on the device."""

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
        return self._show_code("pair")

    async def async_step_reconfigure(
        self, user_input: dict[str, Any] | None = None
    ) -> SubentryFlowResult:
        """A new code for an existing device (e.g. after reinstalling)."""
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
        return self._show_code("reconfigure")

    def _new_pairing(self) -> None:
        self._token, expires = self._runtime().async_create_pairing(
            self._device_id, self._name, self._role, self._child_id
        )
        self._expires = dt_util.as_local(expires).strftime("%H:%M")

    def _show_code(self, step_id: str) -> SubentryFlowResult:
        return self.async_show_form(
            step_id=step_id,
            data_schema=vol.Schema({}),
            description_placeholders={
                "name": self._name,
                "code": self._token,
                "expires": self._expires,
                "install_url": install_url(self.hass, self._token),
            },
        )
