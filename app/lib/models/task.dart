/// Hvor tit en opgave kan udføres.
///
/// [weekly] tilbydes ikke længere i opret/redigér-opgave-UI'en (30. aug.
/// 2026) - "ugeplan" (Task.activeWeekdays) på en [daily]-opgave dækker
/// samme behov (fx "kun tirsdag og torsdag") mere fleksibelt. Værdien
/// beholdes i enummet af bagudkompatibilitet, så en opgave der allerede
/// er oprettet som ugentlig fortsat virker og synker korrekt.
enum Recurrence {
  once('once'),
  daily('daily'),
  weekly('weekly'),
  unlimited('unlimited');

  final String value;
  const Recurrence(this.value);

  static Recurrence fromValue(String value) {
    return Recurrence.values.firstWhere(
      (r) => r.value == value,
      orElse: () => Recurrence.once,
    );
  }

  /// Dansk visningstekst.
  String get label {
    switch (this) {
      case Recurrence.once:
        return 'Engang';
      case Recurrence.daily:
        return 'Dagligt';
      case Recurrence.weekly:
        return 'Ugentligt';
      case Recurrence.unlimited:
        return 'Ubegrænset';
    }
  }
}

/// Normaliserer en liste af ugedage (1=mandag..7=søndag) til `null` når
/// listen reelt betyder "alle dage" (tom, eller indeholder alle 7),
/// så DB/JSON altid har én entydig repræsentation af "ingen filter".
List<int>? _normalizeWeekdays(List<int>? weekdays) {
  if (weekdays == null || weekdays.isEmpty) return null;
  final unique = weekdays.toSet();
  if (unique.length >= 7) return null;
  final sorted = unique.toList()..sort();
  return sorted;
}

/// Normaliserer en liste af barn-id'er til `null` når listen er tom, så
/// DB/JSON altid har én entydig repræsentation af "ingen bestemte børn
/// valgt" (= "alle børn", jf. [Task.assignedChildIds]). Bevidst IKKE en
/// tilsvarende "alle id'er valgt -> null"-regel som for
/// [_normalizeWeekdays]: Task-modellen kender ikke familiens fulde
/// børneliste, så kun UI'et/repository-laget (der rent faktisk kender
/// listen) kan afgøre om "alle er valgt enkeltvis" reelt skal gemmes som
/// den dynamiske "alle børn"-værdi (null) i stedet.
List<String>? _normalizeChildIds(List<String>? childIds) {
  if (childIds == null || childIds.isEmpty) return null;
  final unique = <String>[];
  for (final id in childIds) {
    if (!unique.contains(id)) unique.add(id);
  }
  return unique;
}

/// En opgave oprettet af en forælder.
///
/// [amountOre] er beløbet i øre (100 øre = 1 kr) for at undgå
/// afrundingsfejl med double-værdier.
class Task {
  final String id;
  final String title;
  final String? description;
  final int amountOre;
  final Recurrence recurrence;
  final DateTime createdAt;
  final bool active;

  /// Om opgaven er markeret som obligatorisk ("skal udføres") frem for
  /// valgfri ("kan udføres"). Rent visuelt/informativt felt - påvirker
  /// ikke tilgængelighed, godkendelse eller saldo. Default false, så
  /// eksisterende opgaver fra før dette felt forbliver valgfri.
  final bool mandatory;

  /// Hvilke ugedage opgaven er aktiv på (`DateTime.weekday`-konvention:
  /// 1=mandag...7=søndag). `null` eller en tom liste betyder "alle dage"
  /// - det bagudkompatible default for eksisterende opgaver og for
  /// engangsopgaver. Gælder kun gentagende opgaver (ikke [Recurrence.once]).
  final List<int>? activeWeekdays;

