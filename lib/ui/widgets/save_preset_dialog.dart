import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/preset.dart';
import '../../providers/eq_provider.dart';
import '../../theme/app_theme.dart';

/// Full "Save Preset" flow (button and Ctrl/⌘+S): ask for a name, save,
/// confirm with a snackbar.
Future<void> saveCurrentAsPreset(BuildContext context, WidgetRef ref) async {
  final eq = ref.read(eqProvider);
  final userNames = {for (final p in eq.userPresets) p.name};

  // Pre-fill with the current name if it's one of the user's own presets.
  final name = await showSavePresetDialog(
    context,
    existingNames: userNames,
    initialName: userNames.contains(eq.presetName) ? eq.presetName : '',
  );
  if (name == null || Preset.isReservedName(name)) return;

  await ref.read(eqProvider.notifier).savePreset(name);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('Preset "$name" saved'),
      duration: const Duration(seconds: 2),
    ),
  );
}

/// Asks for a preset name. Returns the trimmed name, or null if cancelled.
Future<String?> showSavePresetDialog(
  BuildContext context, {
  required Set<String> existingNames,
  String initialName = '',
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _SavePresetDialog(
      existingNames: existingNames,
      initialName: initialName,
    ),
  );
}

class _SavePresetDialog extends StatefulWidget {
  const _SavePresetDialog({required this.existingNames, required this.initialName});

  final Set<String> existingNames;
  final String initialName;

  @override
  State<_SavePresetDialog> createState() => _SavePresetDialogState();
}

class _SavePresetDialogState extends State<_SavePresetDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialName);
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      // Clear the error and refresh the "overwrite" hint while typing.
      setState(() => _error = null);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Please enter a name');
    } else if (Preset.isReservedName(name)) {
      setState(() => _error = '"$name" is a built-in name');
    } else {
      Navigator.of(context).pop(name);
    }
  }

  @override
  Widget build(BuildContext context) {
    final overwriting = widget.existingNames.contains(_controller.text.trim());

    return AlertDialog(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppColors.border),
      ),
      title: const Text('Save preset', style: TextStyle(fontSize: 18)),
      content: SizedBox(
        width: 340,
        child: TextField(
          controller: _controller,
          autofocus: true,
          maxLength: 24,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            hintText: 'e.g. Late Night',
            errorText: _error,
            helperText: overwriting ? 'This will overwrite your existing preset.' : null,
            helperStyle: const TextStyle(color: AppColors.accent),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}
