// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Danish (`da`).
class AppLocalizationsDa extends AppLocalizations {
  AppLocalizationsDa([String locale = 'da']) : super(locale);

  @override
  String get cancel => 'Annullér';

  @override
  String get save => 'Gem';

  @override
  String get delete => 'Slet';

  @override
  String get add => 'Tilføj';

  @override
  String get name => 'Navn';

  @override
  String get nameRequired => 'Navn er påkrævet.';

  @override
  String get unknownTask => 'Ukendt opgave';

  @override
  String get unknownChild => 'Ukendt barn';

  @override
  String confirmDelete(Object name) {
    return 'Er du sikker på at du vil slette \"$name\"?';
  }

  @override
  String get language => 'Sprog';

  @override
  String get chooseLanguageTitle => 'Vælg sprog';

  @override
  String get chooseLanguageBody =>
      'Vælg appens sprog. Du kan ændre det senere.';

  @override
  String get continueButton => 'Fortsæt';

  @override
  String get connectTitle => 'Forbind til Home Assistant';

  @override
  String get connectInstructions =>
      'Tilføj enheden i Home Assistant: Indstillinger → Enheder og tjenester → Lommepenge → Tilføj enhed. Vælg navn og rolle, og tast den kode, Home Assistant viser.';

  @override
  String get codeLabel => 'Kode fra Home Assistant';

  @override
  String get codeHint => 'fx K7M2QDXA';

  @override
  String get addressLabel => 'Home Assistant-adresse';

  @override
  String get addressHint => 'fx 192.168.1.10:8123';

  @override
  String get searchingForHa => 'Leder efter Home Assistant på netværket...';

  @override
  String foundHa(Object name) {
    return 'Fundet: $name';
  }

  @override
  String get haNotFound =>
      'Ikke fundet automatisk - skriv adressen. Den står på siden med app-download i Home Assistant.';

  @override
  String get searchAgain => 'Søg igen';

  @override
  String get connectButton => 'Forbind';

  @override
  String get scanQrInstead => 'Scan QR-kode i stedet';

  @override
  String get scanQrTitle => 'Scan QR-kode';

  @override
  String get scanQrHint =>
      'Ret kameraet mod QR-koden i Home Assistant (Lommepenge → Tilføj enhed).';

  @override
  String get parentPinTitle => 'Forælder-PIN';

  @override
  String get pinPrompt =>
      'Indtast PIN-koden for at gå ind i forælder-tilstand.';

  @override
  String get pinLabel => 'PIN-kode';

  @override
  String get wrongPin => 'Forkert PIN-kode. Prøv igen.';

  @override
  String get unlock => 'Lås op';

  @override
  String get timesAndLimits => 'Tider og grænser';

  @override
  String get timesAndLimitsHint =>
      'Kan også rettes fra Home Assistant. Tryk for at ændre.';

  @override
  String get defaultDeadline => 'Standardfrist';

  @override
  String get defaultDeadlineHelp =>
      'For obligatoriske opgaver uden egen frist.';

  @override
  String get restrictionFrom => 'Spærretid fra';

  @override
  String get restrictionFromHelp =>
      'Tablets kan tidligst spærres fra dette tidspunkt.';

  @override
  String get restrictionUntil => 'Spærretid til';

  @override
  String get restrictionUntilHelp =>
      'Efter dette tidspunkt ophæves spærringen.';

  @override
  String get pauseTime => 'Pausetid';

  @override
  String get pauseTimeHelp =>
      'Ventetid før tabletten låses op, når en opgave er udført for sent.';

  @override
  String get warningBeforeDeadline => 'Advarsel før frist';

  @override
  String get warningBeforeDeadlineHelp =>
      'Hvor længe før fristen barnet advares.';

  @override
  String get winterFromWeek => 'Vinter fra uge';

  @override
  String get winterToWeek => 'Vinter til uge';

  @override
  String get winterHelp => 'Bruges til pakkelister (fx indendørssko).';

  @override
  String get minutesUnit => 'min';

  @override
  String get resetToDefaults => 'Nulstil til standard';

