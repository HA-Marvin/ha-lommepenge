# Lommepenge – Home Assistant-integration

Home Assistant som server for familiens lommepenge-app: HA gemmer opgaver,
udførelser og saldi, følger op på frister, og er det eneste sted appen på
den fælles skærm, forældrenes telefoner og børnenes tablets taler med.
Kun hjemmenettet – ingen cloud.

## Installation

1. HACS/Marketplace → ⋮ → *Brugerdefinerede repositories* → tilføj
   `https://github.com/HA-Marvin/ha-lommepenge` som type *Integration*.
2. Installér *Lommepenge* og genstart Home Assistant.
3. *Indstillinger → Enheder og tjenester → Tilføj integration →
   Lommepenge*: familiens navn og forælder-PIN (4–8 cifre).
4. *Konfigurér*: en GitHub-nøgle med læseadgang til app-repoet. Så henter
   HA appens versioner og giver dem videre til enhederne.

Opgraderer du fra 0.1 (hvor køleskabsskærmen var server): slet den gamle
integration først og tilføj den igen.

## Enheder

*Lommepenge → Tilføj enhed*: vælg navn og rolle – **fælles skærm**,
**forælders telefon** eller **barnets tablet** (og hvilket barn). HA viser
en QR-kode, som enheden scanner med kameraet. Siden der åbner, har to
knapper: **Hent appen** og **Åbn appen og forbind**. Linket virker én gang
i 15 minutter.

Hver enhed får sin egen nøgle og signerer alle kald. En barne-tablet ser
kun sit eget barn og kan kun markere dets opgaver udført – det håndhæves
af HA. Slettes enheden i HA, mister den adgangen med det samme.
*Omkonfigurér* på en enhed giver en ny QR-kode (fx efter geninstallation).

## Hvad du får

**Pr. barn** (én HA-enhed pr. barn, følger appens navne):

| Entitet | Beskrivelse |
| --- | --- |
| `sensor.lommepenge_<barn>_saldo` | Barnets saldo (DKK) |
| `sensor.lommepenge_<barn>_optjent_denne_uge` | Optjent de sidste 7 dage |
| `binary_sensor.lommepenge_<barn>_tablet_spaerret` | Til = tabletten skal være spærret nu. Attributter: `reason`, `overdue`, `due_today`, `late_pause_until`, `child_id` |
| `binary_sensor.lommepenge_<barn>_forsinket_opgave` | Til = en obligatorisk opgave er over fristen |
| `button.lommepenge_<barn>_ophaev_spaerring_i_dag` | Ophæver spærringen resten af dagen |

**For familien:** `sensor.<familie>_venter_pa_godkendelse` (attribut
`pending`), tiderne `time.<familie>_standardfrist`, `..._spaerretid_fra`,
`..._spaerretid_til` og grænserne `number.<familie>_pausetid_...`,
`..._advarsel_for_frist`, `..._vinter_fra_uge`, `..._vinter_til_uge`.

**Pr. enhed:** `update.<enhed>_app` (installeret og nyeste app-version) og
`sensor.<enhed>_sidste_kontakt`.

**Services:** `lommepenge.approve`, `lommepenge.reject`,
`lommepenge.suspend_restriction`.

**Hændelse:** `lommepenge_event` med `event` = `completion_pending`,
`completion_approved`, `completion_rejected` eller `restriction_changed`,
plus detaljer (barn, opgave, beløb, `completionId`, `late` …).

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
  tablet), mens barnet er spærret. Valgfri besked til forældrene med
  knappen "Ophæv spærring i dag".

## Sikkerhed

- Appens API (`/api/lommepenge/…`) svarer kun på hjemmenettet – aldrig via
  HA's eksterne adresse eller Nabu Casa.
- Appen bruger ikke HA's brugere eller tokens. Hver enhed har sin egen
  nøgle; kald signeres med HMAC-SHA256 over tidspunkt, metode, sti og
  krop, og må højst være 5 minutter gamle.
- HA's ur bestemmer, hvornår en opgave er udført (og dermed "for sent").
- Familiens data og enhedsnøgler ligger i `.storage/lommepenge.<id>` og
  kommer med i HA's backups. GitHub-nøglen bruges kun af HA.

## Udvikling

```bash
pip install -r requirements_test.txt
pytest
```
