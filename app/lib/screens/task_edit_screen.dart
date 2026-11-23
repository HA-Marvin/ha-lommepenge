import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../l10n/l10n.dart';
import '../models/task.dart';
import '../providers/app_state.dart';
import '../widgets/action_feedback.dart';

/// Form to create a new task, or edit an existing one if [task] is set. The
/// screen closes when Home Assistant has confirmed the change; on an error it
/// stays open, so "Save" can simply be tapped again.
class TaskEditScreen extends StatefulWidget {
  final Task? task;
  const TaskEditScreen({super.key, this.task});

  @override
  State<TaskEditScreen> createState() => _TaskEditScreenState();
}

class _TaskEditScreenState extends State<TaskEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _amountController;
  late Recurrence _recurrence;
  late bool _mandatory;

  /// `null` means "every day" (no weekday filter). Always kept normalized
  /// like that (never a list with all 7 days) for a clear, unambiguous UI
  /// state - see [_setWeekdays].
  List<int>? _activeWeekdays;

  /// `null` means "all children" (dynamic - also applies to children added
  /// later). Otherwise an explicit list of child ids - see [_toggleChild].
  List<String>? _assignedChildIds;

  /// `"HH:MM"` or `null` (no time / the family's default deadline).
  String? _startTime;
  String? _dueTime;
  late bool _showInCalendar;

  bool _saving = false;

  /// The new task's id, made once for this form: saving again after an error
  /// sends the same id, so HA does not create the task twice.
  final String _newTaskId = const Uuid().v4();

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

  /// Opens the time picker and returns `"HH:MM"`, or `null` if cancelled.
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

  /// Sets the week plan and normalizes "all 7 days selected" to `null`, so
  /// the UI always has one unambiguous representation of "every day".
  void _setWeekdays(Set<int> weekdays) {
    setState(() {
      _activeWeekdays = (weekdays.isEmpty || weekdays.length >= 7)
          ? null
          : (weekdays.toList()..sort());
    });
  }

  void _toggleWeekday(int weekday, bool selected) {
    final current = (_activeWeekdays == null || _activeWeekdays!.isEmpty)
        ? {1, 2, 3, 4, 5, 6, 7}
        : _activeWeekdays!.toSet();
    if (selected) {
      current.add(weekday);
    } else {
      current.remove(weekday);
    }
    _setWeekdays(current);
  }

  /// Selects/deselects one child. Starts from an empty explicit list if "all
  /// children" (`null`) is currently selected - i.e. tapping one child chip
  /// while "all children" is selected switches to "only this child" instead
  /// of removing it from an implicit "all" list.
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
    // 'Once' has no week plan - always sent as "every day" (null), regardless
    // of what may have been chosen before/on another recurrence.
    final weekdaysToSave =
        _recurrence == Recurrence.once ? null : _activeWeekdays;

    final task = Task(
      id: widget.task?.id ?? _newTaskId,
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
    final saved = await runAction(
      context,
      () => _isEditing ? appState.editTask(task) : appState.createTask(task),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (saved) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final showWeekPlan = _recurrence != Recurrence.once;
    final appState = context.watch<AppState>();
    final children = appState.children;
    final currency = appState.currency;
    final l10n = context.l10n;
    final defaultDue = appStateFamilyDefault(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? l10n.editTask : l10n.newTask),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _titleController,
              decoration: InputDecoration(
                labelText: l10n.taskTitle,
                border: const OutlineInputBorder(),
              ),
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? l10n.titleRequired
                  : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descriptionController,
              decoration: InputDecoration(
                labelText: l10n.descriptionOptional,
                border: const OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _amountController,
              decoration: InputDecoration(
                labelText: l10n.amountLabel(currency),
                border: const OutlineInputBorder(),
                suffixText: currency,
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]')),
              ],
              validator: (value) {
                final parsed = _parseKrToOre(value ?? '');
                if (parsed == null || parsed < 0) {
                  return l10n.amountInvalid;
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            Text(l10n.recurrence, style: Theme.of(context).textTheme.titleSmall),
            RadioListTile<Recurrence>(
              title: Text(Recurrence.once.label(l10n)),
              value: Recurrence.once,
              groupValue: _recurrence,
              onChanged: (v) => setState(() => _recurrence = v!),
            ),
            RadioListTile<Recurrence>(
              title: Text(Recurrence.daily.label(l10n)),
              value: Recurrence.daily,
              groupValue: _recurrence,
              onChanged: (v) => setState(() => _recurrence = v!),
            ),
            // 'Weekly' is no longer offered for new/changed tasks (a week plan
            // on 'Daily' covers the same need more flexibly) - but is still
            // shown IF the task is already weekly, so the edit screen does not
            // look broken for existing tasks, and so the parent has to
            // actively choose something else to switch away from it.
            if (_recurrence == Recurrence.weekly)
              RadioListTile<Recurrence>(
                title: Text(Recurrence.weekly.label(l10n)),
                subtitle: Text(l10n.weeklyDiscontinued),
                value: Recurrence.weekly,
                groupValue: _recurrence,
                onChanged: (v) => setState(() => _recurrence = v!),
              ),
            RadioListTile<Recurrence>(
              title: Text(Recurrence.unlimited.label(l10n)),
              subtitle: Text(l10n.unlimitedHelp),
              value: Recurrence.unlimited,
              groupValue: _recurrence,
              onChanged: (v) => setState(() => _recurrence = v!),
            ),
            if (showWeekPlan) ...[
              const SizedBox(height: 16),
              Text(l10n.weekPlan, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(
                l10n.weekPlanHelp,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  OutlinedButton(
                    onPressed: () => _setWeekdays({}),
                    child: Text(l10n.allDays),
                  ),
                  OutlinedButton(
                    onPressed: () => _setWeekdays({1, 2, 3, 4, 5}),
                    child: Text(l10n.weekdays),
                  ),
                  OutlinedButton(
                    onPressed: () => _setWeekdays({6, 7}),
                    child: Text(l10n.weekend),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: weekdayLabels(l10n).map((entry) {
                  final weekday = entry.key;
                  final selected = _activeWeekdays == null ||
                      _activeWeekdays!.isEmpty ||
                      _activeWeekdays!.contains(weekday);
                  return FilterChip(
                    label: Text(entry.value),
                    selected: selected,
                    onSelected: (v) => _toggleWeekday(weekday, v),
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: 16),
            Text(l10n.assignTo, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              l10n.assignToHelp,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilterChip(
                  label: Text(l10n.allChildren),
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
              title: Text(l10n.mandatoryTask),
              subtitle: Text(l10n.mandatoryTaskHelp),
              value: _mandatory,
              onChanged: (v) => setState(() => _mandatory = v),
            ),
            const SizedBox(height: 8),
            Text(l10n.timeOfDay, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              _mandatory
                  ? l10n.timeHelpMandatory(defaultDue)
                  : l10n.timeHelpOptional,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            _TimeRow(
              label: l10n.fromLabel,
              value: _startTime,
              emptyText: l10n.none,
              onPick: () async {
                final t = await _pickTime(_startTime, '07:00');
                if (t != null) setState(() => _startTime = t);
              },
              onClear: () => setState(() => _startTime = null),
            ),
            _TimeRow(
              label: l10n.deadline,
              value: _dueTime,
              emptyText: _mandatory ? l10n.defaultLabel : l10n.none,
              onPick: () async {
                final t = await _pickTime(_dueTime, defaultDue);
                if (t != null) setState(() => _dueTime = t);
              },
              onClear: () => setState(() => _dueTime = null),
            ),
            SwitchListTile(
              title: Text(l10n.showInCalendar),
              subtitle: Text(l10n.showInCalendarHelp),
              value: _showInCalendar,
              onChanged: (v) => setState(() => _showInCalendar = v),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(_saving ? l10n.saving : l10n.saveTask),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The family's current default deadline, for display in the form.
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
              tooltip: context.l10n.removeTime,
              onPressed: onClear,
            ),
    );
  }
}
