import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../models/family_settings.dart';
import '../models/task.dart';
import '../providers/app_state.dart';
import '../widgets/action_feedback.dart';
import 'language_screen.dart';

/// The "Settings" tab in parent mode: the app's language, the family's times
/// and limits (from HA's state; the same values can be changed from Home
/// Assistant) and the device's connection to Home Assistant.
class SettingsTabContent extends StatelessWidget {
  const SettingsTabContent({super.key});

  /// Sends the setting to HA; returns whether HA accepted it.
  Future<bool> _save(
    BuildContext context,
    String key,
    Object value,
  ) {
    final appState = context.read<AppState>();
    return runAction(context, () => appState.setFamilySetting(key, value));
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
    final value = await showDialog<int>(
      context: context,
      builder: (_) => _NumberDialog(label: label, current: current),
    );
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
          trailing: appState.isBusy(AppState.settingKey(key))
              ? const BusyIndicator()
              : Text(value, style: title),
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
          trailing: appState.isBusy(AppState.settingKey(key))
              ? const BusyIndicator()
              : Text('$value $unit', style: title),
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
        numberTile('lockMinutes', l10n.lockMinutes, s.lockMinutes,
            l10n.minutesUnit, l10n.lockMinutesHelp),
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
              if (!await _save(context, entry.key, entry.value)) return;
              if (!context.mounted) return;
            }
          },
          child: Text(l10n.resetToDefaults),
        ),
        const Divider(height: 32),
        const _ConnectionSection(),
      ],
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

/// Asks for a whole number; returns it, or `null` when cancelled. Owns its
/// text controller, so it lives as long as the dialog's closing animation
/// (disposing it right after `showDialog` returns crashed that animation).
class _NumberDialog extends StatefulWidget {
  final String label;
  final int current;

  const _NumberDialog({required this.label, required this.current});

  @override
  State<_NumberDialog> createState() => _NumberDialogState();
}

class _NumberDialogState extends State<_NumberDialog> {
  late final _controller = TextEditingController(text: '${widget.current}');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.label),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop(int.tryParse(_controller.text)),
          child: Text(context.l10n.save),
        ),
      ],
    );
  }
}
