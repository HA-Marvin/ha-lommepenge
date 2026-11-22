"""Constants for the Lommepenge integration."""

from datetime import timedelta

DOMAIN = "lommepenge"

# Config entry: the family's name and parent PIN (only salt + hash are stored).
CONF_FAMILY_NAME = "family_name"
CONF_PIN = "pin"
CONF_PIN_HASH = "pin_hash"
CONF_PIN_SALT = "pin_salt"

# Language of the integration: entity names, restriction reasons, notification
# texts, error messages and the install page. Chosen when the integration is
# set up and can be changed under Configure. Deliberately NOT taken from HA's
# language, which is often English in families that want e.g. Danish. Only
# HA's own forms and service descriptions follow each user's language in HA.
CONF_LANGUAGE = "language"
LANGUAGES = ("en", "da", "de", "es", "fr")
DEFAULT_LANGUAGE = "en"

# The currency the family's amounts are shown in, written freely by the user
# (e.g. "DKK", "kr", "€"). Amounts are stored in 1/100 of the unit.
CONF_CURRENCY = "currency"
DEFAULT_CURRENCY = "DKK"
MAX_CURRENCY_LENGTH = 10

# Options: where the app's versions are fetched from. By default the
# integration's own (public) repository, where every release also carries the
# app's APK. A token is only needed if you build your own app in a private
# repository.
CONF_GITHUB_TOKEN = "github_token"
CONF_GITHUB_REPO = "github_repo"
DEFAULT_GITHUB_REPO = "HA-Marvin/ha-lommepenge"

# Every tablet/phone/screen is a config subentry of this type.
SUBENTRY_DEVICE = "device"
CONF_DEVICE_ID = "device_id"
CONF_ROLE = "role"
CONF_CHILD_ID = "child_id"
CONF_NAME = "name"

# Roles. A child's tablet only sees one child and can only mark that child's
# tasks as done; the screen and parents have full access (the parent part is
# PIN-locked in the app).
ROLE_SCREEN = "screen"
ROLE_PARENT = "parent"
ROLE_CHILD = "child"
ROLES = (ROLE_SCREEN, ROLE_PARENT, ROLE_CHILD)

API_PREFIX = "/api/lommepenge"

# A pairing code (QR code) works this long and only for one device.
PAIRING_TTL = timedelta(minutes=15)
# A signed request may be at most this old (against replay).
SIGNATURE_MAX_AGE = timedelta(minutes=5)

# The follow-up is recalculated regularly, because deadlines pass without the
# data changing.
FOLLOW_UP_INTERVAL = timedelta(seconds=30)
RELEASE_CHECK_INTERVAL = timedelta(hours=6)

# Event on HA's event bus (completion_pending, completion_approved,
# completion_rejected, restriction_changed). Used by the blueprints.
EVENT_LOMMEPENGE = "lommepenge_event"

SERVICE_APPROVE = "approve"
SERVICE_REJECT = "reject"
SERVICE_SUSPEND_RESTRICTION = "suspend_restriction"

ATTR_COMPLETION_ID = "completion_id"
ATTR_CHILD_ID = "child_id"
