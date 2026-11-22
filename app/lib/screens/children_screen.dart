import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../models/child.dart';
import '../providers/app_state.dart';

/// Parent tab to manage the family's children: create, rename and delete.
/// Errors from `TaskRepository` are shown in a SnackBar.
///
/// Deliberately has no [AppBar] of its own - used embedded as tab content in
/// [ParentHomeScreen], the same pattern as the other tabs there.
class ChildrenScreen extends StatelessWidget {
  const ChildrenScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final children = appState.children;
    final l10n = context.l10n;

    return Scaffold(
      body: children.isEmpty
          ? Center(child: Text(l10n.noChildrenYet))
          : ListView.builder(
              itemCount: children.length,
              itemBuilder: (context, index) {
                final child = children[index];
                return ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(child.name),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: l10n.rename,
                        onPressed: () => _renameDialog(context, child),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: l10n.delete,
                        onPressed: () => _confirmDelete(context, child),
                      ),
                    ],
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addDialog(context),
        tooltip: l10n.addChild,
        child: const Icon(Icons.add),
      ),
    );
  }

  /// Asks for a name. Returns the name, or `null` if cancelled.
  Future<String?> _nameDialog(
    BuildContext context, {
    required String title,
    required String confirm,
    String initial = '',
  }) async {
    final controller = TextEditingController(text: initial);
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: ctx.l10n.name,
              border: const OutlineInputBorder(),
            ),
            validator: (value) => (value == null || value.trim().isEmpty)
                ? ctx.l10n.nameRequired
                : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(ctx.l10n.cancel),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.of(ctx).pop(true);
              }
            },
            child: Text(confirm),
          ),
        ],
      ),
    );
    return result == true ? controller.text.trim() : null;
  }

  Future<void> _run(BuildContext context, Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _addDialog(BuildContext context) async {
    final l10n = context.l10n;
    final name =
        await _nameDialog(context, title: l10n.addChild, confirm: l10n.add);
    if (name != null && context.mounted) {
      await _run(context, () => context.read<AppState>().addChild(name));
    }
  }

  Future<void> _renameDialog(BuildContext context, Child child) async {
    final l10n = context.l10n;
    final name = await _nameDialog(
      context,
      title: l10n.renameChild,
      confirm: l10n.save,
      initial: child.name,
    );
    if (name != null && context.mounted) {
      await _run(
        context,
        () => context.read<AppState>().renameChild(child.id, name),
      );
    }
  }

  Future<void> _confirmDelete(BuildContext context, Child child) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.deleteChild),
        content: Text(ctx.l10n.confirmDelete(child.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(ctx.l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(ctx.l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await _run(context, () => context.read<AppState>().deleteChild(child.id));
    }
  }
}
