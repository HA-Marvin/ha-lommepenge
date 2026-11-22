import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../providers/app_state.dart';

/// First screen on a new installation: choose the app's language. English is
/// preselected; the screen's own texts follow the choice right away.
class LanguageScreen extends StatefulWidget {
  const LanguageScreen({super.key});

  @override
  State<LanguageScreen> createState() => _LanguageScreenState();
}

class _LanguageScreenState extends State<LanguageScreen> {
  String _selected = defaultLanguage;

  @override
  Widget build(BuildContext context) {
    // The texts of the language being chosen, before it is saved.
    final l10n = l10nFor(_selected);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Lommepenge')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Icon(Icons.language, size: 64, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text(
                l10n.chooseLanguageTitle,
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(l10n.chooseLanguageBody, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              _LanguageList(
                selected: _selected,
                onSelected: (code) => setState(() => _selected = code),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => context.read<AppState>().setLanguage(_selected),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(l10n.continueButton),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lets the user change the app's language later (settings, connect screen,
/// child's tablet).
Future<void> showLanguagePicker(BuildContext context) async {
  final appState = context.read<AppState>();
  final chosen = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(ctx.l10n.language),
      contentPadding: const EdgeInsets.symmetric(vertical: 16),
      content: _LanguageList(
        selected: appState.language,
        onSelected: (code) => Navigator.of(ctx).pop(code),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(ctx.l10n.cancel),
        ),
      ],
    ),
  );
  if (chosen != null && chosen != appState.language) {
    await appState.setLanguage(chosen);
  }
}

/// App bar button that opens [showLanguagePicker].
class LanguageButton extends StatelessWidget {
  const LanguageButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.language),
      tooltip: context.l10n.language,
      onPressed: () => showLanguagePicker(context),
    );
  }
}

/// The supported languages, each shown by its own name.
class _LanguageList extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelected;

  const _LanguageList({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final entry in supportedLanguages.entries)
          ListTile(
            leading: Icon(
              entry.key == selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: entry.key == selected
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
            title: Text(entry.value),
            onTap: () => onSelected(entry.key),
          ),
      ],
    );
  }
}
