import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import 'qr_scan_screen.dart';

/// Første skærm på en ny enhed: forbind til Home Assistant.
///
/// Enheden tilføjes i Home Assistant (Lommepenge → Tilføj enhed), hvor
/// rollen vælges. Derefter enten scannes QR-koden her, trykkes "Åbn appen og
/// forbind" på installationssiden, eller - på en enhed uden kamera - tastes
/// HA's adresse og koden (se `AppState.connectWithLink`/`connectWithCode`).
class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final _addressController = TextEditingController();
  final _codeController = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _addressController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _run(Future<String?> Function(AppState) connect) async {
    setState(() => _busy = true);
    await connect(context.read<AppState>());
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _scan() async {
    final value = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const QrScanScreen()),
    );
    if (value != null) await _run((s) => s.connectWithLink(value));
  }

  Future<void> _connectWithCode() => _run(
        (s) => s.connectWithCode(_addressController.text, _codeController.text),
      );

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
                'barns tablet. Scan derefter QR-koden, eller tast koden '
                'herunder.',
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
                const SizedBox(height: 32),
                Text('Forbind med kode', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                const Text(
                  'Til enheder uden kamera. Adressen og koden står i Home '
                  'Assistant under "Tilføj enhed".',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _addressController,
                  decoration: const InputDecoration(
                    labelText: 'Home Assistant-adresse',
                    hintText: 'fx 192.168.1.10:8123',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _codeController,
                  decoration: const InputDecoration(
                    labelText: 'Kode',
                    hintText: 'fx K7M2QDXA',
                    border: OutlineInputBorder(),
                  ),
                  textCapitalization: TextCapitalization.characters,
                  autocorrect: false,
                  onSubmitted: (_) => _connectWithCode(),
                ),
                const SizedBox(height: 12),
                FilledButton.tonal(
                  onPressed: _connectWithCode,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('Forbind'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
