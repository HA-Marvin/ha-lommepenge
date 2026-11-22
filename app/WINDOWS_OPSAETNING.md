# Sådan bygger du APK'en på din egen Windows-pc

Kildekoden til appen er færdigskrevet (se README.md), men kunne **ikke bygges
til en APK i Claudes cloud-miljø** — det miljø har ingen netværksadgang til
Flutter/Android-værktøjerne (afprøvet grundigt, se README.md). Løsningen er
at bygge den på din egen pc, som har almindelig internetadgang. Det tager
typisk 30-60 minutter første gang (mest download-tid), og skal kun gøres én
gang — derefter kan du bygge nye APK'er på få minutter, hver gang jeg
leverer opdateret kode.

## 1. Installér Android Studio (inkl. Android SDK)
1. Hent Android Studio fra https://developer.android.com/studio
2. Kør installationsprogrammet med standardvalgene. Det installerer også
   Android SDK og en emulator.
3. Åbn Android Studio én gang, gå gennem opsætningsguiden (den henter de
   sidste SDK-komponenter).

## 2. Installér Flutter SDK
1. Hent Flutter til Windows fra https://docs.flutter.dev/get-started/install/windows
2. Pak zip-filen ud til fx `C:\src\flutter` (undgå stier med mellemrum eller
   `Program Files`).
3. Tilføj `C:\src\flutter\bin` til din PATH:
   - Søg efter "Rediger miljøvariabler for din konto" i Windows-søgning.
   - Under "Brugervariabler" → vælg `Path` → "Rediger" → "Ny" → indsæt
     `C:\src\flutter\bin`.
4. Åbn en **ny** Kommandoprompt/PowerShell og kør:
   ```
   flutter doctor
   ```
   Følg de anvisninger den giver (fx accepter Android-licenser med
   `flutter doctor --android-licenses`), indtil Android-delen er grøn ✅.
   (Chrome/VS Code-punkter er ikke nødvendige for at bygge en APK.)

## 3. Byg appen
1. Pak `lommepenge_app_kildekode.zip` ud (fx til `C:\Users\marti\Lommepenge app\lommepenge_app`).
2. Åbn en terminal i den mappe og kør:
   ```
   flutter create .
   ```
   (Dette udfylder evt. manglende platform-filer uden at røre `lib/`-mappen
   — vores Android-mappe er skrevet i hånden uden en rigtig Flutter-
   installation til at generere den, så dette skridt sikrer at alt er, som
   Flutter forventer.)
3. Kør:
   ```
   flutter pub get
   flutter analyze
   flutter test
   flutter build apk --debug
   ```
4. Hvis `flutter analyze` eller build fejler: kopiér fejlbeskeden til mig i
   vores samtale, så retter jeg koden — det er forventeligt at der kan være
   småfejl, da koden aldrig er blevet kompileret endnu (se "Kendte
   begrænsninger" i README.md).
5. Når build lykkes, ligger APK'en her:
   ```
   build\app\outputs\flutter-apk\app-debug.apk
   ```

## 4. Installér på skærm og telefon
Se afsnittet "Sådan installerer og parrer du to enheder" i `README.md`.

---
Kort sagt: skridt 1-2 er engangsopsætning af værktøjer, skridt 3 er det du
gentager, hver gang der er ny kode at bygge.
