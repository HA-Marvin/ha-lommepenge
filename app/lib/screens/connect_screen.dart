import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../providers/app_state.dart';
import 'language_screen.dart';
import 'qr_scan_screen.dart';

/// The screen on a new device after the language: connect to Home Assistant.
///
/// The device is added in Home Assistant (Lommepenge → Add device), where the
/// role is chosen, and HA shows a code. The app finds Home Assistant on the
/// network by itself, so normally only the code has to be typed. If the
/// device has a camera, the QR code can be scanned instead (see
/// `AppState.connectWithCode`/`connectWithLink`).
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
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lommepenge'),
        actions: const [LanguageButton()],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Icon(Icons.home_outlined, size: 64, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text(
                l10n.connectTitle,
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(l10n.connectInstructions, textAlign: TextAlign.center),
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
                decoration: InputDecoration(
                  labelText: l10n.codeLabel,
                  hintText: l10n.codeHint,
                  border: const OutlineInputBorder(),
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
                  labelText: l10n.addressLabel,
                  hintText: l10n.addressHint,
                  border: const OutlineInputBorder(),
                  helperText: _searching
                      ? l10n.searchingForHa
                      : _foundName != null
                          ? l10n.foundHa(_foundName!)
                          : l10n.haNotFound,
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
                          tooltip: l10n.searchAgain,
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
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(l10n.connectButton),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.qr_code_scanner),
                  label: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(l10n.scanQrInstead),
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
