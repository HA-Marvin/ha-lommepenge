// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get delete => 'Delete';

  @override
  String get add => 'Add';

  @override
  String get name => 'Name';

  @override
  String get nameRequired => 'A name is required.';

  @override
  String get unknownTask => 'Unknown task';

  @override
  String get unknownChild => 'Unknown child';

  @override
  String confirmDelete(Object name) {
    return 'Are you sure you want to delete \"$name\"?';
  }

  @override
  String get language => 'Language';

  @override
  String get chooseLanguageTitle => 'Choose language';

  @override
  String get chooseLanguageBody =>
      'Choose the language of the app. You can change it later.';

  @override
  String get continueButton => 'Continue';

  @override
  String get connectTitle => 'Connect to Home Assistant';

  @override
  String get connectInstructions =>
      'Add the device in Home Assistant: Settings → Devices & services → Lommepenge → Add device. Choose a name and role, and enter the code Home Assistant shows.';

  @override
  String get codeLabel => 'Code from Home Assistant';

  @override
  String get codeHint => 'e.g. K7M2QDXA';

  @override
  String get addressLabel => 'Home Assistant address';

  @override
  String get addressHint => 'e.g. 192.168.1.10:8123';

  @override
  String get searchingForHa => 'Looking for Home Assistant on the network...';

  @override
  String foundHa(Object name) {
    return 'Found: $name';
  }

  @override
  String get haNotFound =>
      'Not found automatically - enter the address. It is shown on the page with the app download in Home Assistant.';

  @override
  String get searchAgain => 'Search again';

  @override
  String get connectButton => 'Connect';

  @override
  String get scanQrInstead => 'Scan QR code instead';

  @override
  String get scanQrTitle => 'Scan QR code';

  @override
  String get scanQrHint =>
      'Point the camera at the QR code in Home Assistant (Lommepenge → Add device).';

  @override
  String get parentPinTitle => 'Parent PIN';

  @override
  String get pinPrompt => 'Enter the PIN to enter parent mode.';

  @override
  String get pinLabel => 'PIN';

  @override
  String get wrongPin => 'Wrong PIN. Try again.';

  @override
  String get unlock => 'Unlock';

  @override
  String get timesAndLimits => 'Times and limits';

  @override
  String get timesAndLimitsHint =>
      'Can also be changed from Home Assistant. Tap to change.';

  @override
  String get defaultDeadline => 'Default deadline';

  @override
  String get defaultDeadlineHelp =>
      'For mandatory tasks without their own deadline.';

  @override
  String get pauseTime => 'Short lock when late';

  @override
  String get pauseTimeHelp =>
      'The lock\'s length when a late task is done before its lock has started (0 = no lock).';

  @override
  String get warningBeforeDeadline => 'Warning before deadline';

  @override
  String get warningBeforeDeadlineHelp =>
      'How long before the deadline the child is warned.';

  @override
  String get winterFromWeek => 'Winter from week';

  @override
  String get winterToWeek => 'Winter until week';

  @override
  String get winterHelp => 'Used for packing lists (e.g. indoor shoes).';

  @override
  String get minutesUnit => 'min';

  @override
  String get resetToDefaults => 'Reset to defaults';

  @override
  String get roleFamilyScreen => 'Family screen';

  @override
  String get roleParentPhone => 'Parent\'s phone';

  @override
  String deviceSubtitle(Object role, Object version) {
    return '$role · app version $version';
  }

  @override
  String get notConnected => 'Not connected';

  @override
  String get notFetchedYet => 'Not fetched yet';

  @override
  String lastUpdatedAt(Object time) {
    return 'Last updated at $time';
  }

  @override
  String get addDevicesHint =>
      'New devices are added in Home Assistant under Lommepenge → Add device. They are removed there too.';

  @override
  String get forgetConnection => 'Forget the connection on this device';

  @override
  String get forgetConnectionTitle => 'Forget the connection?';

  @override
  String get forgetConnectionBody =>
      'The device must be connected again with a new code from Home Assistant. Also remove it under Lommepenge in Home Assistant if it will no longer be used.';

  @override
  String get forget => 'Forget';

  @override
  String get noChildrenYet =>
      'No children created yet. Tap + to create a child.';

  @override
  String get rename => 'Rename';

  @override
  String get addChild => 'Add child';

  @override
  String get renameChild => 'Rename child';

  @override
  String get deleteChild => 'Delete child';

  @override
  String get parentMode => 'Parent mode';

  @override
  String get switchToChildMode => 'Switch to child mode';

  @override
  String get tabTasks => 'Tasks';

  @override
  String get tabChildren => 'Children';

  @override
  String get tabApprovals => 'Approvals';

  @override
  String get tabOverview => 'Overview';

  @override
  String get tabHistory => 'History';

  @override
  String get tabSettings => 'Settings';

  @override
  String get noTasksYet => 'No tasks created yet.';

  @override
  String deadlineAt(Object time) {
    return 'deadline $time';
  }

  @override
  String get inCalendar => 'in calendar';

  @override
  String get deleteTask => 'Delete task';

  @override
  String get noPendingApprovals => 'No tasks are waiting for approval.';

  @override
  String get late => 'late';

  @override
  String get approve => 'Approve';

  @override
  String get reject => 'Reject';

  @override
  String get adjustBalance => 'Adjust balance';

  @override
  String get adjustBalanceHelp =>
      'Use this to correct a wrong balance, e.g. after a reinstall. The amount can be negative.';

  @override
  String get child => 'Child';

  @override
  String amountSigned(Object currency) {
    return 'Amount ($currency, +/-)';
  }

  @override
  String get amountNonZero => 'Enter an amount other than 0.';

  @override
  String get reason => 'Reason';

  @override
  String get reasonRequired => 'A reason is required.';

  @override
  String balanceAdjustedBy(Object amount) {
    return 'Balance adjusted by $amount.';
  }

  @override
  String get earnedNotPaidOut => 'Earned, not paid out';

  @override
  String get paidOutTotal => 'Paid out in total';

  @override
  String get markAsPaidOut => 'Mark as paid out';

  @override
  String confirmPayout(Object amount, Object name) {
    return 'You are about to mark $amount as paid out to $name. This balance is then reset to zero. Continue?';
  }

  @override
  String get yesPayOut => 'Yes, pay out';

  @override
  String get noCompletedTasksYet => 'No completed tasks yet.';

  @override
  String balanceAdjustment(Object note) {
    return 'Balance adjustment: $note';
  }

  @override
  String get editTask => 'Edit task';

  @override
  String get newTask => 'New task';

  @override
  String get taskTitle => 'Title';

  @override
  String get titleRequired => 'A title is required.';

  @override
  String get descriptionOptional => 'Description (optional)';

  @override
  String amountLabel(Object currency) {
    return 'Amount ($currency)';
  }

  @override
  String get amountInvalid => 'Enter a valid amount (0 or more).';

  @override
  String get recurrence => 'Recurrence';

  @override
  String get recurrenceOnce => 'Once';

  @override
  String get recurrenceDaily => 'Daily';

  @override
  String get recurrenceWeekly => 'Weekly';

  @override
  String get recurrenceUnlimited => 'Unlimited';

  @override
  String get weeklyDiscontinued =>
      'Discontinued - choose \"Daily\" instead and set the week plan to the desired day(s).';

  @override
  String get unlimitedHelp =>
      'Can be done several times a day - only blocked while a completion is waiting for approval.';

  @override
  String get weekPlan => 'Week plan';

  @override
  String get weekPlanHelp =>
      'Choose which days the task is active, e.g. only Tuesday and Thursday. By default every day.';

  @override
  String get allDays => 'Every day';

  @override
  String get weekdays => 'Weekdays';

  @override
  String get weekend => 'Weekend';

  @override
  String get assignTo => 'Assign to';

  @override
  String get assignToHelp =>
      'Choose which children the task applies to. \"All children\" applies dynamically - also to children added later.';

  @override
  String get allChildren => 'All children';

  @override
  String get mandatoryTask => 'Mandatory task';

  @override
  String get mandatoryTaskHelp =>
      'Shown clearly marked as \"must be done\" instead of \"can be done\".';

  @override
  String get timeOfDay => 'Time';

  @override
  String timeHelpMandatory(Object time) {
    return 'After the deadline the task counts as overdue. Without its own deadline the family\'s default deadline is used ($time).';
  }

  @override
  String get timeHelpOptional =>
      'Optional. The deadline is only followed up on mandatory tasks.';

  @override
  String get fromLabel => 'From';

  @override
  String get deadline => 'Deadline';

  @override
  String get none => 'None';

  @override
  String get defaultLabel => 'Default';

  @override
  String get removeTime => 'Remove time';

  @override
  String get showInCalendar => 'Show in the family calendar';

  @override
  String get showInCalendarHelp =>
      'The task becomes an event in the family\'s calendar once the calendar is set up.';

  @override
  String get saving => 'Saving...';

  @override
  String get saveTask => 'Save task';

  @override
  String get sentForApproval => 'Sent for approval!';

  @override
  String get noTasksAskParent =>
      'There are no tasks yet. Ask a parent to create some in parent mode.';

  @override
  String hiChild(Object name) {
    return 'Hi $name!';
  }

  @override
  String get fetchingYourTasks => 'Fetching your tasks...';

  @override
  String get noTasksRightNow => 'You have no tasks right now.';

  @override
  String get noChildrenCreateInParentMode =>
      'There are no children yet. Create them in parent mode.';

  @override
  String get noTasks => 'No tasks.';

  @override
  String thisWeekAmount(Object amount) {
    return 'This week: $amount';
  }

  @override
  String completedThisWeek(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'This week: $count completed tasks',
      one: 'This week: 1 completed task',
    );
    return '$_temp0';
  }

  @override
  String get syncStatus => 'Sync status';

  @override
  String get connectedToHa => 'Connected to Home Assistant.';

  @override
  String get mustBeDone => 'Must be done';

  @override
  String fromTime(Object time) {
    return 'from $time';
  }

  @override
  String byTime(Object time) {
    return 'by $time';
  }

  @override
  String get notAssigned => 'Not assigned to any child in the family.';

  @override
  String get done => 'Done';

  @override
  String get statusAvailable => 'Ready to be done';

  @override
  String get statusPending => 'Waiting for approval';

  @override
  String get statusDoneToday => 'Done today - available again tomorrow';

  @override
  String get statusDoneThisWeek => 'Done this week - available again';

  @override
  String statusDoneThisWeekUntil(Object date) {
    return 'Done this week - available again ($date)';
  }

  @override
  String get statusCompleted => 'Completed';

  @override
  String get statusNotScheduled => 'Not on the week plan today';

  @override
  String statusNotScheduledUntil(Object date) {
    return 'Not on the week plan today ($date)';
  }

  @override
  String newVersionReady(Object version) {
    return 'New version $version is ready.';
  }

  @override
  String get update => 'Update';

  @override
  String get notLommepengeLink =>
      'That is not a Lommepenge link from Home Assistant.';

  @override
  String get enterAddressAndCode =>
      'Enter Home Assistant\'s address and the code.';

  @override
  String get tabletAlreadyConnected =>
      'This tablet is already connected. Reinstall the app to connect it again.';

  @override
  String get unexpectedResponse => 'Unexpected response from Home Assistant.';

  @override
  String get notConnectedYet => 'Not connected to Home Assistant yet.';

  @override
  String get deviceRemoved =>
      'The device was removed in Home Assistant. Connect it again with a new code from Home Assistant (Lommepenge → Add device).';

  @override
  String get noConnectionRetryLater =>
      'No connection to Home Assistant. Retrying later.';

  @override
  String get updateNotificationTitle => 'New version of Lommepenge';

  @override
  String updateNotificationBody(Object version) {
    return 'Version $version is ready. Open the app to update.';
  }

  @override
  String get updatesChannel => 'Updates';

  @override
  String get allowUnknownApps =>
      'Allow \"Install unknown apps\" for Lommepenge, and tap Update again.';

  @override
  String get downloadCorrupt => 'The downloaded file was damaged. Try again.';

  @override
  String installing(Object version) {
    return 'Installing version $version...';
  }

  @override
  String installFailed(Object error) {
    return 'Could not install: $error';
  }

  @override
  String get installationFailed => 'The installation failed.';

  @override
  String haRejectedConnection(Object status) {
    return 'Home Assistant rejected the connection ($status).';
  }

  @override
  String get cannotReachHaHomeNetwork =>
      'Cannot reach Home Assistant. Is the device on the home network?';

  @override
  String get haTimeout => 'Home Assistant did not respond in time.';

  @override
  String unexpectedError(Object error) {
    return 'Unexpected error: $error';
  }

  @override
  String haUpdateFailed(Object status) {
    return 'Home Assistant could not deliver the update ($status).';
  }

  @override
  String get cannotReachHa => 'Cannot reach Home Assistant.';

  @override
  String updateDownloadFailed(Object error) {
    return 'Could not download the update: $error';
  }

  @override
  String get deviceNoLongerConnected =>
      'The device is no longer connected to Home Assistant.';

  @override
  String haError(Object status) {
    return 'Home Assistant responded with an error ($status).';
  }

  @override
  String get noConnectionCheckNetwork =>
      'No connection to Home Assistant. Check that the device is on the home network.';

  @override
  String get haTimeoutRetry =>
      'Home Assistant did not respond in time. Retrying later.';

  @override
  String get errChildNameEmpty => 'The child\'s name cannot be empty.';

  @override
  String get errChildNotFound => 'The child no longer exists.';

  @override
  String get errAdjustmentNote => 'A balance adjustment must have a note.';

  @override
  String get errTaskNotFound => 'The task no longer exists.';

  @override
  String get errTaskNotAssigned => 'The task is not assigned to this child.';

  @override
  String get errTaskNotAvailable =>
      'The task cannot be marked as done right now.';

  @override
  String get errCompletionNotFound => 'The completion does not exist.';

  @override
  String get errCompletionHandled => 'The completion has already been handled.';

  @override
  String get errMissingChildId =>
      'The action does not say which child it is for (childId).';

  @override
  String get errMissingName => 'The action is missing a name.';

  @override
  String get errMissingIdOrName => 'The action is missing an id or a name.';

  @override
  String get errMissingId => 'The action is missing an id.';

  @override
  String get errMissingSetting => 'The action is missing a setting.';

  @override
  String errUnknownAction(Object type) {
    return 'Unknown action: $type';
  }

  @override
  String errInvalidTime(Object key, Object value) {
    return 'Invalid time for $key: $value';
  }

  @override
  String errSettingRange(Object key, Object min, Object max, Object value) {
    return '$key must be between $min and $max: $value';
  }

  @override
  String errUnknownSetting(Object key) {
    return 'Unknown setting: $key';
  }

  @override
  String get noConnectionTryAgain =>
      'No connection to Home Assistant – try again';

  @override
  String get tryAgain => 'Try again';

  @override
  String get statusOverdue => 'Overdue - can still be done';

  @override
  String statusUpcomingOn(Object date) {
    return 'Can be done $date';
  }

  @override
  String deadlineLabel(Object time) {
    return 'Deadline $time';
  }

  @override
  String get history => 'History';

  @override
  String get showOlder => 'Show older';

  @override
  String get historyEmpty => 'Nothing in this period.';

  @override
  String historyPeriod(Object from, Object to) {
    return '$from – $to';
  }

  @override
  String get historyApproved => 'Approved';

  @override
  String get historyRejected => 'Rejected';

  @override
  String get historyMissed => 'Missed';

  @override
  String get historyAdjustment => 'Adjustment';

  @override
  String doneAt(Object time) {
    return 'done $time';
  }

  @override
  String get lockMinutes => 'Lock duration';

  @override
  String get lockMinutesHelp =>
      'How long the tablet is locked when a mandatory task is missed or rejected (1–480).';

  @override
  String get serviceStatusChannel => 'Status';

  @override
  String get serviceMessagesChannel => 'Messages';

  @override
  String get serviceActive => 'Lommepenge is active';

  @override
  String serviceLockedUntil(Object time) {
    return 'Locked until $time';
  }

  @override
  String get lockRunningTitle => 'The tablet is locked';

  @override
  String lockEndsAt(Object time) {
    return 'Unlocks at $time';
  }

  @override
  String get lockPendingTitle => 'A lock is waiting';

  @override
  String lockPendingBody(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other:
          'It lasts $minutes minutes and starts the next time the tablet is used.',
      one: 'It lasts 1 minute and starts the next time the tablet is used.',
    );
    return '$_temp0';
  }

  @override
  String lockStatusRunning(Object time) {
    return 'Locked · $time left';
  }

  @override
  String get lockStatusPending => 'Lock waiting';

  @override
  String get pausedStatus => 'Paused';

  @override
  String pausedUntilStatus(Object date) {
    return 'Paused until $date';
  }

  @override
  String get notifications => 'Notifications';

  @override
  String get notificationsEmpty => 'No notifications in the last 7 days.';

  @override
  String get liftLock => 'Lift lock';

  @override
  String get lockLifted => 'The lock has been lifted.';

  @override
  String get pauseChild => 'Pause';

  @override
  String get pauseHelp =>
      'No task is mandatory: no deadlines and no locks. Tasks still earn money.';

  @override
  String pauseTitle(Object name) {
    return 'Pause $name';
  }

  @override
  String get pauseUntilLabel => 'Mandatory again from (optional)';

  @override
  String get pauseNoEndDate => 'No end date';

  @override
  String get pauseConfirm => 'Pause';

  @override
  String get rejectTitle => 'Reject the task?';

  @override
  String get rejectReasonLabel => 'Reason (optional)';

  @override
  String get rejectReasonHelp => 'The child sees it in the notification.';

  @override
  String get historyLock => 'Lock';

  @override
  String get historyLockStarted => 'Lock started';

  @override
  String get historyLockEnded => 'Lock ended';

  @override
  String get historyLockLifted => 'Lock lifted';
}