  /// Hvilke børn opgaven er tildelt. `null` eller en tom liste betyder
  /// "alle børn" - og det er DYNAMISK: tilføjes der senere et nyt barn i
  /// familien, gælder opgaven automatisk også for det, uden at denne
  /// opgave skal redigeres. Præcis samme mønster som [activeWeekdays]
  /// bruger for "alle dage" - se `TaskRepository.resolvedChildIdsForTask`
  /// for hvordan "alle børn" slås dynamisk op.
  final List<String>? assignedChildIds;

  /// Hvornår opgaven tidligst bør laves (`"HH:MM"`), fx 06:45 for "Pak
  /// skoletaske". Kun informativt (vises på kortet og bruges som start på
  /// et evt. kalender-event) - opgaven kan stadig udføres før.
  final String? startTime;

  /// Opgavens frist (`"HH:MM"`). For obligatoriske opgaver uden egen frist
  /// bruges familiens standardfrist (se `FamilySettings.defaultDueTime`).
  /// Efter fristen tæller en ikke-udført obligatorisk opgave som
  /// forsinket (spærring/notifikation), men kan stadig markeres udført.
  final String? dueTime;

  /// Om opgaven skal vises som event i familiekalenderen. Standard fra.
  final bool showInCalendar;

  Task({
    required this.id,
    required this.title,
    this.description,
    required this.amountOre,
    required this.recurrence,
    required this.createdAt,
    this.active = true,
    this.mandatory = false,
    List<int>? activeWeekdays,
    List<String>? assignedChildIds,
    String? startTime,
    String? dueTime,
    this.showInCalendar = false,
  })  : activeWeekdays = _normalizeWeekdays(activeWeekdays),
        assignedChildIds = _normalizeChildIds(assignedChildIds),
        startTime = normalizeTimeOfDay(startTime),
        dueTime = normalizeTimeOfDay(dueTime);

  /// Om opgaven er aktiv (kan udføres) på [date], ud fra [activeWeekdays].
  /// `null`/tom liste/alle 7 dage betyder altid aktiv.
  bool isActiveOn(DateTime date) {
    final weekdays = activeWeekdays;
    if (weekdays == null || weekdays.isEmpty) return true;
    return weekdays.contains(date.weekday);
  }

  Task copyWith({
    String? title,
    String? description,
    bool clearDescription = false,
    int? amountOre,
    Recurrence? recurrence,
    bool? active,
    bool? mandatory,
    List<int>? activeWeekdays,
    bool clearActiveWeekdays = false,
    List<String>? assignedChildIds,
    bool clearAssignedChildIds = false,
    String? startTime,
    bool clearStartTime = false,
    String? dueTime,
    bool clearDueTime = false,
    bool? showInCalendar,
  }) {
    return Task(
      id: id,
      title: title ?? this.title,
      description:
          clearDescription ? null : (description ?? this.description),
      amountOre: amountOre ?? this.amountOre,
      recurrence: recurrence ?? this.recurrence,
      createdAt: createdAt,
      active: active ?? this.active,
      mandatory: mandatory ?? this.mandatory,
      activeWeekdays: clearActiveWeekdays
          ? null
          : (activeWeekdays ?? this.activeWeekdays),
      assignedChildIds: clearAssignedChildIds
          ? null
          : (assignedChildIds ?? this.assignedChildIds),
      startTime: clearStartTime ? null : (startTime ?? this.startTime),
      dueTime: clearDueTime ? null : (dueTime ?? this.dueTime),
      showInCalendar: showInCalendar ?? this.showInCalendar,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'amount_ore': amountOre,
      'recurrence': recurrence.value,
      'created_at': createdAt.toIso8601String(),
      'active': active ? 1 : 0,
      'mandatory': mandatory ? 1 : 0,
      'active_weekdays': activeWeekdays?.join(','),
      'assigned_child_ids': assignedChildIds?.join(','),
      'start_time': startTime,
      'due_time': dueTime,
      'show_in_calendar': showInCalendar ? 1 : 0,
    };
  }