  @override
  String get restrictionToday => 'Spærring i dag';

  @override
  String get liftedForToday => 'Ophævet for i dag';

  @override
  String get restricted => 'Spærret';

  @override
  String get overdueOutsideWindow => 'Forsinket, men uden for spærretiden';

  @override
  String get notRestricted => 'Ikke spærret';

  @override
  String get liftToday => 'Ophæv i dag';

  @override
  String get roleFamilyScreen => 'Fælles skærm';

  @override
  String get roleParentPhone => 'Forælders telefon';

  @override
  String deviceSubtitle(Object role, Object version) {
    return '$role · app-version $version';
  }

  @override
  String get notConnected => 'Ikke forbundet';

  @override
  String get notFetchedYet => 'Ikke hentet endnu';

  @override
  String lastUpdatedAt(Object time) {
    return 'Senest opdateret kl. $time';
  }

  @override
  String get addDevicesHint =>
      'Nye enheder tilføjes i Home Assistant under Lommepenge → Tilføj enhed. Dér fjernes de også igen.';

  @override
  String get forgetConnection => 'Glem forbindelsen på denne enhed';

  @override
  String get forgetConnectionTitle => 'Glem forbindelsen?';

  @override
  String get forgetConnectionBody =>
      'Enheden skal forbindes igen med en ny kode fra Home Assistant. Fjern den også under Lommepenge i Home Assistant, hvis den ikke skal bruges mere.';

  @override
  String get forget => 'Glem';

  @override
  String get noChildrenYet =>
      'Ingen børn oprettet endnu. Tryk + for at oprette et barn.';

  @override
  String get rename => 'Omdøb';

  @override
  String get addChild => 'Tilføj barn';

  @override
  String get renameChild => 'Omdøb barn';

  @override
  String get deleteChild => 'Slet barn';

  @override
  String get parentMode => 'Forælder-tilstand';

  @override
  String get switchToChildMode => 'Skift til barne-tilstand';

  @override
  String get tabTasks => 'Opgaver';

  @override
  String get tabChildren => 'Børn';

  @override
  String get tabApprovals => 'Godkendelser';

  @override
  String get tabOverview => 'Overblik';

  @override
  String get tabHistory => 'Historik';

  @override
  String get tabSettings => 'Indstillinger';

  @override
  String get noTasksYet => 'Ingen opgaver oprettet endnu.';

  @override
  String deadlineAt(Object time) {
    return 'frist $time';
  }

  @override
  String get inCalendar => 'i kalender';

  @override
  String get deleteTask => 'Slet opgave';

  @override
  String get noPendingApprovals => 'Ingen opgaver venter på godkendelse.';

  @override
  String get late => 'for sent';

  @override
  String get approve => 'Godkend';

  @override
  String get reject => 'Afvis';

  @override
  String get adjustBalance => 'Justér saldo';

  @override
  String get adjustBalanceHelp =>
      'Brug dette til at rette en forkert saldo, fx efter en geninstallation. Beløbet kan være negativt.';

  @override
  String get child => 'Barn';

  @override
  String amountSigned(Object currency) {
    return 'Beløb ($currency, +/-)';
  }

  @override
  String get amountNonZero => 'Angiv et beløb forskelligt fra 0.';

  @override
  String get reason => 'Begrundelse';

  @override
  String get reasonRequired => 'Begrundelse er påkrævet.';

  @override
  String balanceAdjustedBy(Object amount) {
    return 'Saldo justeret med $amount.';
  }

  @override
  String get earnedNotPaidOut => 'Optjent, ikke udbetalt';

  @override
  String get paidOutTotal => 'Udbetalt i alt';

  @override
  String get markAsPaidOut => 'Marker som udbetalt';

  @override
  String confirmPayout(Object amount, Object name) {
    return 'Du er ved at markere $amount som udbetalt til $name. Denne saldo nulstilles herefter. Fortsæt?';
  }

  @override
  String get yesPayOut => 'Ja, udbetal';

  @override
  String get noCompletedTasksYet => 'Ingen fuldførte opgaver endnu.';

