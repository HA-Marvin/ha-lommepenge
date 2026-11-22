# Lommepenge-app

Familiens app til opgaver og lommepenge. Forældre opretter opgaver med en
kroneværdi, børnene markerer dem udført, og forældrene godkender – i
appen eller direkte fra en notifikation i Home Assistant.

**Home Assistant er serveren.** Integrationen i samme repo
(`custom_components/lommepenge`) gemmer familiens data, regner frister og
spærring, og er det eneste sted appen taler med. Appen har ingen egen server og intet internet-krav – kun
hjemmenettet.

## Roller

Rollen vælges i Home Assistant, når enheden tilføjes, og kan ikke ændres
på enheden selv:

| Rolle | Visning | Forælder-delen |
| --- | --- | --- |
| Fælles skærm (fx køleskabet) | Alle børn, én kolonne pr. barn | Låst med familiens PIN |
| Forælders telefon | Fælles opgaveliste og saldi | Låst med familiens PIN |
| Barnets tablet | Kun det ene barns opgaver | Findes ikke – HA afviser alt andet end "markér udført" for barnet selv |

PIN-koden sættes i Home Assistant. En barne-tablet kan kun forbindes igen
efter en geninstallation (`allowBackup="false"`).

## Installation på en ny enhed

1. I Home Assistant: *Lommepenge → Tilføj enhed*. Vælg navn og rolle
   (og barn). HA viser en QR-kode.
2. Scan QR-koden med enhedens kamera. Siden fra HA har to knapper:
   **Hent appen** (APK'en hentes fra HA) og **Åbn appen og forbind**.
3. Har enheden allerede appen, kan QR-koden også scannes inde i appen.

## Opdateringer

App og integration udgives sammen: et tag `vX.Y.Z` bygger en signeret
APK med GitHub Actions (`.github/workflows/release.yml` i repoets rod) og
lægger den på releasen sammen med dens SHA-256. Home Assistant henter den
derfra, og appen viser "Ny version klar". **Opdater** henter APK'en fra HA, tjekker
SHA-256 og beder Android installere den. Versionskoden er
`major·10000 + minor·100 + patch`.

## Signering

Appen signeres med en fast nøgle (`lommepenge-release.jks`), som ligger
uden for git sammen med `key.properties`. GitHub Actions får den via
hemmelighederne `KEYSTORE_BASE64` og `KEYSTORE_PASSWORD`. **Mistes nøglen,
kan ingen enhed opdateres uden geninstallation** – gem en backup.

Uden `android/key.properties` bygges med debug-nøglen (til `flutter run`).

## Udvikling

```bash
flutter pub get
flutter test
flutter build apk --release --target-platform android-arm,android-arm64
```

Se `WINDOWS_OPSAETNING.md` for Flutter på Windows.

## Struktur

```
lib/
  main.dart                  router: forbind → rollens forside
  providers/app_state.dart   tilstand, sync med HA, offline-kø, opdatering
  services/ha_client.dart    signerede kald til integrationen
  services/native_bridge.dart  links, version, installation (MainActivity.kt)
  repositories/              lokal kopi af familiens data og samme regler som HA
  logic/                     tilgængelighed, frister og spærring
  screens/ widgets/          UI
```
