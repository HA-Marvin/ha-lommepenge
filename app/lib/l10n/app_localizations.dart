import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_da.dart';
import 'app_localizations_de.dart';
import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_fr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('da'),
    Locale('de'),
    Locale('en'),
    Locale('es'),
    Locale('fr')
  ];

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @name.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get name;

  /// No description provided for @nameRequired.
  ///
  /// In en, this message translates to:
  /// **'A name is required.'**
  String get nameRequired;

  /// No description provided for @unknownTask.
  ///
  /// In en, this message translates to:
  /// **'Unknown task'**
  String get unknownTask;

  /// No description provided for @unknownChild.
  ///
  /// In en, this message translates to:
  /// **'Unknown child'**
  String get unknownChild;

  /// No description provided for @confirmDelete.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete \"{name}\"?'**
  String confirmDelete(Object name);

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @chooseLanguageTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose language'**
  String get chooseLanguageTitle;

  /// No description provided for @chooseLanguageBody.
  ///
  /// In en, this message translates to:
  /// **'Choose the language of the app. You can change it later.'**
  String get chooseLanguageBody;

  /// No description provided for @continueButton.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueButton;

  /// No description provided for @connectTitle.
  ///
  /// In en, this message translates to:
  /// **'Connect to Home Assistant'**
  String get connectTitle;

  /// No description provided for @connectInstructions.
  ///
  /// In en, this message translates to:
  /// **'Add the device in Home Assistant: Settings → Devices & services → Lommepenge → Add device. Choose a name and role, and enter the code Home Assistant shows.'**
  String get connectInstructions;

  /// No description provided for @codeLabel.
  ///
  /// In en, this message translates to:
  /// **'Code from Home Assistant'**
  String get codeLabel;

  /// No description provided for @codeHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. K7M2QDXA'**
  String get codeHint;

  /// No description provided for @addressLabel.
  ///
  /// In en, this message translates to:
  /// **'Home Assistant address'**
  String get addressLabel;

  /// No description provided for @addressHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. 192.168.1.10:8123'**
  String get addressHint;

  /// No description provided for @searchingForHa.
  ///
  /// In en, this message translates to:
  /// **'Looking for Home Assistant on the network...'**
  String get searchingForHa;

  /// No description provided for @foundHa.
  ///
  /// In en, this message translates to:
  /// **'Found: {name}'**
  String foundHa(Object name);

  /// No description provided for @haNotFound.
  ///
  /// In en, this message translates to:
  /// **'Not found automatically - enter the address. It is shown on the page with the app download in Home Assistant.'**
  String get haNotFound;

  /// No description provided for @searchAgain.
  ///
  /// In en, this message translates to:
  /// **'Search again'**
  String get searchAgain;

  /// No description provided for @connectButton.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get connectButton;

  /// No description provided for @scanQrInstead.
  ///
  /// In en, this message translates to:
  /// **'Scan QR code instead'**
  String get scanQrInstead;

  /// No description provided for @scanQrTitle.
  ///
  /// In en, this message translates to:
  /// **'Scan QR code'**
  String get scanQrTitle;

  /// No description provided for @scanQrHint.
  ///
  /// In en, this message translates to:
  /// **'Point the camera at the QR code in Home Assistant (Lommepenge → Add device).'**
  String get scanQrHint;

  /// No description provided for @parentPinTitle.
  ///
  /// In en, this message translates to:
  /// **'Parent PIN'**
  String get parentPinTitle;

  /// No description provided for @pinPrompt.
  ///
  /// In en, this message translates to:
  /// **'Enter the PIN to enter parent mode.'**
  String get pinPrompt;

  /// No description provided for @pinLabel.
  ///
  /// In en, this message translates to:
  /// **'PIN'**
  String get pinLabel;

  /// No description provided for @wrongPin.
  ///
  /// In en, this message translates to:
  /// **'Wrong PIN. Try again.'**
  String get wrongPin;

  /// No description provided for @unlock.
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get unlock;

  /// No description provided for @timesAndLimits.
  ///
  /// In en, this message translates to:
  /// **'Times and limits'**
  String get timesAndLimits;

  /// No description provided for @timesAndLimitsHint.
  ///
  /// In en, this message translates to:
  /// **'Can also be changed from Home Assistant. Tap to change.'**
  String get timesAndLimitsHint;

  /// No description provided for @defaultDeadline.
  ///
  /// In en, this message translates to:
  /// **'Default deadline'**
  String get defaultDeadline;

  /// No description provided for @defaultDeadlineHelp.
  ///
  /// In en, this message translates to:
  /// **'For mandatory tasks without their own deadline.'**
  String get defaultDeadlineHelp;

  /// No description provided for @restrictionFrom.
  ///
  /// In en, this message translates to:
  /// **'Restriction from'**
  String get restrictionFrom;

  /// No description provided for @restrictionFromHelp.
  ///
  /// In en, this message translates to:
  /// **'Tablets can be restricted from this time at the earliest.'**
  String get restrictionFromHelp;

  /// No description provided for @restrictionUntil.
  ///
  /// In en, this message translates to:
  /// **'Restriction until'**
  String get restrictionUntil;

  /// No description provided for @restrictionUntilHelp.
  ///
  /// In en, this message translates to:
  /// **'After this time the restriction is lifted.'**
  String get restrictionUntilHelp;

  /// No description provided for @pauseTime.
  ///
  /// In en, this message translates to:
  /// **'Pause time'**
  String get pauseTime;

  /// No description provided for @pauseTimeHelp.
  ///
  /// In en, this message translates to:
  /// **'Waiting time before the tablet is unlocked when a task was done late.'**
  String get pauseTimeHelp;

  /// No description provided for @warningBeforeDeadline.
  ///
  /// In en, this message translates to:
  /// **'Warning before deadline'**
  String get warningBeforeDeadline;

  /// No description provided for @warningBeforeDeadlineHelp.
  ///
  /// In en, this message translates to:
  /// **'How long before the deadline the child is warned.'**
  String get warningBeforeDeadlineHelp;

  /// No description provided for @winterFromWeek.
  ///
  /// In en, this message translates to:
  /// **'Winter from week'**
  String get winterFromWeek;

  /// No description provided for @winterToWeek.
  ///
  /// In en, this message translates to:
  /// **'Winter until week'**
  String get winterToWeek;

  /// No description provided for @winterHelp.
  ///
  /// In en, this message translates to:
  /// **'Used for packing lists (e.g. indoor shoes).'**
  String get winterHelp;

  /// No description provided for @minutesUnit.
  ///
  /// In en, this message translates to:
  /// **'min'**
  String get minutesUnit;

  /// No description provided for @resetToDefaults.
  ///
  /// In en, this message translates to:
  /// **'Reset to defaults'**
  String get resetToDefaults;

  /// No description provided for @restrictionToday.
  ///
  /// In en, this message translates to:
  /// **'Restriction today'**
  String get restrictionToday;

  /// No description provided for @liftedForToday.
  ///
  /// In en, this message translates to:
  /// **'Lifted for today'**
  String get liftedForToday;

  /// No description provided for @restricted.
  ///
  /// In en, this message translates to:
  /// **'Restricted'**
  String get restricted;

  /// No description provided for @overdueOutsideWindow.
  ///
  /// In en, this message translates to:
  /// **'Overdue, but outside the restriction time'**
  String get overdueOutsideWindow;

  /// No description provided for @notRestricted.
  ///
  /// In en, this message translates to:
  /// **'Not restricted'**
  String get notRestricted;

  /// No description provided for @liftToday.
  ///
  /// In en, this message translates to:
  /// **'Lift today'**
  String get liftToday;

  /// No description provided for @roleFamilyScreen.
  ///
  /// In en, this message translates to:
  /// **'Family screen'**
  String get roleFamilyScreen;

  /// No description provided for @roleParentPhone.
  ///
  /// In en, this message translates to:
  /// **'Parent\'s phone'**
  String get roleParentPhone;

  /// No description provided for @deviceSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{role} · app version {version}'**
  String deviceSubtitle(Object role, Object version);

  /// No description provided for @notConnected.
  ///
  /// In en, this message translates to:
  /// **'Not connected'**
  String get notConnected;

  /// No description provided for @notFetchedYet.
  ///
  /// In en, this message translates to:
  /// **'Not fetched yet'**
  String get notFetchedYet;

  /// No description provided for @lastUpdatedAt.
  ///
  /// In en, this message translates to:
  /// **'Last updated at {time}'**
  String lastUpdatedAt(Object time);

  /// No description provided for @addDevicesHint.
  ///
  /// In en, this message translates to:
  /// **'New devices are added in Home Assistant under Lommepenge → Add device. They are removed there too.'**
  String get addDevicesHint;

  /// No description provided for @forgetConnection.
  ///
  /// In en, this message translates to:
  /// **'Forget the connection on this device'**
  String get forgetConnection;

  /// No description provided for @forgetConnectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Forget the connection?'**
  String get forgetConnectionTitle;

  /// No description provided for @forgetConnectionBody.
  ///
  /// In en, this message translates to:
  /// **'The device must be connected again with a new code from Home Assistant. Also remove it under Lommepenge in Home Assistant if it will no longer be used.'**
  String get forgetConnectionBody;

  /// No description provided for @forget.
  ///
  /// In en, this message translates to:
  /// **'Forget'**
  String get forget;

  /// No description provided for @noChildrenYet.
  ///
  /// In en, this message translates to:
  /// **'No children created yet. Tap + to create a child.'**
  String get noChildrenYet;

  /// No description provided for @rename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get rename;

  /// No description provided for @addChild.
  ///
  /// In en, this message translates to:
  /// **'Add child'**
  String get addChild;

  /// No description provided for @renameChild.
  ///
  /// In en, this message translates to:
  /// **'Rename child'**
  String get renameChild;

  /// No description provided for @deleteChild.
  ///
  /// In en, this message translates to:
  /// **'Delete child'**
  String get deleteChild;

  /// No description provided for @parentMode.
  ///
  /// In en, this message translates to:
  /// **'Parent mode'**
  String get parentMode;

  /// No description provided for @switchToChildMode.
  ///
  /// In en, this message translates to:
  /// **'Switch to child mode'**
  String get switchToChildMode;

  /// No description provided for @tabTasks.
  ///
  /// In en, this message translates to:
  /// **'Tasks'**
  String get tabTasks;

  /// No description provided for @tabChildren.
  ///
  /// In en, this message translates to:
  /// **'Children'**
  String get tabChildren;

  /// No description provided for @tabApprovals.
  ///
  /// In en, this message translates to:
  /// **'Approvals'**
  String get tabApprovals;

  /// No description provided for @tabOverview.
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get tabOverview;

  /// No description provided for @tabHistory.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get tabHistory;

  /// No description provided for @tabSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get tabSettings;

  /// No description provided for @noTasksYet.
  ///
  /// In en, this message translates to:
  /// **'No tasks created yet.'**
  String get noTasksYet;

  /// No description provided for @deadlineAt.
  ///
  /// In en, this message translates to:
  /// **'deadline {time}'**
  String deadlineAt(Object time);

  /// No description provided for @inCalendar.
  ///
  /// In en, this message translates to:
  /// **'in calendar'**
  String get inCalendar;

  /// No description provided for @deleteTask.
  ///
  /// In en, this message translates to:
  /// **'Delete task'**
  String get deleteTask;

  /// No description provided for @noPendingApprovals.
  ///
  /// In en, this message translates to:
  /// **'No tasks are waiting for approval.'**
  String get noPendingApprovals;

  /// No description provided for @late.
  ///
  /// In en, this message translates to:
  /// **'late'**
  String get late;

  /// No description provided for @approve.
  ///
  /// In en, this message translates to:
  /// **'Approve'**
  String get approve;

  /// No description provided for @reject.
  ///
  /// In en, this message translates to:
  /// **'Reject'**
  String get reject;

  /// No description provided for @adjustBalance.
  ///
  /// In en, this message translates to:
  /// **'Adjust balance'**
  String get adjustBalance;

  /// No description provided for @adjustBalanceHelp.
  ///
  /// In en, this message translates to:
  /// **'Use this to correct a wrong balance, e.g. after a reinstall. The amount can be negative.'**
  String get adjustBalanceHelp;

  /// No description provided for @child.
  ///
  /// In en, this message translates to:
  /// **'Child'**
  String get child;

  /// No description provided for @amountSigned.
  ///
  /// In en, this message translates to:
  /// **'Amount ({currency}, +/-)'**
  String amountSigned(Object currency);

  /// No description provided for @amountNonZero.
  ///
  /// In en, this message translates to:
  /// **'Enter an amount other than 0.'**
  String get amountNonZero;

  /// No description provided for @reason.
  ///
  /// In en, this message translates to:
  /// **'Reason'**
  String get reason;

  /// No description provided for @reasonRequired.
  ///
  /// In en, this message translates to:
  /// **'A reason is required.'**
  String get reasonRequired;

  /// No description provided for @balanceAdjustedBy.
  ///
  /// In en, this message translates to:
  /// **'Balance adjusted by {amount}.'**
  String balanceAdjustedBy(Object amount);

  /// No description provided for @earnedNotPaidOut.
  ///
  /// In en, this message translates to:
  /// **'Earned, not paid out'**
  String get earnedNotPaidOut;

  /// No description provided for @paidOutTotal.
  ///
  /// In en, this message translates to:
  /// **'Paid out in total'**
  String get paidOutTotal;

  /// No description provided for @markAsPaidOut.
  ///
  /// In en, this message translates to:
  /// **'Mark as paid out'**
  String get markAsPaidOut;

  /// No description provided for @confirmPayout.
  ///
  /// In en, this message translates to:
  /// **'You are about to mark {amount} as paid out to {name}. This balance is then reset to zero. Continue?'**
  String confirmPayout(Object amount, Object name);

  /// No description provided for @yesPayOut.
  ///
  /// In en, this message translates to:
  /// **'Yes, pay out'**
  String get yesPayOut;

  /// No description provided for @noCompletedTasksYet.
  ///
  /// In en, this message translates to:
  /// **'No completed tasks yet.'**
  String get noCompletedTasksYet;

  /// No description provided for @balanceAdjustment.
  ///
  /// In en, this message translates to:
  /// **'Balance adjustment: {note}'**
  String balanceAdjustment(Object note);

  /// No description provided for @editTask.
  ///
  /// In en, this message translates to:
  /// **'Edit task'**
  String get editTask;

  /// No description provided for @newTask.
  ///
  /// In en, this message translates to:
  /// **'New task'**
  String get newTask;

  /// No description provided for @taskTitle.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get taskTitle;

  /// No description provided for @titleRequired.
  ///
  /// In en, this message translates to:
  /// **'A title is required.'**
  String get titleRequired;

  /// No description provided for @descriptionOptional.
  ///
  /// In en, this message translates to:
  /// **'Description (optional)'**
  String get descriptionOptional;

  /// No description provided for @amountLabel.
  ///
  /// In en, this message translates to:
  /// **'Amount ({currency})'**
  String amountLabel(Object currency);

  /// No description provided for @amountInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid amount (0 or more).'**
  String get amountInvalid;

  /// No description provided for @recurrence.
  ///
  /// In en, this message translates to:
  /// **'Recurrence'**
  String get recurrence;

  /// No description provided for @recurrenceOnce.
  ///
  /// In en, this message translates to:
  /// **'Once'**
  String get recurrenceOnce;

  /// No description provided for @recurrenceDaily.
  ///
  /// In en, this message translates to:
  /// **'Daily'**
  String get recurrenceDaily;

  /// No description provided for @recurrenceWeekly.
  ///
  /// In en, this message translates to:
  /// **'Weekly'**
  String get recurrenceWeekly;

  /// No description provided for @recurrenceUnlimited.
  ///
  /// In en, this message translates to:
  /// **'Unlimited'**
  String get recurrenceUnlimited;

  /// No description provided for @weeklyDiscontinued.
  ///
  /// In en, this message translates to:
  /// **'Discontinued - choose \"Daily\" instead and set the week plan to the desired day(s).'**
  String get weeklyDiscontinued;

  /// No description provided for @unlimitedHelp.
  ///
  /// In en, this message translates to:
  /// **'Can be done several times a day - only blocked while a completion is waiting for approval.'**
  String get unlimitedHelp;

  /// No description provided for @weekPlan.
  ///
  /// In en, this message translates to:
  /// **'Week plan'**
  String get weekPlan;

  /// No description provided for @weekPlanHelp.
  ///
  /// In en, this message translates to:
  /// **'Choose which days the task is active, e.g. only Tuesday and Thursday. By default every day.'**
  String get weekPlanHelp;

  /// No description provided for @allDays.
  ///
  /// In en, this message translates to:
  /// **'Every day'**
  String get allDays;

  /// No description provided for @weekdays.
  ///
  /// In en, this message translates to:
  /// **'Weekdays'**
  String get weekdays;

  /// No description provided for @weekend.
  ///
  /// In en, this message translates to:
  /// **'Weekend'**
  String get weekend;

  /// No description provided for @assignTo.
  ///
  /// In en, this message translates to:
  /// **'Assign to'**
  String get assignTo;

  /// No description provided for @assignToHelp.
  ///
  /// In en, this message translates to:
  /// **'Choose which children the task applies to. \"All children\" applies dynamically - also to children added later.'**
  String get assignToHelp;

  /// No description provided for @allChildren.
  ///
  /// In en, this message translates to:
  /// **'All children'**
  String get allChildren;

  /// No description provided for @mandatoryTask.
  ///
  /// In en, this message translates to:
  /// **'Mandatory task'**
  String get mandatoryTask;

  /// No description provided for @mandatoryTaskHelp.
  ///
  /// In en, this message translates to:
  /// **'Shown clearly marked as \"must be done\" instead of \"can be done\".'**
  String get mandatoryTaskHelp;

  /// No description provided for @timeOfDay.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get timeOfDay;

  /// No description provided for @timeHelpMandatory.
  ///
  /// In en, this message translates to:
  /// **'After the deadline the task counts as overdue. Without its own deadline the family\'s default deadline is used ({time}).'**
  String timeHelpMandatory(Object time);

  /// No description provided for @timeHelpOptional.
  ///
  /// In en, this message translates to:
  /// **'Optional. The deadline is only followed up on mandatory tasks.'**
  String get timeHelpOptional;

  /// No description provided for @fromLabel.
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get fromLabel;

  /// No description provided for @deadline.
  ///
  /// In en, this message translates to:
  /// **'Deadline'**
  String get deadline;

  /// No description provided for @none.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get none;

  /// No description provided for @defaultLabel.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get defaultLabel;

  /// No description provided for @removeTime.
  ///
  /// In en, this message translates to:
  /// **'Remove time'**
  String get removeTime;

  /// No description provided for @showInCalendar.
  ///
  /// In en, this message translates to:
  /// **'Show in the family calendar'**
  String get showInCalendar;

  /// No description provided for @showInCalendarHelp.
  ///
  /// In en, this message translates to:
  /// **'The task becomes an event in the family\'s calendar once the calendar is set up.'**
  String get showInCalendarHelp;

  /// No description provided for @saving.
  ///
  /// In en, this message translates to:
  /// **'Saving...'**
  String get saving;

  /// No description provided for @saveTask.
  ///
  /// In en, this message translates to:
  /// **'Save task'**
  String get saveTask;

  /// No description provided for @sentForApproval.
  ///
  /// In en, this message translates to:
  /// **'Sent for approval!'**
  String get sentForApproval;

  /// No description provided for @noTasksAskParent.
  ///
  /// In en, this message translates to:
  /// **'There are no tasks yet. Ask a parent to create some in parent mode.'**
  String get noTasksAskParent;

  /// No description provided for @hiChild.
  ///
  /// In en, this message translates to:
  /// **'Hi {name}!'**
  String hiChild(Object name);

  /// No description provided for @fetchingYourTasks.
  ///
  /// In en, this message translates to:
  /// **'Fetching your tasks...'**
  String get fetchingYourTasks;

  /// No description provided for @noTasksRightNow.
  ///
  /// In en, this message translates to:
  /// **'You have no tasks right now.'**
  String get noTasksRightNow;

  /// No description provided for @noChildrenCreateInParentMode.
  ///
  /// In en, this message translates to:
  /// **'There are no children yet. Create them in parent mode.'**
  String get noChildrenCreateInParentMode;

  /// No description provided for @noTasks.
  ///
  /// In en, this message translates to:
  /// **'No tasks.'**
  String get noTasks;

  /// No description provided for @restrictedTitle.
  ///
  /// In en, this message translates to:
  /// **'Games and YouTube are blocked'**
  String get restrictedTitle;

  /// No description provided for @restrictedDoFirst.
  ///
  /// In en, this message translates to:
  /// **'Do these first: {tasks}. Then they are unlocked again.'**
  String restrictedDoFirst(Object tasks);

  /// No description provided for @restrictedLatePause.
  ///
  /// In en, this message translates to:
  /// **'{minutes, plural, =1{The task was done late, so it takes 1 minute before your tablet is unlocked again.} other{The task was done late, so it takes {minutes} minutes before your tablet is unlocked again.}}'**
  String restrictedLatePause(int minutes);

  /// No description provided for @behindTitle.
  ///
  /// In en, this message translates to:
  /// **'You are behind'**
  String get behindTitle;

  /// No description provided for @behindBody.
  ///
  /// In en, this message translates to:
  /// **'{tasks} should have been done. Games and YouTube are blocked from {time} if it is not done.'**
  String behindBody(Object tasks, Object time);

  /// No description provided for @reminderTitle.
  ///
  /// In en, this message translates to:
  /// **'Remember: {task}'**
  String reminderTitle(Object task);

  /// No description provided for @reminderBody.
  ///
  /// In en, this message translates to:
  /// **'Must be done by {time}, otherwise games and YouTube are blocked.'**
  String reminderBody(Object time);

  /// No description provided for @reasonOverdue.
  ///
  /// In en, this message translates to:
  /// **'Missing: {tasks}'**
  String reasonOverdue(Object tasks);

  /// No description provided for @reasonOverdueTask.
  ///
  /// In en, this message translates to:
  /// **'{title} (due {due})'**
  String reasonOverdueTask(Object title, Object due);

  /// No description provided for @reasonLate.
  ///
  /// In en, this message translates to:
  /// **'The task was done late - unlocks at {time}'**
  String reasonLate(Object time);

  /// No description provided for @thisWeekAmount.
  ///
  /// In en, this message translates to:
  /// **'This week: {amount}'**
  String thisWeekAmount(Object amount);

  /// No description provided for @completedThisWeek.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{This week: 1 completed task} other{This week: {count} completed tasks}}'**
  String completedThisWeek(int count);

  /// No description provided for @syncStatus.
  ///
  /// In en, this message translates to:
  /// **'Sync status'**
  String get syncStatus;

  /// No description provided for @connectedToHa.
  ///
  /// In en, this message translates to:
  /// **'Connected to Home Assistant.'**
  String get connectedToHa;

  /// No description provided for @mustBeDone.
  ///
  /// In en, this message translates to:
  /// **'Must be done'**
  String get mustBeDone;

  /// No description provided for @fromTime.
  ///
  /// In en, this message translates to:
  /// **'from {time}'**
  String fromTime(Object time);

  /// No description provided for @byTime.
  ///
  /// In en, this message translates to:
  /// **'by {time}'**
  String byTime(Object time);

  /// No description provided for @notAssigned.
  ///
  /// In en, this message translates to:
  /// **'Not assigned to any child in the family.'**
  String get notAssigned;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @statusAvailable.
  ///
  /// In en, this message translates to:
  /// **'Ready to be done'**
  String get statusAvailable;

  /// No description provided for @statusPending.
  ///
  /// In en, this message translates to:
  /// **'Waiting for approval'**
  String get statusPending;

  /// No description provided for @statusDoneToday.
  ///
  /// In en, this message translates to:
  /// **'Done today - available again tomorrow'**
  String get statusDoneToday;

  /// No description provided for @statusDoneThisWeek.
  ///
  /// In en, this message translates to:
  /// **'Done this week - available again'**
  String get statusDoneThisWeek;

  /// No description provided for @statusDoneThisWeekUntil.
  ///
  /// In en, this message translates to:
  /// **'Done this week - available again ({date})'**
  String statusDoneThisWeekUntil(Object date);

  /// No description provided for @statusCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get statusCompleted;

  /// No description provided for @statusNotScheduled.
  ///
  /// In en, this message translates to:
  /// **'Not on the week plan today'**
  String get statusNotScheduled;

  /// No description provided for @statusNotScheduledUntil.
  ///
  /// In en, this message translates to:
  /// **'Not on the week plan today ({date})'**
  String statusNotScheduledUntil(Object date);

  /// No description provided for @newVersionReady.
  ///
  /// In en, this message translates to:
  /// **'New version {version} is ready.'**
  String newVersionReady(Object version);

  /// No description provided for @update.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get update;

  /// No description provided for @notLommepengeLink.
  ///
  /// In en, this message translates to:
  /// **'That is not a Lommepenge link from Home Assistant.'**
  String get notLommepengeLink;

  /// No description provided for @enterAddressAndCode.
  ///
  /// In en, this message translates to:
  /// **'Enter Home Assistant\'s address and the code.'**
  String get enterAddressAndCode;

  /// No description provided for @tabletAlreadyConnected.
  ///
  /// In en, this message translates to:
  /// **'This tablet is already connected. Reinstall the app to connect it again.'**
  String get tabletAlreadyConnected;

  /// No description provided for @unexpectedResponse.
  ///
  /// In en, this message translates to:
  /// **'Unexpected response from Home Assistant.'**
  String get unexpectedResponse;

  /// No description provided for @notConnectedYet.
  ///
  /// In en, this message translates to:
  /// **'Not connected to Home Assistant yet.'**
  String get notConnectedYet;

  /// No description provided for @deviceRemoved.
  ///
  /// In en, this message translates to:
  /// **'The device was removed in Home Assistant. Connect it again with a new code from Home Assistant (Lommepenge → Add device).'**
  String get deviceRemoved;

  /// No description provided for @noConnectionRetryLater.
  ///
  /// In en, this message translates to:
  /// **'No connection to Home Assistant. Retrying later.'**
  String get noConnectionRetryLater;

  /// No description provided for @updateNotificationTitle.
  ///
  /// In en, this message translates to:
  /// **'New version of Lommepenge'**
  String get updateNotificationTitle;

  /// No description provided for @updateNotificationBody.
  ///
  /// In en, this message translates to:
  /// **'Version {version} is ready. Open the app to update.'**
  String updateNotificationBody(Object version);

  /// No description provided for @updatesChannel.
  ///
  /// In en, this message translates to:
  /// **'Updates'**
  String get updatesChannel;

  /// No description provided for @allowUnknownApps.
  ///
  /// In en, this message translates to:
  /// **'Allow \"Install unknown apps\" for Lommepenge, and tap Update again.'**
  String get allowUnknownApps;

  /// No description provided for @downloadCorrupt.
  ///
  /// In en, this message translates to:
  /// **'The downloaded file was damaged. Try again.'**
  String get downloadCorrupt;

  /// No description provided for @installing.
  ///
  /// In en, this message translates to:
  /// **'Installing version {version}...'**
  String installing(Object version);

  /// No description provided for @installFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not install: {error}'**
  String installFailed(Object error);

  /// No description provided for @installationFailed.
  ///
  /// In en, this message translates to:
  /// **'The installation failed.'**
  String get installationFailed;

  /// No description provided for @haRejectedConnection.
  ///
  /// In en, this message translates to:
  /// **'Home Assistant rejected the connection ({status}).'**
  String haRejectedConnection(Object status);

  /// No description provided for @cannotReachHaHomeNetwork.
  ///
  /// In en, this message translates to:
  /// **'Cannot reach Home Assistant. Is the device on the home network?'**
  String get cannotReachHaHomeNetwork;

  /// No description provided for @haTimeout.
  ///
  /// In en, this message translates to:
  /// **'Home Assistant did not respond in time.'**
  String get haTimeout;

  /// No description provided for @unexpectedError.
  ///
  /// In en, this message translates to:
  /// **'Unexpected error: {error}'**
  String unexpectedError(Object error);

  /// No description provided for @haUpdateFailed.
  ///
  /// In en, this message translates to:
  /// **'Home Assistant could not deliver the update ({status}).'**
  String haUpdateFailed(Object status);

  /// No description provided for @cannotReachHa.
  ///
  /// In en, this message translates to:
  /// **'Cannot reach Home Assistant.'**
  String get cannotReachHa;

  /// No description provided for @updateDownloadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not download the update: {error}'**
  String updateDownloadFailed(Object error);

  /// No description provided for @deviceNoLongerConnected.
  ///
  /// In en, this message translates to:
  /// **'The device is no longer connected to Home Assistant.'**
  String get deviceNoLongerConnected;

  /// No description provided for @haError.
  ///
  /// In en, this message translates to:
  /// **'Home Assistant responded with an error ({status}).'**
  String haError(Object status);

  /// No description provided for @noConnectionCheckNetwork.
  ///
  /// In en, this message translates to:
  /// **'No connection to Home Assistant. Check that the device is on the home network.'**
  String get noConnectionCheckNetwork;

  /// No description provided for @haTimeoutRetry.
  ///
  /// In en, this message translates to:
  /// **'Home Assistant did not respond in time. Retrying later.'**
  String get haTimeoutRetry;

  /// No description provided for @errChildNameEmpty.
  ///
  /// In en, this message translates to:
  /// **'The child\'s name cannot be empty.'**
  String get errChildNameEmpty;

  /// No description provided for @errChildNotFound.
  ///
  /// In en, this message translates to:
  /// **'The child no longer exists.'**
  String get errChildNotFound;

  /// No description provided for @errAdjustmentNote.
  ///
  /// In en, this message translates to:
  /// **'A balance adjustment must have a note.'**
  String get errAdjustmentNote;

  /// No description provided for @errTaskNotFound.
  ///
  /// In en, this message translates to:
  /// **'The task no longer exists.'**
  String get errTaskNotFound;

  /// No description provided for @errTaskNotAssigned.
  ///
  /// In en, this message translates to:
  /// **'The task is not assigned to this child.'**
  String get errTaskNotAssigned;

  /// No description provided for @errTaskNotAvailable.
  ///
  /// In en, this message translates to:
  /// **'The task cannot be marked as done right now.'**
  String get errTaskNotAvailable;

  /// No description provided for @errCompletionNotFound.
  ///
  /// In en, this message translates to:
  /// **'The completion does not exist.'**
  String get errCompletionNotFound;

  /// No description provided for @errCompletionHandled.
  ///
  /// In en, this message translates to:
  /// **'The completion has already been handled.'**
  String get errCompletionHandled;

  /// No description provided for @errMissingChildId.
  ///
  /// In en, this message translates to:
  /// **'The action does not say which child it is for (childId).'**
  String get errMissingChildId;

  /// No description provided for @errMissingName.
  ///
  /// In en, this message translates to:
  /// **'The action is missing a name.'**
  String get errMissingName;

  /// No description provided for @errMissingIdOrName.
  ///
  /// In en, this message translates to:
  /// **'The action is missing an id or a name.'**
  String get errMissingIdOrName;

  /// No description provided for @errMissingId.
  ///
  /// In en, this message translates to:
  /// **'The action is missing an id.'**
  String get errMissingId;

  /// No description provided for @errMissingSetting.
  ///
  /// In en, this message translates to:
  /// **'The action is missing a setting.'**
  String get errMissingSetting;

  /// No description provided for @errUnknownAction.
  ///
  /// In en, this message translates to:
  /// **'Unknown action: {type}'**
  String errUnknownAction(Object type);

  /// No description provided for @errInvalidTime.
  ///
  /// In en, this message translates to:
  /// **'Invalid time for {key}: {value}'**
  String errInvalidTime(Object key, Object value);

  /// No description provided for @errSettingRange.
  ///
  /// In en, this message translates to:
  /// **'{key} must be between {min} and {max}: {value}'**
  String errSettingRange(Object key, Object min, Object max, Object value);

  /// No description provided for @errUnknownSetting.
  ///
  /// In en, this message translates to:
  /// **'Unknown setting: {key}'**
  String errUnknownSetting(Object key);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['da', 'de', 'en', 'es', 'fr'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'da':
      return AppLocalizationsDa();
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
    case 'fr':
      return AppLocalizationsFr();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
