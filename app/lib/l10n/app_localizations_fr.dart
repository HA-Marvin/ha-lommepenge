// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get cancel => 'Annuler';

  @override
  String get save => 'Enregistrer';

  @override
  String get delete => 'Supprimer';

  @override
  String get add => 'Ajouter';

  @override
  String get name => 'Nom';

  @override
  String get nameRequired => 'Le nom est obligatoire.';

  @override
  String get unknownTask => 'Tâche inconnue';

  @override
  String get unknownChild => 'Enfant inconnu';

  @override
  String confirmDelete(Object name) {
    return 'Veux-tu vraiment supprimer « $name » ?';
  }

  @override
  String get language => 'Langue';

  @override
  String get chooseLanguageTitle => 'Choisir la langue';

  @override
  String get chooseLanguageBody =>
      'Choisis la langue de l\'application. Tu pourras la changer plus tard.';

  @override
  String get continueButton => 'Continuer';

  @override
  String get connectTitle => 'Se connecter à Home Assistant';

  @override
  String get connectInstructions =>
      'Ajoute l\'appareil dans Home Assistant : Paramètres → Appareils et services → Lommepenge → Ajouter un appareil. Choisis un nom et un rôle, puis saisis le code affiché par Home Assistant.';

  @override
  String get codeLabel => 'Code de Home Assistant';

  @override
  String get codeHint => 'p. ex. K7M2QDXA';

  @override
  String get addressLabel => 'Adresse de Home Assistant';

  @override
  String get addressHint => 'p. ex. 192.168.1.10:8123';

  @override
  String get searchingForHa => 'Recherche de Home Assistant sur le réseau...';

  @override
  String foundHa(Object name) {
    return 'Trouvé : $name';
  }

  @override
  String get haNotFound =>
      'Introuvable automatiquement - saisis l\'adresse. Elle figure sur la page de téléchargement de l\'application dans Home Assistant.';

  @override
  String get searchAgain => 'Rechercher à nouveau';

  @override
  String get connectButton => 'Se connecter';

  @override
  String get scanQrInstead => 'Scanner un code QR à la place';

  @override
  String get scanQrTitle => 'Scanner le code QR';

  @override
  String get scanQrHint =>
      'Dirige la caméra vers le code QR dans Home Assistant (Lommepenge → Ajouter un appareil).';

  @override
  String get parentPinTitle => 'PIN parent';

  @override
  String get pinPrompt => 'Saisis le PIN pour passer en mode parent.';

  @override
  String get pinLabel => 'PIN';

  @override
  String get wrongPin => 'PIN incorrect. Réessaie.';

  @override
  String get unlock => 'Déverrouiller';

  @override
  String get timesAndLimits => 'Horaires et limites';

  @override
  String get timesAndLimitsHint =>
      'Modifiable aussi depuis Home Assistant. Appuie pour modifier.';

  @override
  String get defaultDeadline => 'Échéance par défaut';

  @override
  String get defaultDeadlineHelp =>
      'Pour les tâches obligatoires sans échéance propre.';

  @override
  String get pauseTime => 'Verrouillage court en cas de retard';

  @override
  String get pauseTimeHelp =>
      'Durée du verrouillage quand une tâche en retard est faite avant le début de son verrouillage (0 = aucun verrouillage).';

  @override
  String get warningBeforeDeadline => 'Avertissement avant l\'échéance';

  @override
  String get warningBeforeDeadlineHelp =>
      'Combien de temps avant l\'échéance l\'enfant est averti.';

  @override
  String get winterFromWeek => 'Hiver à partir de la semaine';

  @override
  String get winterToWeek => 'Hiver jusqu\'à la semaine';

  @override
  String get winterHelp =>
      'Utilisé pour les listes d\'affaires (p. ex. chaussons).';

  @override
  String get minutesUnit => 'min';

  @override
  String get resetToDefaults => 'Rétablir les valeurs par défaut';

  @override
  String get roleFamilyScreen => 'Écran familial';

  @override
  String get roleParentPhone => 'Téléphone d\'un parent';

  @override
  String deviceSubtitle(Object role, Object version) {
    return '$role · version de l\'application $version';
  }

  @override
  String get notConnected => 'Non connecté';

  @override
  String get notFetchedYet => 'Pas encore récupéré';

  @override
  String lastUpdatedAt(Object time) {
    return 'Dernière mise à jour à $time';
  }

  @override
  String get addDevicesHint =>
      'Les nouveaux appareils s\'ajoutent dans Home Assistant sous Lommepenge → Ajouter un appareil. C\'est aussi là qu\'on les supprime.';

  @override
  String get forgetConnection => 'Oublier la connexion sur cet appareil';

  @override
  String get forgetConnectionTitle => 'Oublier la connexion ?';

  @override
  String get forgetConnectionBody =>
      'L\'appareil devra être reconnecté avec un nouveau code de Home Assistant. Supprime-le aussi sous Lommepenge dans Home Assistant s\'il ne sert plus.';

  @override
  String get forget => 'Oublier';

  @override
  String get noChildrenYet =>
      'Aucun enfant pour l\'instant. Appuie sur + pour créer un enfant.';

  @override
  String get rename => 'Renommer';

  @override
  String get addChild => 'Ajouter un enfant';

  @override
  String get renameChild => 'Renommer l\'enfant';

  @override
  String get deleteChild => 'Supprimer l\'enfant';

  @override
  String get parentMode => 'Mode parent';

  @override
  String get switchToChildMode => 'Passer en mode enfant';

  @override
  String get tabTasks => 'Tâches';

  @override
  String get tabChildren => 'Enfants';

  @override
  String get tabApprovals => 'Validations';

  @override
  String get tabOverview => 'Aperçu';

  @override
  String get tabHistory => 'Historique';

  @override
  String get tabSettings => 'Paramètres';

  @override
  String get noTasksYet => 'Aucune tâche pour l\'instant.';

  @override
  String deadlineAt(Object time) {
    return 'échéance $time';
  }

  @override
  String get inCalendar => 'dans le calendrier';

  @override
  String get deleteTask => 'Supprimer la tâche';

  @override
  String get noPendingApprovals => 'Aucune tâche n\'attend de validation.';

  @override
  String get late => 'en retard';

  @override
  String get approve => 'Valider';

  @override
  String get reject => 'Refuser';

  @override
  String get adjustBalance => 'Ajuster le solde';

  @override
  String get adjustBalanceHelp =>
      'Sert à corriger un solde erroné, p. ex. après une réinstallation. Le montant peut être négatif.';

  @override
  String get child => 'Enfant';

  @override
  String amountSigned(Object currency) {
    return 'Montant ($currency, +/-)';
  }

  @override
  String get amountNonZero => 'Saisis un montant différent de 0.';

  @override
  String get reason => 'Motif';

  @override
  String get reasonRequired => 'Le motif est obligatoire.';

  @override
  String balanceAdjustedBy(Object amount) {
    return 'Solde ajusté de $amount.';
  }

  @override
  String get earnedNotPaidOut => 'Gagné, non versé';

  @override
  String get paidOutTotal => 'Total versé';

  @override
  String get markAsPaidOut => 'Marquer comme versé';

  @override
  String confirmPayout(Object amount, Object name) {
    return 'Tu vas marquer $amount comme versé à $name. Ce solde sera ensuite remis à zéro. Continuer ?';
  }

  @override
  String get yesPayOut => 'Oui, verser';

  @override
  String get noCompletedTasksYet => 'Aucune tâche terminée pour l\'instant.';

  @override
  String balanceAdjustment(Object note) {
    return 'Ajustement de solde : $note';
  }

  @override
  String get editTask => 'Modifier la tâche';

  @override
  String get newTask => 'Nouvelle tâche';

  @override
  String get taskTitle => 'Titre';

  @override
  String get titleRequired => 'Le titre est obligatoire.';

  @override
  String get descriptionOptional => 'Description (facultative)';

  @override
  String amountLabel(Object currency) {
    return 'Montant ($currency)';
  }

  @override
  String get amountInvalid => 'Saisis un montant valide (0 ou plus).';

  @override
  String get recurrence => 'Répétition';

  @override
  String get recurrenceOnce => 'Une fois';

  @override
  String get recurrenceDaily => 'Quotidienne';

  @override
  String get recurrenceWeekly => 'Hebdomadaire';

  @override
  String get recurrenceUnlimited => 'Illimitée';

  @override
  String get weeklyDiscontinued =>
      'N\'est plus proposé - choisis plutôt « Quotidienne » et règle le planning hebdomadaire sur le ou les jours voulus.';

  @override
  String get unlimitedHelp =>
      'Peut être faite plusieurs fois par jour - bloquée seulement tant qu\'une réalisation attend une validation.';

  @override
  String get weekPlan => 'Planning hebdomadaire';

  @override
  String get weekPlanHelp =>
      'Choisis les jours où la tâche est active, p. ex. seulement le mardi et le jeudi. Par défaut tous les jours.';

  @override
  String get allDays => 'Tous les jours';

  @override
  String get weekdays => 'En semaine';

  @override
  String get weekend => 'Week-end';

  @override
  String get assignTo => 'Attribuer à';

  @override
  String get assignToHelp =>
      'Choisis à quels enfants la tâche s\'applique. « Tous les enfants » s\'applique de façon dynamique - aussi aux enfants ajoutés plus tard.';

  @override
  String get allChildren => 'Tous les enfants';

  @override
  String get mandatoryTask => 'Tâche obligatoire';

  @override
  String get mandatoryTaskHelp =>
      'Clairement marquée « à faire » au lieu de « peut être faite ».';

  @override
  String get timeOfDay => 'Horaire';

  @override
  String timeHelpMandatory(Object time) {
    return 'Après l\'échéance, la tâche compte comme en retard. Sans échéance propre, l\'échéance par défaut de la famille s\'applique ($time).';
  }

  @override
  String get timeHelpOptional =>
      'Facultatif. L\'échéance n\'est suivie que pour les tâches obligatoires.';

  @override
  String get fromLabel => 'À partir de';

  @override
  String get deadline => 'Échéance';

  @override
  String get none => 'Aucune';

  @override
  String get defaultLabel => 'Par défaut';

  @override
  String get removeTime => 'Supprimer l\'heure';

  @override
  String get showInCalendar => 'Afficher dans le calendrier familial';

  @override
  String get showInCalendarHelp =>
      'La tâche devient un événement du calendrier familial une fois le calendrier configuré.';

  @override
  String get saving => 'Enregistrement...';

  @override
  String get saveTask => 'Enregistrer la tâche';

  @override
  String get sentForApproval => 'Envoyé pour validation !';

  @override
  String get noTasksAskParent =>
      'Il n\'y a pas encore de tâches. Demande à un parent d\'en créer en mode parent.';

  @override
  String hiChild(Object name) {
    return 'Salut $name !';
  }

  @override
  String get fetchingYourTasks => 'Chargement de tes tâches...';

  @override
  String get noTasksRightNow => 'Tu n\'as aucune tâche pour le moment.';

  @override
  String get noChildrenCreateInParentMode =>
      'Il n\'y a pas encore d\'enfants. Crée-les en mode parent.';

  @override
  String get noTasks => 'Aucune tâche.';

  @override
  String thisWeekAmount(Object amount) {
    return 'Cette semaine : $amount';
  }

  @override
  String completedThisWeek(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Cette semaine : $count tâches terminées',
      one: 'Cette semaine : 1 tâche terminée',
    );
    return '$_temp0';
  }

  @override
  String get syncStatus => 'État de la synchronisation';

  @override
  String get connectedToHa => 'Connecté à Home Assistant.';

  @override
  String get mustBeDone => 'À faire';

  @override
  String fromTime(Object time) {
    return 'à partir de $time';
  }

  @override
  String byTime(Object time) {
    return 'avant $time';
  }

  @override
  String get notAssigned => 'Attribuée à aucun enfant de la famille.';

  @override
  String get done => 'Fait';

  @override
  String get statusAvailable => 'Prête à être faite';

  @override
  String get statusPending => 'En attente de validation';

  @override
  String get statusDoneToday =>
      'Faite aujourd\'hui - de nouveau disponible demain';

  @override
  String get statusDoneThisWeek =>
      'Faite cette semaine - bientôt de nouveau disponible';

  @override
  String statusDoneThisWeekUntil(Object date) {
    return 'Faite cette semaine - de nouveau disponible ($date)';
  }

  @override
  String get statusCompleted => 'Terminée';

  @override
  String get statusNotScheduled => 'Pas au planning aujourd\'hui';

  @override
  String statusNotScheduledUntil(Object date) {
    return 'Pas au planning aujourd\'hui ($date)';
  }

  @override
  String newVersionReady(Object version) {
    return 'La nouvelle version $version est prête.';
  }

  @override
  String get update => 'Mettre à jour';

  @override
  String get notLommepengeLink =>
      'Ce n\'est pas un lien Lommepenge de Home Assistant.';

  @override
  String get enterAddressAndCode =>
      'Saisis l\'adresse de Home Assistant et le code.';

  @override
  String get tabletAlreadyConnected =>
      'Cette tablette est déjà connectée. Réinstalle l\'application pour la reconnecter.';

  @override
  String get unexpectedResponse => 'Réponse inattendue de Home Assistant.';

  @override
  String get notConnectedYet => 'Pas encore connecté à Home Assistant.';

  @override
  String get deviceRemoved =>
      'L\'appareil a été supprimé dans Home Assistant. Reconnecte-le avec un nouveau code de Home Assistant (Lommepenge → Ajouter un appareil).';

  @override
  String get noConnectionRetryLater =>
      'Pas de connexion à Home Assistant. Nouvelle tentative plus tard.';

  @override
  String get updateNotificationTitle => 'Nouvelle version de Lommepenge';

  @override
  String updateNotificationBody(Object version) {
    return 'La version $version est prête. Ouvre l\'application pour la mettre à jour.';
  }

  @override
  String get updatesChannel => 'Mises à jour';

  @override
  String get allowUnknownApps =>
      'Autorise « Installer des applis inconnues » pour Lommepenge, puis appuie à nouveau sur Mettre à jour.';

  @override
  String get downloadCorrupt =>
      'Le fichier téléchargé était endommagé. Réessaie.';

  @override
  String installing(Object version) {
    return 'Installation de la version $version...';
  }

  @override
  String installFailed(Object error) {
    return 'Installation impossible : $error';
  }

  @override
  String get installationFailed => 'L\'installation a échoué.';

  @override
  String haRejectedConnection(Object status) {
    return 'Home Assistant a refusé la connexion ($status).';
  }

  @override
  String get cannotReachHaHomeNetwork =>
      'Impossible de joindre Home Assistant. L\'appareil est-il sur le réseau domestique ?';

  @override
  String get haTimeout => 'Home Assistant n\'a pas répondu à temps.';

  @override
  String unexpectedError(Object error) {
    return 'Erreur inattendue : $error';
  }

  @override
  String haUpdateFailed(Object status) {
    return 'Home Assistant n\'a pas pu fournir la mise à jour ($status).';
  }

  @override
  String get cannotReachHa => 'Impossible de joindre Home Assistant.';

  @override
  String updateDownloadFailed(Object error) {
    return 'Impossible de télécharger la mise à jour : $error';
  }

  @override
  String get deviceNoLongerConnected =>
      'L\'appareil n\'est plus connecté à Home Assistant.';

  @override
  String haError(Object status) {
    return 'Home Assistant a répondu par une erreur ($status).';
  }

  @override
  String get noConnectionCheckNetwork =>
      'Pas de connexion à Home Assistant. Vérifie que l\'appareil est sur le réseau domestique.';

  @override
  String get haTimeoutRetry =>
      'Home Assistant n\'a pas répondu à temps. Nouvelle tentative plus tard.';

  @override
  String get errChildNameEmpty => 'Le nom de l\'enfant ne peut pas être vide.';

  @override
  String get errChildNotFound => 'L\'enfant n\'existe plus.';

  @override
  String get errAdjustmentNote => 'Un ajustement de solde doit avoir une note.';

  @override
  String get errTaskNotFound => 'La tâche n\'existe plus.';

  @override
  String get errTaskNotAssigned =>
      'La tâche n\'est pas attribuée à cet enfant.';

  @override
  String get errTaskNotAvailable =>
      'La tâche ne peut pas être marquée comme faite pour le moment.';

  @override
  String get errCompletionNotFound => 'La réalisation n\'existe pas.';

  @override
  String get errCompletionHandled => 'La réalisation a déjà été traitée.';

  @override
  String get errMissingChildId =>
      'L\'action n\'indique pas pour quel enfant elle est (childId).';

  @override
  String get errMissingName => 'Il manque un nom à l\'action.';

  @override
  String get errMissingIdOrName =>
      'Il manque un identifiant ou un nom à l\'action.';

  @override
  String get errMissingId => 'Il manque un identifiant à l\'action.';

  @override
  String get errMissingSetting => 'Il manque un paramètre à l\'action.';

  @override
  String errUnknownAction(Object type) {
    return 'Action inconnue : $type';
  }

  @override
  String errInvalidTime(Object key, Object value) {
    return 'Heure non valide pour $key : $value';
  }

  @override
  String errSettingRange(Object key, Object min, Object max, Object value) {
    return '$key doit être compris entre $min et $max : $value';
  }

  @override
  String errUnknownSetting(Object key) {
    return 'Paramètre inconnu : $key';
  }

  @override
  String get noConnectionTryAgain =>
      'Pas de connexion à Home Assistant – réessaie';

  @override
  String get tryAgain => 'Réessayer';

  @override
  String get statusOverdue => 'En retard - peut encore être faite';

  @override
  String statusUpcomingOn(Object date) {
    return 'Possible le $date';
  }

  @override
  String deadlineLabel(Object time) {
    return 'Échéance $time';
  }

  @override
  String get history => 'Historique';

  @override
  String get showOlder => 'Afficher plus ancien';

  @override
  String get historyEmpty => 'Rien pendant cette période.';

  @override
  String historyPeriod(Object from, Object to) {
    return '$from – $to';
  }

  @override
  String get historyApproved => 'Approuvée';

  @override
  String get historyRejected => 'Refusée';

  @override
  String get historyMissed => 'Manquée';

  @override
  String get historyAdjustment => 'Ajustement';

  @override
  String doneAt(Object time) {
    return 'faite $time';
  }

  @override
  String get lockMinutes => 'Durée du verrouillage';

  @override
  String get lockMinutesHelp =>
      'Durée du verrouillage de la tablette quand une tâche obligatoire est en retard ou refusée (1–480).';

  @override
  String get serviceStatusChannel => 'État';

  @override
  String get serviceMessagesChannel => 'Messages';

  @override
  String get serviceActive => 'Lommepenge est actif';

  @override
  String serviceLockedUntil(Object time) {
    return 'Verrouillée jusqu\'à $time';
  }

  @override
  String get lockRunningTitle => 'La tablette est verrouillée';

  @override
  String lockEndsAt(Object time) {
    return 'Déverrouillage à $time';
  }

  @override
  String get lockPendingTitle => 'Un verrouillage est en attente';

  @override
  String lockPendingBody(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other:
          'Il dure $minutes minutes et commence la prochaine fois que la tablette est utilisée.',
      one:
          'Il dure 1 minute et commence la prochaine fois que la tablette est utilisée.',
    );
    return '$_temp0';
  }

  @override
  String lockStatusRunning(Object time) {
    return 'Verrouillée · reste $time';
  }

  @override
  String get lockStatusPending => 'Verrouillage en attente';

  @override
  String get pausedStatus => 'En pause';

  @override
  String pausedUntilStatus(Object date) {
    return 'En pause jusqu\'au $date';
  }

  @override
  String get notifications => 'Notifications';

  @override
  String get notificationsEmpty => 'Aucune notification ces 7 derniers jours.';

  @override
  String get liftLock => 'Lever le verrouillage';

  @override
  String get lockLifted => 'Le verrouillage a été levé.';

  @override
  String get pauseChild => 'Pause';

  @override
  String get pauseHelp =>
      'Aucune tâche n\'est obligatoire : pas d\'échéances ni de verrouillage. Les tâches rapportent toujours de l\'argent.';

  @override
  String pauseTitle(Object name) {
    return 'Mettre $name en pause';
  }

  @override
  String get pauseUntilLabel =>
      'De nouveau obligatoires à partir du (facultatif)';

  @override
  String get pauseNoEndDate => 'Pas de date de fin';

  @override
  String get pauseConfirm => 'Mettre en pause';

  @override
  String get rejectTitle => 'Refuser la tâche ?';

  @override
  String get rejectReasonLabel => 'Raison (facultative)';

  @override
  String get rejectReasonHelp => 'L\'enfant la verra dans la notification.';

  @override
  String get historyLock => 'Verrouillage';

  @override
  String get historyLockStarted => 'Verrouillage commencé';

  @override
  String get historyLockEnded => 'Verrouillage terminé';

  @override
  String get historyLockLifted => 'Verrouillage levé';
}
