import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import 'qr_scan_screen.dart';

/// Første skærm på en ny enhed: forbind til Home Assistant.
///
/// Enheden tilføjes i Home Assistant (Lommepenge → Tilføj enhed), hvor
/// rollen vælges, og HA viser en kode. Appen finder selv Home Assistant på
/// netværket, så man normalt kun skal taste koden. Har enheden kamera, kan
/// QR-koden scannes i stedet (se `AppState.connectWithCode`/
/// `connectWithLink`).
class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final _addressController = TextEditingController();
  final _codeController = TextEditingController();
  bool _busy = false;
  bool _searching = true;
  String? _foundName;

  @override
  void initState() {
    super.initState();
    _discover();
  }

  @override
  void dispose() {
    _addressController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _discover() async {
    setState(() => _searching = true);
    final found = await context.read<AppState>().discoverHa();
    if (!mounted) return;
    setState(() {
      _searching = false;
      if (found.isNotEmpty) {
        _foundName = found.first.name;
        if (_addressController.text.isEmpty) {
          _addressController.text = found.first.url;
        }
      }
    });
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
                'Tilføj enheden i Home Assistant: Indstillinger → Enheder og '
                'tjenester → Lommepenge → Tilføj enhed. Vælg navn og rolle, og '
                'tast den kode, Home Assistant viser.',
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
              TextField(
                controller: _codeController,
                decoration: const InputDecoration(
                  labelText: 'Kode fra Home Assistant',
                  hintText: 'fx K7M2QDXA',
                  border: OutlineInputBorder(),
                ),
                style: theme.textTheme.headlineSmall?.copyWith(letterSpacing: 4),
                textCapitalization: TextCapitalization.characters,
                autocorrect: false,
                onSubmitted: (_) => _connectWithCode(),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _addressController,
                decoration: InputDecoration(
                  labelText: 'Home Assistant-adresse',
                  hintText: 'fx 192.168.1.10:8123',
                  border: const OutlineInputBorder(),
                  helperText: _searching
                      ? 'Leder efter Home Assistant på netværket...'
                      : _foundName != null
                          ? 'Fundet: $_foundName'
                          : 'Ikke fundet automatisk - skriv adressen. Den står '
                              'på siden "Åbn siden med app-download" i Home '
                              'Assistant.',
                  helperMaxLines: 3,
                  suffixIcon: _searching
                      ? const Padding(
                          padding: EdgeInsets.all(14),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : IconButton(
                          icon: const Icon(Icons.refresh),
                          tooltip: 'Søg igen',
                          onPressed: _discover,
                        ),
                ),
                keyboardType: TextInputType.url,
                autocorrect: false,
              ),
              const SizedBox(height: 20),
              if (_busy)
                const Center(child: CircularProgressIndicator())
              else ...[
                FilledButton(
                  onPressed: _connectWithCode,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('Forbind'),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('Scan QR-kode i stedet'),
                  ),
                  onPressed: _scan,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
