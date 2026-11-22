# Lommepenge – Home Assistant-integration

Forbinder Home Assistant med lommepenge-appens køleskabsskærm over det
lokale netværk. Ingen cloud.

## Hvad du får

**Pr. barn** (én HA-enhed pr. barn):

| Entitet | Beskrivelse |
| --- | --- |
| `sensor.lommepenge_<barn>_saldo` | Barnets saldo (DKK) |
| `sensor.lommepenge_<barn>_optjent_denne_uge` | Optjent de sidste 7 dage |
| `binary_sensor.lommepenge_<barn>_tablet_spaerret` | Til = tabletten skal være spærret nu. Attributter: `reason`, `overdue`, `due_today`, `late_pause_until`, `child_id` |
| `binary_sensor.lommepenge_<barn>_forsinket_opgave` | Til = en obligatorisk opgave er over fristen |
| `button.lommepenge_<barn>_ophaev_spaerring_i_dag` | Ophæver spærringen resten af dagen |

**For familien** (køleskabsskærmen):

| Entitet | Beskrivelse |
| --- | --- |
| `sensor.<familie>_venter_pa_godkendelse` | Antal opgaver der venter. Attribut `pending` med detaljer |
| `time.<familie>_standardfrist`, `..._spaerretid_fra`, `..._spaerretid_til` | Familiens tider – kan rettes her eller i appen |
| `number.<familie>_pausetid_...`, `..._advarsel_for_frist`, `..._vinter_fra_uge`, `..._vinter_til_uge` | Familiens grænser |

(De præcise entitets-id'er afhænger af navnene i appen.)

**Services:** `lommepenge.approve`, `lommepenge.reject`, `lommepenge.suspend_restriction`.

**Hændelse:** `lommepenge_event` med `event` =
`completion_pending`, `completion_approved`, `completion_rejected` eller
`restriction_changed`, plus detaljer (barn, opgave, beløb, `completionId` …).

## Installation

1. HACS → ⋮ → *Brugerdefinerede repositories* → tilføj
   `https://github.com/HA-Marvin/ha-lommepenge` som type *Integration*.
2. Søg efter *Lommepenge* i HACS, installér, og genstart Home Assistant.
3. Køleskabsskærmen dukker op under *Indstillinger → Enheder og tjenester*
   som fundet enhed (ellers: *Tilføj integration → Lommepenge* og indtast
   IP-adressen). Bekræft med familiens forælder-PIN.

HA skal have en **intern URL** (*Indstillinger → System → Netværk*), så
skærmen kan sende hændelser med det samme. Uden den virker alt stadig, men
med op til et minuts forsinkelse.

## Blueprints

HACS installerer ikke blueprints. Importér dem med knapperne herunder (eller
*Indstillinger → Automationer → Blueprints → Importér* med linket):

[![Importér godkendelse](https://my.home-assistant.io/badges/blueprint_import.svg)](https://my.home-assistant.io/redirect/blueprint_import/?blueprint_url=https%3A%2F%2Fgithub.com%2FHA-Marvin%2Fha-lommepenge%2Fblob%2Fmain%2Fblueprints%2Fautomation%2Flommepenge%2Fgodkendelse.yaml)
[![Importér spærring](https://my.home-assistant.io/badges/blueprint_import.svg)](https://my.home-assistant.io/redirect/blueprint_import/?blueprint_url=https%3A%2F%2Fgithub.com%2FHA-Marvin%2Fha-lommepenge%2Fblob%2Fmain%2Fblueprints%2Fautomation%2Flommepenge%2Fspaerring.yaml)

- **Godkendelse via notifikation** – Godkend/Afvis-knapper til de valgte
  forældres telefoner. Kun tryk fra de valgte personers HA-brugere bliver
  udført. Notifikationen forsvinder hos alle, når opgaven er afgjort.
- **Spær tablet ved forsinket opgave** – én automation pr. barn. Tænder en
  kontakt (fx en UniFi-trafikregel, der blokerer YouTube/spil for barnets
  tablet) mens barnet er spærret. Er skærmen utilgængelig i 10 minutter,
  slukkes kontakten (fail-open). Valgfri besked til forældrene med knappen
  "Ophæv spærring i dag".

## Sikkerhed

- Kun LAN. Webhooken er `local_only`.
- HA får sin egen nøgle ved parring med forælder-PIN. Skærmen låser i et
  minut efter 5 forkerte PIN-forsøg.
- HA kan kun godkende/afvise, ophæve spærring og ændre familiens tider –
  ikke oprette/slette opgaver eller ændre saldo.
- Nøglen kan tilbagekaldes i appen (*Forælder-tilstand → Indstillinger →
  Afbryd forbindelsen*); HA beder så om PIN igen.

## Udvikling

```bash
pip install -r requirements_test.txt
pytest
```
