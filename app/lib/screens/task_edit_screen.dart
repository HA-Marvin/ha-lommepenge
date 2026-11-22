import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/task.dart';
import '../providers/app_state.dart';

/// Formular til at oprette en ny opgave, eller redigere en eksisterende
/// hvis [task] er sat.
class TaskEditScreen extends StatefulWidget {
  final Task? task;
  const TaskEditScreen({super.key, this.task});

  @override
  State<TaskEditScreen> createState() => _TaskEditScreenState();
}

/// De 7 ugedage i dansk visningsrækkefølge (mandag først), sammen med
/// deres `DateTime.weekday`-værdi (1=mandag...7=søndag).
const List<MapEntry<int, String>> _kWeekdayLabels = [
  MapEntry(1, 'Man'),
  MapEntry(2, 'Tir'),
  MapEntry(3, 'Ons'),
  MapEntry(4, 'Tor'),
  MapEntry(5, 'Fre'),
  MapEntry(6, 'Lør'),
  MapEntry(7, 'Søn'),
];

class _TaskEditScreenState extends State<TaskEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _amountController;
  late Recurrence _recurrence;
  late bool _mandatory;

  /// `null` betyder "alle dage" (intet ugedags-filter). Holdes altid
  /// normaliseret sådan (aldrig en liste med alle 7 dage) for en klar,
  /// entydig UI-tilstand - se [_setWeekdays].
  List<int>? _activeWeekdays;

  /// `null` betyder "alle børn" (dynamisk - gælder også børn tilføjet
  /// senere). Ellers en eksplicit liste af barn-id'er - se
  /// [_toggleChild].
  List<String>? _assignedChildIds;

  /// `"HH:MM"` eller `null` (ingen tid / familiens standardfrist).
  String? _startTime;
  String? _dueTime;
  late bool _showInCalendar;

  bool _saving = false;

  bool get _isEditing => widget.task != null;

  @override
  void initState() {
    super.initState();
    final task = widget.task;
    _titleController = TextEditingController(text: task?.title ?? '');
    _descriptionController =
        TextEditingController(text: task?.description ?? '');
    _amountController = TextEditingController(
      text: task != null ? _oreToKrString(task.amountOre) : '',
    );
    _recurrence = task?.recurrence ?? Recurrence.once;
    _mandatory = task?.mandatory ?? false;
    _activeWeekdays = task?.activeWeekdays;
    _assignedChildIds = task?.assignedChildIds;
    _startTime = task?.startTime;
    _dueTime = task?.dueTime;
    _showInCalendar = task?.showInCalendar ?? false;
  }

  /// Åbner tidsvælgeren og returnerer `"HH:MM"`, eller `null` ved annullér.
  Future<String?> _pickTime(String? current, String fallback) async {
    final minutes = minutesOfDay(current ?? fallback) ?? 0;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null) return null;
    return normalizeTimeOfDay('${picked.hour}:${picked.minute}');
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  String _oreToKrString(int ore) {
    if (ore % 100 == 0) return (ore ~/ 100).toString();
    return (ore / 100).toStringAsFixed(2);
  }

  int? _parseKrToOre(String input) {
    final normalized = input.trim().replaceAll(',', '.');
    final value = double.tryParse(normalized);
    if (value == null) return null;
    return (value * 100).round();
  }

  /// Sætter ugeplanen og normaliserer "alle 7 dage markeret" til `null`,
  /// så UI'et altid har én entydig repræsentation af "alle dage".
  void _setWeekdays(Set<int> weekdays) {
    setState(() {
      _activeWeekdays = (weekdays.isEmpty || weekdays.length >= 7)
          ? null
          : (weekdays.toList()..sort());
    });
  }

  void _toggleWeekday(int weekday, bool selected) {
    final current = (_activeWeekdays == null || _activeWeekdays!.isEmpty)
        ? _kWeekdayLabels.map((e) => e.key).toSet()
        : _activeWeekdays!.toSet();
    if (selected) {
      current.add(weekday);
    } else {
      current.remove(weekday);
    }
    _setWeekdays(current);
  }

  /// Vælger/fravælger ét barn. Starter fra en tom eksplicit liste hvis
  /// "alle børn" (`null`) pt. er valgt - dvs. at trykke på ét
  /// barne-chip mens "alle børn" er valgt, skifter til "kun dette barn"
  /// i stedet for at fjerne det fra en implicit "alle"-liste.
  void _toggleChild(String childId, bool selected) {
    setState(() {
      final current = (_assignedChildIds == null || _assignedChildIds!.isEmpty)
          ? <String>{}
          : _assignedChildIds!.toSet();
      if (selected) {
        current.add(childId);
      } else {
        current.remove(childId);
      }
      _assignedChildIds = current.isEmpty ? null : current.toList();
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    final appState = context.read<AppState>();
    final amountOre = _parseKrToOre(_amountController.text)!;
    final description = _descriptionController.text.trim();
    // 'Engang' har ingen ugeplan - sendes altid som "alle dage" (null),
    // uanset hvad der evt. var valgt tidligere/på en anden gentagelse.
    final weekdaysToSave =
        _recurrence == Recurrence.once ? null : _activeWeekdays;

    try {
      if (_isEditing) {
        await appState.editTask(
          widget.task!.id,
          title: _titleController.text.trim(),
          description: description.isEmpty ? null : description,
          amountOre: amountOre,
          recurrence: _recurrence,
          mandatory: _mandatory,
          activeWeekdays: weekdaysToSave,
          assignedChildIds: _assignedChildIds,
          startTime: _startTime,
          dueTime: _dueTime,
          showInCalendar: _showInCalendar,
        );
      } else {
        await appState.createTask(
          title: _titleController.text.trim(),
          description: description.isEmpty ? null : description,
          amountOre: amountOre,
          recurrence: _recurrence,
          mandatory: _mandatory,
          activeWeekdays: weekdaysToSave,
          assignedChildIds: _assignedChildIds,
          startTime: _startTime,
          dueTime: _dueTime,
          showInCalendar: _showInCalendar,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final showWeekPlan = _recurrence != Recurrence.once;
    final children = context.watch<AppState>().children;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Redigér opgave' : 'Ny opgave'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Titel',
                border: OutlineInputBorder(),
              ),
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? 'Titel er påkrævet.'
                  : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Beskrivelse (valgfri)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _amountController,
              decoration: const InputDecoration(
                labelText: 'Beløb (kr)',
                border: OutlineInputBorder(),
                suffixText: 'kr',
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]')),
              ],
              validator: (value) {
                final parsed = _parseKrToOre(value ?? '');
                if (parsed == null || parsed < 0) {
                  return 'Angiv et gyldigt beløb (0 eller derover).';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            Text('Gentagelse', style: Theme.of(context).textTheme.titleSmall),
            RadioListTile<Recurrence>(
              title: const Text('Engang'),
              value: Recurrence.once,
              groupValue: _recurrence,
              onChanged: (v) => setState(() => _recurrence = v!),
            ),
            RadioListTile<Recurrence>(
              title: const Text('Dagligt'),
              value: Recurrence.daily,
              groupValue: _recurrence,
              onChanged: (v) => setState(() => _recurrence = v!),
            ),
            // 'Ugentligt' tilbydes ikke længere til nye/ændrede opgaver
            // (ugeplan på 'Dagligt' dækker samme behov mere fleksibelt) -
            // men vises stadig HVIS opgaven allerede er ugentlig, så
            // redigeringsskærmen ikke fremstår i stykker for eksisterende
            // opgaver, og så forælderen aktivt skal vælge noget andet for
            // at skifte væk fra det.
            if (_recurrence == Recurrence.weekly)
              RadioListTile<Recurrence>(
                title: const Text('Ugentligt'),
                subtitle: const Text(
                  'Udgået - vælg i stedet "Dagligt" og sæt ugeplanen til '
                  'den/de ønskede dage.',
                ),
                value: Recurrence.weekly,
                groupValue: _recurrence,
                onChanged: (v) => setState(() => _recurrence = v!),
              ),
            RadioListTile<Recurrence>(
              title: const Text('Ubegrænset'),
              subtitle: const Text(
                'Kan udføres flere gange om dagen - blokeres kun mens en '
                'udførelse venter på godkendelse.',
              ),
              value: Recurrence.unlimited,
              groupValue: _recurrence,
              onChanged: (v) => setState(() => _recurrence = v!),
            ),
            if (showWeekPlan) ...[
              const SizedBox(height: 16),
              Text('Ugeplan', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(
                'Vælg hvilke dage opgaven er aktiv, fx kun tirsdag og '
                'torsdag. Default er alle dage.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  OutlinedButton(
                    onPressed: () => _setWeekdays({}),
                    child: const Text('Alle dage'),
                  ),
                  OutlinedButton(
                    onPressed: () => _setWeekdays({1, 2, 3, 4, 5}),
                    child: const Text('Hverdage'),
                  ),
                  OutlinedButton(
                    onPressed: () => _setWeekdays({6, 7}),
                    child: const Text('Weekend'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _kWeekdayLabels.map((entry) {
                  final weekday = entry.key;
                  final label = entry.value;
                  final selected = _activeWeekdays == null ||
                      _activeWeekdays!.isEmpty ||
                      _activeWeekdays!.contains(weekday);
                  return FilterChip(
                    label: Text(label),
                    selected: selected,
                    onSelected: (v) => _toggleWeekday(weekday, v),
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: 16),
            Text('Tildel til', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              'Vælg hvilke børn opgaven gælder for. "Alle børn" gælder '
              'dynamisk - også for børn der tilføjes senere.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilterChip(
                  label: const Text('Alle børn'),
                  selected:
                      _assignedChildIds == null || _assignedChildIds!.isEmpty,
                  onSelected: (_) => setState(() => _assignedChildIds = null),
                ),
                ...children.map((child) {
                  final selected = _assignedChildIds != null &&
                      _assignedChildIds!.contains(child.id);
                  return FilterChip(
                    label: Text(child.name),
                    selected: selected,
                    onSelected: (v) => _toggleChild(child.id, v),
                  );
                }),
              ],
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              title: const Text('Obligatorisk opgave'),
              subtitle: const Text(
                'Vises tydeligt markeret som "skal udføres" i stedet for '
                '"kan udføres".',
              ),
              value: _mandatory,
              onChanged: (v) => setState(() => _mandatory = v),
            ),
            const SizedBox(height: 8),
            Text('Tidspunkt', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              _mandatory
                  ? 'Efter fristen tæller opgaven som forsinket. Uden egen '
                      'frist bruges familiens standardfrist '
                      '(${appStateFamilyDefault(context)}).'
                  : 'Valgfrit. Fristen følges kun op på obligatoriske opgaver.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            _TimeRow(
              label: 'Fra',
              value: _startTime,
              emptyText: 'Ingen',
              onPick: () async {
                final t = await _pickTime(_startTime, '07:00');
                if (t != null) setState(() => _startTime = t);
              },
              onClear: () => setState(() => _startTime = null),
            ),
            _TimeRow(
              label: 'Frist',
              value: _dueTime,
              emptyText: _mandatory ? 'Standard' : 'Ingen',
              onPick: () async {
                final t = await _pickTime(
                  _dueTime,
                  appStateFamilyDefault(context),
                );
                if (t != null) setState(() => _dueTime = t);
              },
              onClear: () => setState(() => _dueTime = null),
            ),
            SwitchListTile(
              title: const Text('Vis i familiekalenderen'),
              subtitle: const Text(
                'Opgaven bliver til en aftale i familiens kalender, når '
                'kalenderen er sat op.',
              ),
              value: _showInCalendar,
              onChanged: (v) => setState(() => _showInCalendar = v),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(_saving ? 'Gemmer...' : 'Gem opgave'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Familiens nuværende standardfrist, til visning i formularen.
String appStateFamilyDefault(BuildContext context) =>
    context.read<AppState>().familySettings.defaultDueTime;

class _TimeRow extends StatelessWidget {
  final String label;
  final String? value;
  final String emptyText;
  final VoidCallback onPick;
  final VoidCallback onClear;

  const _TimeRow({
    required this.label,
    required this.value,
    required this.emptyText,
    required this.onPick,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.schedule),
      title: Text(label),
      subtitle: Text(value ?? emptyText),
      onTap: onPick,
      trailing: value == null
          ? null
          : IconButton(
              icon: const Icon(Icons.clear),
              tooltip: 'Fjern tid',
              onPressed: onClear,
            ),
    );
  }
}
