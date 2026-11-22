import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../models/family_settings.dart';
import '../models/task.dart';
import '../providers/app_state.dart';
import 'language_screen.dart';

/// The "Settings" tab in parent mode: the app's language, the family's times
/// and limits (the same values can be changed from Home Assistant), today's
/// restrictions and the device's connection to Home Assistant.
class SettingsTabContent extends StatelessWidget {
  const SettingsTabContent({super.key});

  Future<void> _save(
    BuildContext context,
    String key,
    Object value,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<AppState>().setFamilySetting(key, value);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _editTime(
    BuildContext context,
    String key,
    String current,
  ) async {
    final minutes = minutesOfDay(current) ?? 0;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null || !context.mounted) return;
    await _save(context, key, '${picked.hour}:${picked.minute}');
  }

  Future<void> _editNumber(
    BuildContext context,
    String key,
    String label,
    int current,
  ) async {
    final controller = TextEditingController(text: '$current');
    final value = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(label),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(ctx.l10n.cancel),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(ctx).pop(int.tryParse(controller.text)),
            child: Text(ctx.l10n.save),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || !context.mounted) return;
    await _save(context, key, value);
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final s = appState.familySettings;
    final title = Theme.of(context).textTheme.titleMedium;
    final l10n = context.l10n;

    Widget timeTile(String key, String label, String value, String help) =>
        ListTile(
          leading: const Icon(Icons.schedule),
          title: Text(label),
          subtitle: Text(help),
          trailing: Text(value, style: title),
          onTap: () => _editTime(context, key, value),
        );

    Widget numberTile(
      String key,
      String label,
      int value,
      String unit,
      String help,
    ) =>
        ListTile(
          leading: const Icon(Icons.timer_outlined),
          title: Text(label),
          subtitle: Text(help),
          trailing: Text('$value $unit', style: title),
          onTap: () => _editNumber(context, key, label, value),
        );

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      children: [
        ListTile(
          leading: const Icon(Icons.language),
          title: Text(l10n.language),
          trailing: Text(
            supportedLanguages[appState.language]!,
            style: title,
          ),
          onTap: () => showLanguagePicker(context),
        ),
        const Divider(height: 32),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(l10n.timesAndLimits, style: title),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(
            l10n.timesAndLimitsHint,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        timeTile('defaultDueTime', l10n.defaultDeadline, s.defaultDueTime,
            l10n.defaultDeadlineHelp),
        timeTile('restrictionStart', l10n.restrictionFrom, s.restrictionStart,
            l10n.restrictionFromHelp),
        timeTile('restrictionEnd', l10n.restrictionUntil, s.restrictionEnd,
            l10n.restrictionUntilHelp),
        numberTile('latePauseMinutes', l10n.pauseTime, s.latePauseMinutes,
            l10n.minutesUnit, l10n.pauseTimeHelp),
        numberTile('warningMinutes', l10n.warningBeforeDeadline,
            s.warningMinutes, l10n.minutesUnit, l10n.warningBeforeDeadlineHelp),
        numberTile('winterFromWeek', l10n.winterFromWeek, s.winterFromWeek, '',
            l10n.winterHelp),
        numberTile('winterToWeek', l10n.winterToWeek, s.winterToWeek, '',
            l10n.winterHelp),
        TextButton(
          onPressed: () async {
            for (final entry in FamilySettings.defaults.toJson().entries) {
              await _save(context, entry.key, entry.value);
              if (!context.mounted) return;
            }
          },
          child: Text(l10n.resetToDefaults),
        ),
        const Divider(height: 32),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(l10n.restrictionToday, style: title),
        ),
        for (final child in appState.children)
          _RestrictionTile(appState: appState, childId: child.id),
        const Divider(height: 32),
        const _ConnectionSection(),
      ],
    );
  }
}

class _RestrictionTile extends StatelessWidget {
  final AppState appState;
  final String childId;

  const _RestrictionTile({required this.appState, required this.childId});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final child = appState.childrenById[childId]!;
    final f = appState.followUpFor(childId);
    final String status;
    if (f == null) {
      status = '';
    } else if (f.suspended) {
      status = l10n.liftedForToday;
    } else if (f.restricted) {
      status = f.reason(l10n) ?? l10n.restricted;
    } else if (f.overdue.isNotEmpty) {
      status = l10n.overdueOutsideWindow;
    } else {
      status = l10n.notRestricted;
    }
    return ListTile(
      leading: Icon(
        f?.restricted == true ? Icons.block : Icons.check_circle_outline,
        color: f?.restricted == true ? Colors.red : Colors.green,
      ),
      title: Text(child.name),
      subtitle: Text(status),
      trailing: (f == null || f.suspended)
          ? null
          : TextButton(
              onPressed: () => appState.suspendRestriction(childId),
              child: Text(l10n.liftToday),
            ),
    );
  }
}

class _ConnectionSection extends StatelessWidget {
  const _ConnectionSection();

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final l10n = context.l10n;
    final connection = appState.connection;
    final lastSync = appState.lastSyncAt;
    final role = appState.isScreen ? l10n.roleFamilyScreen : l10n.roleParentPhone;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Home Assistant', style: Theme.of(context).textTheme.titleMedium),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.devices_other),
            title: Text(appState.settings.deviceName),
            subtitle: Text(
              l10n.deviceSubtitle(
                role,
                appState.appVersion.isEmpty ? '?' : appState.appVersion,
              ),
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.home_outlined),
            title: Text(connection?.baseUrl.toString() ?? l10n.notConnected),
            subtitle: Text(
              lastSync == null
                  ? (appState.syncMessage ?? l10n.notFetchedYet)
                  : l10n.lastUpdatedAt(formatTimeOfDay(lastSync)),
            ),
          ),
          Text(l10n.addDevicesHint),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.link_off),
            label: Text(l10n.forgetConnection),
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text(ctx.l10n.forgetConnectionTitle),
                  content: Text(ctx.l10n.forgetConnectionBody),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: Text(ctx.l10n.cancel),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      child: Text(ctx.l10n.forget),
                    ),
                  ],
                ),
              );
              if (confirmed == true && context.mounted) {
                Navigator.of(context).popUntil((route) => route.isFirst);
                await appState.disconnect();
              }
            },
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
