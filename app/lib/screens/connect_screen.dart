import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import 'qr_scan_screen.dart';

/// Første skærm på en ny enhed: forbind til Home Assistant.
///
/// Enheden tilføjes i Home Assistant (Lommepenge → Tilføj enhed), hvor
/// rollen vælges. Derefter enten scannes QR-koden her, eller også trykkes
/// "Åbn appen og forbind" på installationssiden - så forbinder appen af sig
/// selv (se `AppState.connectWithLink`).
class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final _linkController = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _linkController.dispose();
    super.dispose();
  }

  Future<void> _connect(String link) async {
    setState(() => _busy = true);
    await context.read<AppState>().connectWithLink(link);
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _scan() async {
    final value = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const QrScanScreen()),
    );
    if (value != null) await _connect(value);
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Lommepenge')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Icon(Icons.home_outlined, size: 64, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text(
                'Forbind til Home Assistant',
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              const Text(
                'Familiens opgaver og lommepenge ligger i Home Assistant. '
                'Tilføj enheden dér under Lommepenge → Tilføj enhed, og vælg '
                'om den er den fælles skærm, en forælders telefon eller et '
                'barns tablet. Scan derefter QR-koden.',
                textAlign: TextAlign.center,
              ),
              if (appState.connectionMessage != null) ...[
                const SizedBox(height: 16),
                Card(
                  color: theme.colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      appState.connectionMessage!,
                      style: TextStyle(color: theme.colorScheme.onErrorContainer),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              if (_busy)
                const Center(child: CircularProgressIndicator())
              else ...[
                FilledButton.icon(
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('Scan QR-kode'),
                  ),
                  onPressed: _scan,
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _linkController,
                  decoration: const InputDecoration(
                    labelText: 'Eller indsæt linket fra Home Assistant',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.url,
                  onSubmitted: _connect,
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => _connect(_linkController.text),
                  child: const Text('Forbind'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
