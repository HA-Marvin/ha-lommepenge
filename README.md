# Lommepenge – Home Assistant + Android app

The family's tasks and pocket money with Home Assistant as the server: HA
stores tasks, completions and balances, follows up on deadlines, and is the
only place the app on the family screen, the parents' phones and the
children's tablets talks to. Home network only – no cloud.

The repository contains both parts, released together with one version
number:

- `custom_components/lommepenge` – the integration (installed via HACS/Marketplace)
- `app/` – the Android app (Flutter), see [app/README.md](app/README.md)
- `blueprints/` – automations for approval and restriction
- `docs/app-api.md` – the API between Home Assistant and the app

Every release has both the integration and the signed APK, which HA fetches
and hands on to the family's devices.

## Languages

English is the default. Danish, German, Spanish and French are also
available. The language is always chosen explicitly – it never follows Home
Assistant's, the browser's or the phone's language, because many families run
Home Assistant in English but want e.g. Danish for the family.

- **The integration** – entity names, lock reasons, notification texts
  for the blueprints and the install page – uses the language chosen when it
  is set up (*Configure* changes it).
- **The app** asks for its language on first start (English is preselected).
  It can be changed later under *Settings* in parent mode, on the connect
  screen and on the child's tablet. Error messages from Home Assistant follow
  the app's language.
- Only Home Assistant's own forms (setup, *Configure*, *Add device*) and the
  service descriptions follow each user's language in Home Assistant – that
  is decided by Home Assistant itself.

Installations from before 0.4.0 keep Danish everywhere.

## Currency

The currency is written freely when the integration is set up – e.g. `DKK`
(the default), `kr`, `€` or `USD` – and can be changed under *Configure*. It
is used for the balance sensors, notification texts and everywhere in the
app. Amounts are stored in 1/100 of the currency, so changing the currency
does not convert existing amounts.

## Installation

1. HACS/Marketplace → ⋮ → *Custom repositories* → add
   `https://github.com/HA-Marvin/ha-lommepenge` as type *Integration*.
2. Install *Lommepenge* and restart Home Assistant.
3. *Settings → Devices & services → Add integration → Lommepenge*: the
   family's name, the parent PIN (4–8 digits), the language and the
   currency.

HA fetches the app from this repository's releases by itself – no GitHub
token is needed. (*Configure* can point to another repository, e.g. a private
one with a token, if you build your own app.)

If you upgrade from 0.1 (where the fridge screen was the server): delete the
old integration first and add it again.

## Devices

**The app:** *Settings → Devices & services → Lommepenge →* the family's
device *→ Visit* opens a page with **Download the app (.apk)** and the
instructions. If the device has no browser, download the file on the
computer and move it over, e.g. with USB.

**Add a device:** *Lommepenge → Add device*. Choose a name and role –
**family screen**, **parent's phone** or **child's tablet** (and which
child). HA shows an 8-character code and a link to a page with a QR code and
the app download.

On the device: open the app, choose the language, enter the code and tap
*Connect*. The app finds Home Assistant on the network by itself. If the
device has a camera, the QR code can be scanned instead. The code works once
for 15 minutes. After 10 wrong codes HA refuses pairing for 5 minutes.

Every device gets its own key and signs all requests. A child's tablet only
sees its own child and can only mark that child's tasks as done – this is
enforced by HA. If the device is deleted in HA, it loses access
immediately. *Reconfigure* on a device gives a new code (e.g. after a
reinstall).

## What you get

**Per child** (one HA device per child, following the names in the app).
Entity names – and the entity IDs of new entities – follow the integration's
language; in English:

| Entity | Description |
| --- | --- |
| `sensor.lommepenge_<child>_balance` | The child's balance (in the chosen currency) |
| `sensor.lommepenge_<child>_earned_this_week` | Earned in the last 7 days |
| `binary_sensor.lommepenge_<child>_tablet_restricted` | On = a lock is running (drive the network rule with it). Attributes: `lock_status` (`none`/`pending`/`running`), `reason`, `started_at`, `ends_at`, `pending_since`, `paused`, `overdue`, `due_today`, `child_id` |
| `binary_sensor.lommepenge_<child>_overdue_task` | On = a mandatory task is past its deadline |
| `button.lommepenge_<child>_lift_lock` | Clears the child's pending and running lock |
| `switch.lommepenge_<child>_tasks_paused` | Pause: no task is mandatory (no deadline, no lock), tasks still earn money. Attribute `paused_until` |

