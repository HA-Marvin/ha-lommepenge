/// A child's lock and notifications, exactly as Home Assistant sends them
/// (`state.children[].lock` and `.notifications`, see docs/app-api.md). HA
/// decides everything about locks; the app only shows them and counts the
/// countdown down locally between polls.
library;

/// `none`, `pending` (waits for the child to use the tablet) or `running`.
enum LockStatus {
  none,
  pending,
  running;

  /// An unknown status from a newer HA is shown as no lock.
  static LockStatus fromValue(Object? value) {
    for (final status in values) {
      if (status.name == value) return status;
    }
    return none;
  }
}

/// How a lock is enforced on the child's tablet - and thereby how the app
/// shows it. Today HA only has the network rule, shown in the app as a big
/// countdown ([inApp]); other types (e.g. an overlay on other apps) can be
/// added here and get their own view in `lockViews` (widgets/lock_view.dart).
enum LockType { inApp }

/// One cause of a lock (`lock.reasons[]`).
class LockReason {
  /// `overdue`, `rejected` or `late`.
  final String kind;
  final String? taskId;
  final String? taskTitle;
  final String? date;
  final DateTime? deadline;

  /// The parent's reason for a rejection.
  final String? reason;

  /// Arrived while the lock was running and did not extend it.
  final bool absorbed;

  const LockReason({
    required this.kind,
    this.taskId,
    this.taskTitle,
    this.date,
    this.deadline,
    this.reason,
    this.absorbed = false,
  });

  static LockReason? tryParse(Object? json) {
    if (json is! Map) return null;
    final kind = json['kind'];
    if (kind is! String) return null;
    return LockReason(
      kind: kind,
      taskId: _string(json['taskId']),
      taskTitle: _string(json['taskTitle']),
      date: _string(json['date']),
      deadline: _time(json['deadline']),
      reason: _string(json['reason']),
      absorbed: json['absorbed'] == true,
    );
  }
}

/// A child's lock (`children[].lock`).
class ChildLock {
  final LockStatus status;

  /// Ready-made text for all causes, in the app's language (`null` when
  /// [status] is `none`). Shown under the countdown.
  final String? reason;
  final List<LockReason> reasons;

  /// How long it runs (running) or will run when it starts (pending).
  final int? minutes;
  final DateTime? pendingSince;
  final DateTime? pendingUntil;
  final DateTime? startedAt;
  final DateTime? endsAt;

  const ChildLock({
    this.status = LockStatus.none,
    this.reason,
    this.reasons = const [],
    this.minutes,
    this.pendingSince,
    this.pendingUntil,
    this.startedAt,
    this.endsAt,
  });

  static const none = ChildLock();

  bool get isNone => status == LockStatus.none;
  bool get isPending => status == LockStatus.pending;

  /// A running lock without an end time cannot be counted down and is
  /// treated as no lock (HA always sends `endsAt` for a running lock).
  bool get isRunning => status == LockStatus.running && endsAt != null;

  /// Only the in-app countdown exists today, see [LockType].
  LockType get type => LockType.inApp;

  /// Reads a lock defensively: anything unreadable is "no lock".
  factory ChildLock.fromJson(Object? json) {
    if (json is! Map) return none;
    final status = LockStatus.fromValue(json['status']);
    if (status == LockStatus.none) return none;
    final reasons = <LockReason>[];
    final rawReasons = json['reasons'];
    if (rawReasons is List) {
      for (final raw in rawReasons) {
        final reason = LockReason.tryParse(raw);
        if (reason != null) reasons.add(reason);
      }
    }
    final minutes = json['minutes'];
    return ChildLock(
      status: status,
      reason: _string(json['reason']),
      reasons: reasons,
      minutes: minutes is num ? minutes.toInt() : null,
      pendingSince: _time(json['pendingSince']),
      pendingUntil: _time(json['pendingUntil']),
      startedAt: _time(json['startedAt']),
      endsAt: _time(json['endsAt']),
    );
  }
}

/// How long a running lock has left: `endsAt - now` by HA's clock at the
/// moment the state was received, minus the time that has passed on the
/// device since then (so a wrong tablet clock does not matter). Never
/// negative. `null` when the lock is not running.
Duration? lockRemaining(
  ChildLock lock, {
  required DateTime? serverNow,
  required DateTime receivedAt,
  required DateTime deviceNow,
}) {
  final endsAt = lock.endsAt;
  if (!lock.isRunning || endsAt == null || serverNow == null) return null;
  var elapsed = deviceNow.difference(receivedAt);
  if (elapsed.isNegative) elapsed = Duration.zero;
  final remaining = endsAt.difference(serverNow) - elapsed;
  return remaining.isNegative ? Duration.zero : remaining;
}

/// A countdown as `m:ss`, or `h:mm:ss` from one hour.
String formatCountdown(Duration d) {
  final total = d.inSeconds < 0 ? 0 : d.inSeconds;
  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  final seconds = (total % 60).toString().padLeft(2, '0');
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:$seconds';
  }
  return '$minutes:$seconds';
}

/// One notification for the child (`children[0].notifications[]`, child's
/// tablet only). HA writes the ready-made [message] in the app's language.
class ChildNotification {
  final String id;

  /// `deadlineWarning`, `overdue`, `rejected`, `lockStarted`, `forgotten`
  /// (unknown types are shown with a neutral icon).
  final String type;
  final DateTime at;
  final String message;
  final String? taskId;
  final String? taskTitle;
  final String? reason;
  final int? minutes;
  final DateTime? endsAt;

  const ChildNotification({
    required this.id,
    required this.type,
    required this.at,
    required this.message,
    this.taskId,
    this.taskTitle,
    this.reason,
    this.minutes,
    this.endsAt,
  });

  static ChildNotification? tryParse(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final at = _time(json['at']);
    if (id is! String || at == null) return null;
    final minutes = json['minutes'];
    return ChildNotification(
      id: id,
      type: _string(json['type']) ?? '',
      at: at,
      message: _string(json['message']) ?? '',
      taskId: _string(json['taskId']),
      taskTitle: _string(json['taskTitle']),
      reason: _string(json['reason']),
      minutes: minutes is num ? minutes.toInt() : null,
      endsAt: _time(json['endsAt']),
    );
  }
}

String? _string(Object? value) => value is String ? value : null;

DateTime? _time(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;