  @override
  String balanceAdjustment(Object note) {
    return 'Saldo-justering: $note';
  }

  @override
  String get editTask => 'Redigér opgave';

  @override
  String get newTask => 'Ny opgave';

  @override
  String get taskTitle => 'Titel';

  @override
  String get titleRequired => 'Titel er påkrævet.';

  @override
  String get descriptionOptional => 'Beskrivelse (valgfri)';

  @override
  String amountLabel(Object currency) {
    return 'Beløb ($currency)';
  }

  @override
  String get amountInvalid => 'Angiv et gyldigt beløb (0 eller derover).';

  @override
  String get recurrence => 'Gentagelse';

  @override
  String get recurrenceOnce => 'Engang';

  @override
  String get recurrenceDaily => 'Dagligt';

  @override
  String get recurrenceWeekly => 'Ugentligt';

  @override
  String get recurrenceUnlimited => 'Ubegrænset';

  @override
  String get weeklyDiscontinued =>
      'Udgået - vælg i stedet \"Dagligt\" og sæt ugeplanen til den/de ønskede dage.';

  @override
  String get unlimitedHelp =>
      'Kan udføres flere gange om dagen - blokeres kun mens en udførelse venter på godkendelse.';

  @override
  String get weekPlan => 'Ugeplan';

  @override
  String get weekPlanHelp =>
      'Vælg hvilke dage opgaven er aktiv, fx kun tirsdag og torsdag. Som standard alle dage.';

  @override
  String get allDays => 'Alle dage';

  @override
  String get weekdays => 'Hverdage';

  @override
  String get weekend => 'Weekend';

  @override
  String get assignTo => 'Tildel til';

  @override
  String get assignToHelp =>
      'Vælg hvilke børn opgaven gælder for. \"Alle børn\" gælder dynamisk - også for børn der tilføjes senere.';

  @override
  String get allChildren => 'Alle børn';

  @override
  String get mandatoryTask => 'Obligatorisk opgave';

  @override
  String get mandatoryTaskHelp =>
      'Vises tydeligt markeret som \"skal udføres\" i stedet for \"kan udføres\".';

  @override
  String get timeOfDay => 'Tidspunkt';

  @override
  String timeHelpMandatory(Object time) {
    return 'Efter fristen tæller opgaven som forsinket. Uden egen frist bruges familiens standardfrist ($time).';
  }

  @override
  String get timeHelpOptional =>
      'Valgfrit. Fristen følges kun op på obligatoriske opgaver.';

  @override
  String get fromLabel => 'Fra';

  @override
  String get deadline => 'Frist';

  @override
  String get none => 'Ingen';

  @override
  String get defaultLabel => 'Standard';

  @override
  String get removeTime => 'Fjern tid';

  @override
  String get showInCalendar => 'Vis i familiekalenderen';

  @override
  String get showInCalendarHelp =>
      'Opgaven bliver til en aftale i familiens kalender, når kalenderen er sat op.';

  @override
  String get saving => 'Gemmer...';

  @override
  String get saveTask => 'Gem opgave';

  @override
  String get sentForApproval => 'Sendt til godkendelse!';

  @override
  String get noTasksAskParent =>
      'Der er ingen opgaver endnu. Bed en forælder om at oprette nogle i forælder-tilstand.';

  @override
  String hiChild(Object name) {
    return 'Hej $name!';
  }

  @override
  String get fetchingYourTasks => 'Henter dine opgaver...';

  @override
  String get noTasksRightNow => 'Du har ingen opgaver lige nu.';

  @override
  String get noChildrenCreateInParentMode =>
      'Der er ingen børn endnu. Opret dem i forælder-tilstand.';

  @override
  String get noTasks => 'Ingen opgaver.';

  @override
  String get restrictedTitle => 'Spil og YouTube er spærret';

  @override
  String restrictedDoFirst(Object tasks) {
    return 'Lav først: $tasks. Så låses de op igen.';
  }