**Locks:** an overdue or rejected mandatory task locks the child's tablet.
The lock waits until the child uses the tablet, then runs for the lock
duration (default 60 minutes) and ends by itself; a lock that has not
started lapses after 24 hours. A late task done before its lock started
gives only the short "pause when done late" lock and still earns money;
once a lock has run out, its task gives no money that day. One lock at a
time, and one penalty per task occurrence.

**For the family:** `sensor.<family>_awaiting_approval` (attribute
`pending` with `amount` and `currency`; the old `amount_kr` is kept for
existing automations), the time `time.<family>_default_deadline` and the
limits `number.<family>_lock_duration`, `..._pause_when_done_late`,
`..._warning_before_deadline`, `..._winter_from_week`, `..._winter_until_week`.

**Per device:** `update.<device>_app` (installed and latest app version) and
`sensor.<device>_last_contact`.

**Services:** `lommepenge.approve`, `lommepenge.reject` (optional `reason`,
shown to the child), `lommepenge.lift_lock`, `lommepenge.pause` (optional
`until` date) and `lommepenge.resume`.

**Event:** `lommepenge_event` with `event` = `completion_pending`,
`completion_approved`, `completion_rejected`, `lock_started`, `lock_ended`
or `lock_lifted`, plus details (child, task, amount, `completionId`, `late`,
the lock's `reason`, `minutes`, `endsAt` …). Completion events also have
`message`: a ready-made notification text in the integration's language.

## Blueprints

HACS does not install blueprints. Import them with the buttons below (or
*Settings → Automations → Blueprints → Import* with the link):

[![Import approval](https://my.home-assistant.io/badges/blueprint_import.svg)](https://my.home-assistant.io/redirect/blueprint_import/?blueprint_url=https%3A%2F%2Fgithub.com%2FHA-Marvin%2Fha-lommepenge%2Fblob%2Fmain%2Fblueprints%2Fautomation%2Flommepenge%2Fapproval.yaml)
[![Import restriction](https://my.home-assistant.io/badges/blueprint_import.svg)](https://my.home-assistant.io/redirect/blueprint_import/?blueprint_url=https%3A%2F%2Fgithub.com%2FHA-Marvin%2Fha-lommepenge%2Fblob%2Fmain%2Fblueprints%2Fautomation%2Flommepenge%2Frestriction.yaml)

- **Approve via notification** – Approve/Reject buttons on the selected
  parents' phones. Only taps from the selected people's HA users are carried
  out. The notification disappears for everyone once the task is decided.
- **Restrict tablet while locked** – one automation per child. Turns on a
  switch (e.g. a UniFi traffic rule that blocks YouTube/games for the child's
  tablet) exactly while the child's lock runs, re-syncs it when HA starts,
  and turns it off if Lommepenge has been unavailable for 10 minutes. Parents
  are not notified about locks; they are in the app's history.

The approval notification text comes from the integration in its language.
Button labels and titles are blueprint inputs with English defaults – change
them when you create the automation.

With the locks, the restriction blueprint has only two inputs (the sensor
and the switch). Re-import it, then open and save each automation made from
it (the sensor and switch are kept; the old notification inputs are dropped).

The blueprints were renamed in 0.4.0 (`godkendelse.yaml` → `approval.yaml`,
`spaerring.yaml` → `restriction.yaml`). Automations made from the old
blueprints keep working, but "Re-import" of the old ones no longer finds them;
import the new ones instead.

## Security

- The app's API (`/api/lommepenge/…`) only answers on the home network –
  never via HA's external address or Nabu Casa.
- The app does not use HA's users or tokens. Every device has its own key;
  requests are signed with HMAC-SHA256 over timestamp, method, path and body,
  and may be at most 5 minutes old.
- HA's clock decides when a task was done (and thereby "late").
- The family's data and device keys are in `.storage/lommepenge.<id>` and
  are part of HA's backups. The app contains no family data, addresses or
  keys – it only gets them when pairing.

## Development and releases

```bash
pip install -r requirements_test.txt
pytest                       # the integration
cd app && flutter test       # the app
```

A release is made with a tag `vX.Y.Z` (the same version as in
`custom_components/lommepenge/manifest.json`). `.github/workflows/release.yml`
builds the signed APK and puts it on the release. The signing key is stored
as the secrets `KEYSTORE_BASE64` and `KEYSTORE_PASSWORD`.

**Translations:** the integration's UI texts are in
`custom_components/lommepenge/strings.json` (English) and `translations/`;
the texts it writes itself are in `custom_components/lommepenge/i18n.py`. The
app's texts are in `app/lib/l10n/app_<language>.arb` (English is the
template). The tests check that every language has every text.