  factory Task.fromMap(Map<String, Object?> map) {
    final rawWeekdays = map['active_weekdays'] as String?;
    final rawChildIds = map['assigned_child_ids'] as String?;
    return Task(
      id: map['id'] as String,
      title: map['title'] as String,
      description: map['description'] as String?,
      amountOre: map['amount_ore'] as int,
      recurrence: Recurrence.fromValue(map['recurrence'] as String),
      createdAt: DateTime.parse(map['created_at'] as String),
      active: (map['active'] as int) == 1,
      // Defensivt fallback til 0/valgfri hvis en gammel række/DB-version
      // mangler kolonnen (bør ikke ske efter migrationen i
      // DatabaseHelper, men koster intet at være robust).
      mandatory: (map['mandatory'] as int? ?? 0) == 1,
      activeWeekdays: (rawWeekdays == null || rawWeekdays.isEmpty)
          ? null
          : rawWeekdays.split(',').map(int.parse).toList(),
      // 'null'/manglende kolonne betyder "alle børn" - korrekt for ALLE
      // opgaver oprettet før denne feature, ingen backfill nødvendig.
      assignedChildIds: (rawChildIds == null || rawChildIds.isEmpty)
          ? null
          : rawChildIds.split(','),
      startTime: map['start_time'] as String?,
      dueTime: map['due_time'] as String?,
      showInCalendar: (map['show_in_calendar'] as int? ?? 0) == 1,
    );
  }

  /// JSON-form brugt over sync-protokollen (camelCase-nøgler), adskilt
  /// fra [toMap]/[fromMap] der bruger databasens snake_case kolonnenavne.
  Map<String, Object?> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'amountOre': amountOre,
      'recurrence': recurrence.value,
      'createdAt': createdAt.toIso8601String(),
      'active': active,
      'mandatory': mandatory,
      'activeWeekdays': activeWeekdays,
      'assignedChildIds': assignedChildIds,
      'startTime': startTime,
      'dueTime': dueTime,
      'showInCalendar': showInCalendar,
    };
  }

  factory Task.fromJson(Map<String, Object?> json) {
    return Task(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      amountOre: json['amountOre'] as int,
      recurrence: Recurrence.fromValue(json['recurrence'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
      active: json['active'] as bool? ?? true,
      // '?? false'/'?? null' holder sync bagudkompatibel, hvis den anden
      // enhed (skærm/telefon) endnu ikke har fået denne opdatering.
      mandatory: json['mandatory'] as bool? ?? false,
      activeWeekdays:
          (json['activeWeekdays'] as List?)?.cast<int>(),
      // Samme bagudkompatible '?? null' (nøglen mangler helt hvis den
      // anden enhed endnu ikke kender "flere børn"-featuren) -> "alle
      // børn", som er korrekt for alle opgaver fra før den fandtes.
      assignedChildIds:
          (json['assignedChildIds'] as List?)?.cast<String>(),
      // Samme bagudkompatible mønster: en ældre enhed sender ikke
      // tidspunkter/kalender-valg -> ingen tider, ikke i kalenderen.
      startTime: json['startTime'] as String?,
      dueTime: json['dueTime'] as String?,
      showInCalendar: json['showInCalendar'] as bool? ?? false,
    );
  }
}

/// Normaliserer et klokkeslæt til `"HH:MM"` (fx `"7:5"` -> `"07:05"`), eller
/// `null` hvis værdien er tom eller ugyldig. Én entydig repræsentation i
/// DB/JSON, så sammenligninger og visning altid virker.
String? normalizeTimeOfDay(String? value) {
  final minutes = minutesOfDay(value);
  if (minutes == null) return null;
  final h = (minutes ~/ 60).toString().padLeft(2, '0');
  final m = (minutes % 60).toString().padLeft(2, '0');
  return '$h:$m';
}

/// `"HH:MM"` -> minutter efter midnat, eller `null` hvis ugyldig.
int? minutesOfDay(String? value) {
  if (value == null) return null;
  final parts = value.trim().split(':');
  if (parts.length != 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) {
    return null;
  }
  return h * 60 + m;
}