  @override
  String restrictedLatePause(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other:
          'Opgaven er udført for sent, så der går $minutes minutter, før din tablet bliver låst op igen.',
      one:
          'Opgaven er udført for sent, så der går 1 minut, før din tablet bliver låst op igen.',
    );
    return '$_temp0';
  }

  @override
  String get behindTitle => 'Du er bagud';

  @override
  String behindBody(Object tasks, Object time) {
    return '$tasks skulle være lavet. Spil og YouTube spærres fra kl. $time, hvis det ikke er gjort.';
  }

  @override
  String reminderTitle(Object task) {
    return 'Husk: $task';
  }

  @override
  String reminderBody(Object time) {
    return 'Skal være lavet kl. $time, ellers spærres spil og YouTube.';
  }

  @override
  String reasonOverdue(Object tasks) {
    return 'Mangler: $tasks';
  }

  @override
  String reasonOverdueTask(Object title, Object due) {
    return '$title (frist $due)';
  }

  @override
  String reasonLate(Object time) {
    return 'Opgaven er udført for sent - låses op kl. $time';
  }

  @override
  String thisWeekAmount(Object amount) {
    return 'Denne uge: $amount';
  }

  @override
  String completedThisWeek(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Denne uge: $count fuldførte opgaver',
      one: 'Denne uge: 1 fuldført opgave',
    );
    return '$_temp0';
  }

  @override
  String get syncStatus => 'Sync-status';

  @override
  String get connectedToHa => 'Forbundet til Home Assistant.';

  @override
  String get mustBeDone => 'Skal udføres';

  @override
  String fromTime(Object time) {
    return 'fra $time';
  }

  @override
  String byTime(Object time) {
    return 'senest $time';
  }

  @override
  String get notAssigned => 'Ikke tildelt noget barn i familien.';

  @override
  String get done => 'Udført';

  @override
  String get statusAvailable => 'Klar til at blive udført';

  @override
  String get statusPending => 'Venter på godkendelse';

  @override
  String get statusDoneToday => 'Udført i dag - tilgængelig igen i morgen';

  @override
  String get statusDoneThisWeek => 'Udført denne uge - tilgængelig igen';

  @override
  String statusDoneThisWeekUntil(Object date) {
    return 'Udført denne uge - tilgængelig igen ($date)';
  }

  @override
  String get statusCompleted => 'Fuldført';

  @override
  String get statusNotScheduled => 'Ikke på ugeplanen i dag';

  @override
  String statusNotScheduledUntil(Object date) {
    return 'Ikke på ugeplanen i dag ($date)';
  }

  @override
  String newVersionReady(Object version) {
    return 'Ny version $version er klar.';
  }

  @override
  String get update => 'Opdater';

  @override
  String get notLommepengeLink =>
      'Det er ikke et Lommepenge-link fra Home Assistant.';

  @override
  String get enterAddressAndCode => 'Skriv Home Assistants adresse og koden.';

  @override
  String get tabletAlreadyConnected =>
      'Denne tablet er allerede forbundet. Geninstallér appen for at forbinde den igen.';

  @override
  String get unexpectedResponse => 'Uventet svar fra Home Assistant.';

  @override
  String get notConnectedYet => 'Ikke forbundet til Home Assistant endnu.';

  @override
  String get deviceRemoved =>
      'Enheden er fjernet i Home Assistant. Forbind den igen med en ny kode fra Home Assistant (Lommepenge → Tilføj enhed).';

  @override
  String get noConnectionRetryLater =>
      'Ingen forbindelse til Home Assistant. Prøver igen senere.';

  @override
  String get updateNotificationTitle => 'Ny version af Lommepenge';

  @override
  String updateNotificationBody(Object version) {
    return 'Version $version er klar. Åbn appen for at opdatere.';
  }

  @override
  String get updatesChannel => 'Opdateringer';

  @override
  String get allowUnknownApps =>
      'Tillad \"Installér ukendte apps\" for Lommepenge, og tryk Opdater igen.';

  @override
  String get downloadCorrupt => 'Den hentede fil var beskadiget. Prøv igen.';

  @override
  String installing(Object version) {
    return 'Installerer version $version...';
  }

  @override
  String installFailed(Object error) {
    return 'Kunne ikke installere: $error';
  }

  @override
  String get installationFailed => 'Installationen mislykkedes.';

  @override
  String haRejectedConnection(Object status) {
    return 'Home Assistant afviste forbindelsen ($status).';
  }

  @override
  String get cannotReachHaHomeNetwork =>
      'Kan ikke nå Home Assistant. Er enheden på hjemmenettet?';

  @override
  String get haTimeout => 'Home Assistant svarede ikke i tide.';

  @override
  String unexpectedError(Object error) {
    return 'Uventet fejl: $error';
  }

  @override
  String haUpdateFailed(Object status) {
    return 'Home Assistant kunne ikke levere opdateringen ($status).';
  }

  @override
  String get cannotReachHa => 'Kan ikke nå Home Assistant.';

  @override
  String updateDownloadFailed(Object error) {
    return 'Kunne ikke hente opdateringen: $error';
  }

  @override
  String get deviceNoLongerConnected =>
      'Enheden er ikke længere forbundet til Home Assistant.';

  @override
  String haError(Object status) {
    return 'Home Assistant svarede med fejl ($status).';
  }

  @override
  String get noConnectionCheckNetwork =>
      'Ingen forbindelse til Home Assistant. Tjek at enheden er på hjemmenettet.';

  @override
  String get haTimeoutRetry =>
      'Home Assistant svarede ikke i tide. Prøver igen senere.';

  @override
  String get errChildNameEmpty => 'Barnets navn må ikke være tomt.';

  @override
  String get errChildNotFound => 'Barnet findes ikke længere.';

  @override
  String get errAdjustmentNote => 'En saldo-justering skal have en note.';

  @override
  String get errTaskNotFound => 'Opgaven findes ikke længere.';

  @override
  String get errTaskNotAssigned => 'Opgaven er ikke tildelt dette barn.';

  @override
  String get errTaskNotAvailable => 'Opgaven kan ikke markeres udført lige nu.';

  @override
  String get errCompletionNotFound => 'Udførelsen findes ikke.';

  @override
  String get errCompletionHandled => 'Udførelsen er allerede behandlet.';

  @override
  String get errMissingChildId =>
      'Handlingen mangler oplysning om hvilket barn (childId).';

  @override
  String get errMissingName => 'Handlingen mangler et navn.';

  @override
  String get errMissingIdOrName => 'Handlingen mangler id eller navn.';

  @override
  String get errMissingId => 'Handlingen mangler et id.';

  @override
  String get errMissingSetting => 'Handlingen mangler en indstilling.';

  @override
  String errUnknownAction(Object type) {
    return 'Ukendt handling: $type';
  }

  @override
  String errInvalidTime(Object key, Object value) {
    return 'Ugyldigt klokkeslæt for $key: $value';
  }

  @override
  String errSettingRange(Object key, Object min, Object max, Object value) {
    return '$key skal være mellem $min og $max: $value';
  }

  @override
  String errUnknownSetting(Object key) {
    return 'Ukendt indstilling: $key';
  }

  @override
  String get noConnectionTryAgain =>
      'Ingen forbindelse til Home Assistant – prøv igen';

  @override
  String get tryAgain => 'Prøv igen';

  @override
  String get statusOverdue => 'For sent - kan stadig laves';

  @override
  String statusUpcomingOn(Object date) {
    return 'Kan laves $date';
  }

  @override
  String deadlineLabel(Object time) {
    return 'Frist $time';
  }

  @override
  String get history => 'Historik';

  @override
  String get showOlder => 'Vis ældre';

  @override
  String get historyEmpty => 'Intet i denne periode.';

  @override
  String historyPeriod(Object from, Object to) {
    return '$from – $to';
  }

  @override
  String get historyApproved => 'Godkendt';

  @override
  String get historyRejected => 'Afvist';

  @override
  String get historyMissed => 'Ikke nået';

  @override
  String get historyAdjustment => 'Justering';

  @override
  String doneAt(Object time) {
    return 'lavet $time';
  }
}
