import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/family_settings.dart';
import '../models/task.dart';
import '../providers/app_state.dart';

/// "Indstillinger"-fanen i forælder-tilstand: familiens tider og grænser
/// (de samme værdier kan rettes fra Home Assistant), dagens spærringer og
/// enhedens forbindelse til Home Assistant.
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
            child: const Text('Annullér'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(ctx).pop(int.tryParse(controller.text)),
            child: const Text('Gem'),
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
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text('Tider og grænser', style: title),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(
            'Kan også rettes fra Home Assistant. Tryk for at ændre.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        timeTile('defaultDueTime', 'Standardfrist', s.defaultDueTime,
            'For obligatoriske opgaver uden egen frist.'),
        timeTile('restrictionStart', 'Spærretid fra', s.restrictionStart,
            'Tablets kan tidligst spærres fra dette tidspunkt.'),
        timeTile('restrictionEnd', 'Spærretid til', s.restrictionEnd,
            'Efter dette tidspunkt ophæves spærringen.'),
        numberTile('latePauseMinutes', 'Pausetid', s.latePauseMinutes, 'min',
            'Ventetid før tabletten låses op, når en opgave er udført for sent.'),
        numberTile('warningMinutes', 'Advarsel før frist', s.warningMinutes,
            'min', 'Hvor længe før fristen barnet advares.'),
        numberTile('winterFromWeek', 'Vinter fra uge', s.winterFromWeek, '',
            'Bruges til pakkelister (fx indendørssko).'),
        numberTile('winterToWeek', 'Vinter til uge', s.winterToWeek, '',
            'Bruges til pakkelister (fx indendørssko).'),
        TextButton(
          onPressed: () async {
            for (final entry in FamilySettings.defaults.toJson().entries) {
              await _save(context, entry.key, entry.value);
              if (!context.mounted) return;
            }
          },
          child: const Text('Nulstil til standard'),
        ),
        const Divider(height: 32),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text('Spærring i dag', style: title),
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
    final child = appState.childrenById[childId]!;
    final f = appState.followUpFor(childId);
    final String status;
    if (f == null) {
      status = '';
    } else if (f.suspended) {
      status = 'Ophævet for i dag';
    } else if (f.restricted) {
      status = f.reason ?? 'Spærret';
    } else if (f.overdue.isNotEmpty) {
      status = 'Forsinket, men uden for spærretiden';
    } else {
      status = 'Ikke spærret';
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
              child: const Text('Ophæv i dag'),
            ),
    );
  }
}

class _ConnectionSection extends StatelessWidget {
  const _ConnectionSection();

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final connection = appState.connection;
    final lastSync = appState.lastSyncAt;
    final role = appState.isScreen ? 'Fælles skærm' : 'Forælders telefon';

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
              '$role · app-version '
              '${appState.appVersion.isEmpty ? '?' : appState.appVersion}',
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.home_outlined),
            title: Text(connection?.baseUrl.toString() ?? 'Ikke forbundet'),
            subtitle: Text(
              lastSync == null
                  ? (appState.syncMessage ?? 'Ikke hentet endnu')
                  : 'Senest opdateret kl. '
                      '${lastSync.hour.toString().padLeft(2, '0')}:'
                      '${lastSync.minute.toString().padLeft(2, '0')}',
            ),
          ),
          const Text(
            'Nye enheder tilføjes i Home Assistant under Lommepenge → '
            'Tilføj enhed. Dér fjernes de også igen.',
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.link_off),
            label: const Text('Glem forbindelsen på denne enhed'),
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Glem forbindelsen?'),
                  content: const Text(
                    'Enheden skal forbindes igen med en ny QR-kode fra Home '
                    'Assistant. Fjern den også under Lommepenge i Home '
                    'Assistant, hvis den ikke skal bruges mere.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: const Text('Annullér'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      child: const Text('Glem'),
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
