// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get cancel => 'Abbrechen';

  @override
  String get save => 'Speichern';

  @override
  String get delete => 'Löschen';

  @override
  String get add => 'Hinzufügen';

  @override
  String get name => 'Name';

  @override
  String get nameRequired => 'Ein Name ist erforderlich.';

  @override
  String get unknownTask => 'Unbekannte Aufgabe';

  @override
  String get unknownChild => 'Unbekanntes Kind';

  @override
  String confirmDelete(Object name) {
    return 'Möchtest du \"$name\" wirklich löschen?';
  }

  @override
  String get language => 'Sprache';

  @override
  String get chooseLanguageTitle => 'Sprache wählen';

  @override
  String get chooseLanguageBody =>
      'Wähle die Sprache der App. Du kannst sie später ändern.';

  @override
  String get continueButton => 'Weiter';

  @override
  String get connectTitle => 'Mit Home Assistant verbinden';

  @override
  String get connectInstructions =>
      'Füge das Gerät in Home Assistant hinzu: Einstellungen → Geräte & Dienste → Lommepenge → Gerät hinzufügen. Wähle Name und Rolle und gib den Code ein, den Home Assistant anzeigt.';

  @override
  String get codeLabel => 'Code von Home Assistant';

  @override
  String get codeHint => 'z. B. K7M2QDXA';

  @override
  String get addressLabel => 'Home Assistant-Adresse';

  @override
  String get addressHint => 'z. B. 192.168.1.10:8123';

  @override
  String get searchingForHa => 'Suche Home Assistant im Netzwerk...';

  @override
  String foundHa(Object name) {
    return 'Gefunden: $name';
  }

  @override
  String get haNotFound =>
      'Nicht automatisch gefunden - gib die Adresse ein. Sie steht auf der Seite mit dem App-Download in Home Assistant.';

  @override
  String get searchAgain => 'Erneut suchen';

  @override
  String get connectButton => 'Verbinden';

  @override
  String get scanQrInstead => 'Stattdessen QR-Code scannen';

  @override
  String get scanQrTitle => 'QR-Code scannen';

  @override
  String get scanQrHint =>
      'Richte die Kamera auf den QR-Code in Home Assistant (Lommepenge → Gerät hinzufügen).';

  @override
  String get parentPinTitle => 'Eltern-PIN';

  @override
  String get pinPrompt => 'Gib die PIN ein, um in den Elternmodus zu wechseln.';

  @override
  String get pinLabel => 'PIN';

  @override
  String get wrongPin => 'Falsche PIN. Versuche es erneut.';

  @override
  String get unlock => 'Entsperren';

  @override
  String get timesAndLimits => 'Zeiten und Grenzen';

  @override
  String get timesAndLimitsHint =>
      'Kann auch in Home Assistant geändert werden. Tippe zum Ändern.';

  @override
  String get defaultDeadline => 'Standardfrist';

  @override
  String get defaultDeadlineHelp => 'Für Pflichtaufgaben ohne eigene Frist.';

  @override
  String get restrictionFrom => 'Sperrzeit ab';

  @override
  String get restrictionFromHelp =>
      'Tablets können frühestens ab dieser Uhrzeit gesperrt werden.';

  @override
  String get restrictionUntil => 'Sperrzeit bis';

  @override
  String get restrictionUntilHelp =>
      'Nach dieser Uhrzeit wird die Sperre aufgehoben.';

  @override
  String get pauseTime => 'Pausenzeit';

  @override
  String get pauseTimeHelp =>
      'Wartezeit, bevor das Tablet entsperrt wird, wenn eine Aufgabe zu spät erledigt wurde.';

  @override
  String get warningBeforeDeadline => 'Warnung vor der Frist';

  @override
  String get warningBeforeDeadlineHelp =>
      'Wie lange vor der Frist das Kind gewarnt wird.';

  @override
  String get winterFromWeek => 'Winter ab Woche';

  @override
  String get winterToWeek => 'Winter bis Woche';

  @override
  String get winterHelp => 'Wird für Packlisten verwendet (z. B. Hausschuhe).';

  @override
  String get minutesUnit => 'Min.';

  @override
  String get resetToDefaults => 'Auf Standard zurücksetzen';

  @override
  String get restrictionToday => 'Sperre heute';

  @override
  String get liftedForToday => 'Für heute aufgehoben';

  @override
  String get restricted => 'Gesperrt';

  @override
  String get overdueOutsideWindow => 'Überfällig, aber außerhalb der Sperrzeit';

  @override
  String get notRestricted => 'Nicht gesperrt';

  @override
  String get liftToday => 'Heute aufheben';

  @override
  String get roleFamilyScreen => 'Familienbildschirm';

  @override
  String get roleParentPhone => 'Handy eines Elternteils';

  @override
  String deviceSubtitle(Object role, Object version) {
    return '$role · App-Version $version';
  }

  @override
  String get notConnected => 'Nicht verbunden';

  @override
  String get notFetchedYet => 'Noch nicht abgerufen';

  @override
  String lastUpdatedAt(Object time) {
    return 'Zuletzt aktualisiert um $time';
  }

  @override
  String get addDevicesHint =>
      'Neue Geräte werden in Home Assistant unter Lommepenge → Gerät hinzufügen hinzugefügt. Dort werden sie auch wieder entfernt.';

  @override
  String get forgetConnection => 'Verbindung auf diesem Gerät vergessen';

  @override
  String get forgetConnectionTitle => 'Verbindung vergessen?';

  @override
  String get forgetConnectionBody =>
      'Das Gerät muss mit einem neuen Code aus Home Assistant erneut verbunden werden. Entferne es auch unter Lommepenge in Home Assistant, wenn es nicht mehr verwendet wird.';

  @override
  String get forget => 'Vergessen';

  @override
  String get noChildrenYet =>
      'Noch keine Kinder angelegt. Tippe auf +, um ein Kind anzulegen.';

  @override
  String get rename => 'Umbenennen';

  @override
  String get addChild => 'Kind hinzufügen';

  @override
  String get renameChild => 'Kind umbenennen';

  @override
  String get deleteChild => 'Kind löschen';

  @override
  String get parentMode => 'Elternmodus';

  @override
  String get switchToChildMode => 'Zum Kindermodus wechseln';

  @override
  String get tabTasks => 'Aufgaben';

  @override
  String get tabChildren => 'Kinder';

  @override
  String get tabApprovals => 'Freigaben';

  @override
  String get tabOverview => 'Übersicht';

  @override
  String get tabHistory => 'Verlauf';

  @override
  String get tabSettings => 'Einstellungen';

  @override
  String get noTasksYet => 'Noch keine Aufgaben angelegt.';

  @override
  String deadlineAt(Object time) {
    return 'Frist $time';
  }

  @override
  String get inCalendar => 'im Kalender';

  @override
  String get deleteTask => 'Aufgabe löschen';

  @override
  String get noPendingApprovals => 'Keine Aufgaben warten auf Freigabe.';

  @override
  String get late => 'zu spät';

  @override
  String get approve => 'Freigeben';

  @override
  String get reject => 'Ablehnen';

  @override
  String get adjustBalance => 'Guthaben korrigieren';

  @override
  String get adjustBalanceHelp =>
      'Damit korrigierst du ein falsches Guthaben, z. B. nach einer Neuinstallation. Der Betrag darf negativ sein.';

  @override
  String get child => 'Kind';

  @override
  String amountSigned(Object currency) {
    return 'Betrag ($currency, +/-)';
  }

  @override
  String get amountNonZero => 'Gib einen Betrag ungleich 0 ein.';

  @override
  String get reason => 'Begründung';

  @override
  String get reasonRequired => 'Eine Begründung ist erforderlich.';

  @override
  String balanceAdjustedBy(Object amount) {
    return 'Guthaben um $amount korrigiert.';
  }

  @override
  String get earnedNotPaidOut => 'Verdient, nicht ausgezahlt';

  @override
  String get paidOutTotal => 'Insgesamt ausgezahlt';

  @override
  String get markAsPaidOut => 'Als ausgezahlt markieren';

  @override
  String confirmPayout(Object amount, Object name) {
    return 'Du markierst $amount als an $name ausgezahlt. Das Guthaben wird danach auf null gesetzt. Fortfahren?';
  }

  @override
  String get yesPayOut => 'Ja, auszahlen';

  @override
  String get noCompletedTasksYet => 'Noch keine erledigten Aufgaben.';

  @override
  String balanceAdjustment(Object note) {
    return 'Guthabenkorrektur: $note';
  }

  @override
  String get editTask => 'Aufgabe bearbeiten';

  @override
  String get newTask => 'Neue Aufgabe';

  @override
  String get taskTitle => 'Titel';

  @override
  String get titleRequired => 'Ein Titel ist erforderlich.';

  @override
  String get descriptionOptional => 'Beschreibung (optional)';

  @override
  String amountLabel(Object currency) {
    return 'Betrag ($currency)';
  }

  @override
  String get amountInvalid => 'Gib einen gültigen Betrag ein (0 oder mehr).';

  @override
  String get recurrence => 'Wiederholung';

  @override
  String get recurrenceOnce => 'Einmalig';

  @override
  String get recurrenceDaily => 'Täglich';

  @override
  String get recurrenceWeekly => 'Wöchentlich';

  @override
  String get recurrenceUnlimited => 'Unbegrenzt';

  @override
  String get weeklyDiscontinued =>
      'Nicht mehr verfügbar - wähle stattdessen \"Täglich\" und stelle den Wochenplan auf den/die gewünschten Tag(e).';

  @override
  String get unlimitedHelp =>
      'Kann mehrmals am Tag erledigt werden - nur gesperrt, solange eine Erledigung auf Freigabe wartet.';

  @override
  String get weekPlan => 'Wochenplan';

  @override
  String get weekPlanHelp =>
      'Wähle, an welchen Tagen die Aufgabe aktiv ist, z. B. nur Dienstag und Donnerstag. Standardmäßig jeden Tag.';

  @override
  String get allDays => 'Jeden Tag';

  @override
  String get weekdays => 'Werktags';

  @override
  String get weekend => 'Wochenende';

  @override
  String get assignTo => 'Zuweisen an';

  @override
  String get assignToHelp =>
      'Wähle, für welche Kinder die Aufgabe gilt. \"Alle Kinder\" gilt dynamisch - auch für später hinzugefügte Kinder.';

  @override
  String get allChildren => 'Alle Kinder';

  @override
  String get mandatoryTask => 'Pflichtaufgabe';

  @override
  String get mandatoryTaskHelp =>
      'Wird deutlich als \"muss erledigt werden\" statt \"kann erledigt werden\" markiert.';

  @override
  String get timeOfDay => 'Uhrzeit';

  @override
  String timeHelpMandatory(Object time) {
    return 'Nach der Frist gilt die Aufgabe als überfällig. Ohne eigene Frist gilt die Standardfrist der Familie ($time).';
  }

  @override
  String get timeHelpOptional =>
      'Optional. Die Frist wird nur bei Pflichtaufgaben verfolgt.';

  @override
  String get fromLabel => 'Ab';

  @override
  String get deadline => 'Frist';

  @override
  String get none => 'Keine';

  @override
  String get defaultLabel => 'Standard';

  @override
  String get removeTime => 'Uhrzeit entfernen';

  @override
  String get showInCalendar => 'Im Familienkalender anzeigen';

  @override
  String get showInCalendarHelp =>
      'Die Aufgabe wird zu einem Termin im Familienkalender, sobald der Kalender eingerichtet ist.';

  @override
  String get saving => 'Speichern...';

  @override
  String get saveTask => 'Aufgabe speichern';

  @override
  String get sentForApproval => 'Zur Freigabe gesendet!';

  @override
  String get noTasksAskParent =>
      'Es gibt noch keine Aufgaben. Bitte ein Elternteil, im Elternmodus welche anzulegen.';

  @override
  String hiChild(Object name) {
    return 'Hallo $name!';
  }

  @override
  String get fetchingYourTasks => 'Deine Aufgaben werden geladen...';

  @override
  String get noTasksRightNow => 'Du hast gerade keine Aufgaben.';

  @override
  String get noChildrenCreateInParentMode =>
      'Es gibt noch keine Kinder. Lege sie im Elternmodus an.';

  @override
  String get noTasks => 'Keine Aufgaben.';

  @override
  String get restrictedTitle => 'Spiele und YouTube sind gesperrt';

  @override
  String restrictedDoFirst(Object tasks) {
    return 'Erledige zuerst: $tasks. Dann werden sie wieder entsperrt.';
  }

  @override
  String restrictedLatePause(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other:
          'Die Aufgabe wurde zu spät erledigt, deshalb dauert es $minutes Minuten, bis dein Tablet wieder entsperrt wird.',
      one:
          'Die Aufgabe wurde zu spät erledigt, deshalb dauert es 1 Minute, bis dein Tablet wieder entsperrt wird.',
    );
    return '$_temp0';
  }

  @override
  String get behindTitle => 'Du bist im Rückstand';

  @override
  String behindBody(Object tasks, Object time) {
    return '$tasks hätte erledigt sein sollen. Spiele und YouTube werden ab $time Uhr gesperrt, wenn es nicht erledigt ist.';
  }

  @override
  String reminderTitle(Object task) {
    return 'Denk an: $task';
  }

  @override
  String reminderBody(Object time) {
    return 'Muss bis $time Uhr erledigt sein, sonst werden Spiele und YouTube gesperrt.';
  }

  @override
  String reasonOverdue(Object tasks) {
    return 'Fehlt: $tasks';
  }

  @override
  String reasonOverdueTask(Object title, Object due) {
    return '$title (fällig $due)';
  }

  @override
  String reasonLate(Object time) {
    return 'Die Aufgabe wurde zu spät erledigt - wird um $time entsperrt';
  }

  @override
  String thisWeekAmount(Object amount) {
    return 'Diese Woche: $amount';
  }

  @override
  String completedThisWeek(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Diese Woche: $count erledigte Aufgaben',
      one: 'Diese Woche: 1 erledigte Aufgabe',
    );
    return '$_temp0';
  }

  @override
  String get syncStatus => 'Sync-Status';

  @override
  String get connectedToHa => 'Mit Home Assistant verbunden.';

  @override
  String get mustBeDone => 'Muss erledigt werden';

  @override
  String fromTime(Object time) {
    return 'ab $time';
  }

  @override
  String byTime(Object time) {
    return 'bis $time';
  }

  @override
  String get notAssigned => 'Keinem Kind der Familie zugewiesen.';

  @override
  String get done => 'Erledigt';

  @override
  String get statusAvailable => 'Bereit zum Erledigen';

  @override
  String get statusPending => 'Wartet auf Freigabe';

  @override
  String get statusDoneToday => 'Heute erledigt - morgen wieder verfügbar';

  @override
  String get statusDoneThisWeek =>
      'Diese Woche erledigt - bald wieder verfügbar';

  @override
  String statusDoneThisWeekUntil(Object date) {
    return 'Diese Woche erledigt - wieder verfügbar ($date)';
  }

  @override
  String get statusCompleted => 'Abgeschlossen';

  @override
  String get statusNotScheduled => 'Heute nicht im Wochenplan';

  @override
  String statusNotScheduledUntil(Object date) {
    return 'Heute nicht im Wochenplan ($date)';
  }

  @override
  String newVersionReady(Object version) {
    return 'Neue Version $version ist bereit.';
  }

  @override
  String get update => 'Aktualisieren';

  @override
  String get notLommepengeLink =>
      'Das ist kein Lommepenge-Link aus Home Assistant.';

  @override
  String get enterAddressAndCode =>
      'Gib die Adresse von Home Assistant und den Code ein.';

  @override
  String get tabletAlreadyConnected =>
      'Dieses Tablet ist bereits verbunden. Installiere die App neu, um es erneut zu verbinden.';

  @override
  String get unexpectedResponse => 'Unerwartete Antwort von Home Assistant.';

  @override
  String get notConnectedYet => 'Noch nicht mit Home Assistant verbunden.';

  @override
  String get deviceRemoved =>
      'Das Gerät wurde in Home Assistant entfernt. Verbinde es erneut mit einem neuen Code aus Home Assistant (Lommepenge → Gerät hinzufügen).';

  @override
  String get noConnectionRetryLater =>
      'Keine Verbindung zu Home Assistant. Neuer Versuch später.';

  @override
  String get updateNotificationTitle => 'Neue Version von Lommepenge';

  @override
  String updateNotificationBody(Object version) {
    return 'Version $version ist bereit. Öffne die App, um zu aktualisieren.';
  }

  @override
  String get updatesChannel => 'Updates';

  @override
  String get allowUnknownApps =>
      'Erlaube \"Unbekannte Apps installieren\" für Lommepenge und tippe erneut auf Aktualisieren.';

  @override
  String get downloadCorrupt =>
      'Die heruntergeladene Datei war beschädigt. Versuche es erneut.';

  @override
  String installing(Object version) {
    return 'Version $version wird installiert...';
  }

  @override
  String installFailed(Object error) {
    return 'Installation nicht möglich: $error';
  }

  @override
  String get installationFailed => 'Die Installation ist fehlgeschlagen.';

  @override
  String haRejectedConnection(Object status) {
    return 'Home Assistant hat die Verbindung abgelehnt ($status).';
  }

  @override
  String get cannotReachHaHomeNetwork =>
      'Home Assistant ist nicht erreichbar. Ist das Gerät im Heimnetz?';

  @override
  String get haTimeout => 'Home Assistant hat nicht rechtzeitig geantwortet.';

  @override
  String unexpectedError(Object error) {
    return 'Unerwarteter Fehler: $error';
  }

  @override
  String haUpdateFailed(Object status) {
    return 'Home Assistant konnte das Update nicht liefern ($status).';
  }

  @override
  String get cannotReachHa => 'Home Assistant ist nicht erreichbar.';

  @override
  String updateDownloadFailed(Object error) {
    return 'Das Update konnte nicht heruntergeladen werden: $error';
  }

  @override
  String get deviceNoLongerConnected =>
      'Das Gerät ist nicht mehr mit Home Assistant verbunden.';

  @override
  String haError(Object status) {
    return 'Home Assistant hat mit einem Fehler geantwortet ($status).';
  }

  @override
  String get noConnectionCheckNetwork =>
      'Keine Verbindung zu Home Assistant. Prüfe, ob das Gerät im Heimnetz ist.';

  @override
  String get haTimeoutRetry =>
      'Home Assistant hat nicht rechtzeitig geantwortet. Neuer Versuch später.';

  @override
  String get errChildNameEmpty => 'Der Name des Kindes darf nicht leer sein.';

  @override
  String get errChildNotFound => 'Das Kind existiert nicht mehr.';

  @override
  String get errAdjustmentNote => 'Eine Guthabenkorrektur braucht eine Notiz.';

  @override
  String get errTaskNotFound => 'Die Aufgabe existiert nicht mehr.';

  @override
  String get errTaskNotAssigned =>
      'Die Aufgabe ist diesem Kind nicht zugewiesen.';

  @override
  String get errTaskNotAvailable =>
      'Die Aufgabe kann gerade nicht als erledigt markiert werden.';

  @override
  String get errCompletionNotFound => 'Die Erledigung existiert nicht.';

  @override
  String get errCompletionHandled => 'Die Erledigung wurde bereits bearbeitet.';

  @override
  String get errMissingChildId =>
      'Der Aktion fehlt die Angabe, für welches Kind sie gilt (childId).';

  @override
  String get errMissingName => 'Der Aktion fehlt ein Name.';

  @override
  String get errMissingIdOrName => 'Der Aktion fehlt eine ID oder ein Name.';

  @override
  String get errMissingId => 'Der Aktion fehlt eine ID.';

  @override
  String get errMissingSetting => 'Der Aktion fehlt eine Einstellung.';

  @override
  String errUnknownAction(Object type) {
    return 'Unbekannte Aktion: $type';
  }

  @override
  String errInvalidTime(Object key, Object value) {
    return 'Ungültige Uhrzeit für $key: $value';
  }

  @override
  String errSettingRange(Object key, Object min, Object max, Object value) {
    return '$key muss zwischen $min und $max liegen: $value';
  }

  @override
  String errUnknownSetting(Object key) {
    return 'Unbekannte Einstellung: $key';
  }

  @override
  String get noConnectionTryAgain =>
      'Keine Verbindung zu Home Assistant – versuche es erneut';

  @override
  String get tryAgain => 'Erneut versuchen';

  @override
  String get statusOverdue => 'Überfällig - kann noch erledigt werden';

  @override
  String statusUpcomingOn(Object date) {
    return 'Möglich am $date';
  }

  @override
  String deadlineLabel(Object time) {
    return 'Frist $time';
  }

  @override
  String get history => 'Verlauf';

  @override
  String get showOlder => 'Ältere anzeigen';

  @override
  String get historyEmpty => 'Nichts in diesem Zeitraum.';

  @override
  String historyPeriod(Object from, Object to) {
    return '$from – $to';
  }

  @override
  String get historyApproved => 'Genehmigt';

  @override
  String get historyRejected => 'Abgelehnt';

  @override
  String get historyMissed => 'Verpasst';

  @override
  String get historyAdjustment => 'Korrektur';

  @override
  String doneAt(Object time) {
    return 'erledigt $time';
  }
}
