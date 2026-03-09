import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_phoenix/flutter_phoenix.dart';
import 'package:lanis/core/linux_config.dart';
import 'package:lanis/generated/l10n.dart';
import 'package:path_provider/path_provider.dart';

import '../settings_page_builder.dart';

class LinuxSettings extends SettingsColours {
  final bool showBackButton;
  const LinuxSettings({super.key, this.showBackButton = true});

  @override
  State<LinuxSettings> createState() => _LinuxSettingsState();
}

class _LinuxSettingsState extends SettingsColoursState<LinuxSettings> {
  String? _currentDir;
  String? _defaultDir;
  bool _isBusy = false;

  @override
  void initState() {
    super.initState();
    _currentDir = LinuxConfig.dataDir;
    getApplicationCacheDirectory().then((d) {
      if (mounted) setState(() => _defaultDir = d.path);
    });
  }

  String get _displayDir => _currentDir ?? _defaultDir ?? '…';

  Future<void> _pickDirectory() async {
    final picked = await FilePicker.platform.getDirectoryPath(
      dialogTitle: AppLocalizations.of(context).dataDirDialogTitle,
    );
    if (picked == null || !mounted) return;

    final confirmed = await _confirmChange(picked);
    if (!confirmed) return;

    setState(() => _isBusy = true);
    try {
      // Optionally copy existing DB files to new location.
      await _migrateDataFiles(picked);
      await LinuxConfig.setDataDir(picked);
      if (mounted) {
        setState(() {
          _currentDir = picked;
          _isBusy = false;
        });
        _showRestartPrompt();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isBusy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${AppLocalizations.of(context).error}: $e')),
        );
      }
    }
  }

  Future<void> _resetDirectory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(context).dataDirReset),
        content: Text(AppLocalizations.of(context).dataDirResetDesc),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppLocalizations.of(context).cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(AppLocalizations.of(context).confirm),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await LinuxConfig.setDataDir(null);
    setState(() => _currentDir = null);
    _showRestartPrompt();
  }

  Future<bool> _confirmChange(String newDir) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(context).dataDirChangeTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(AppLocalizations.of(context).dataDirChangeDesc),
            const SizedBox(height: 12),
            Text(
              newDir,
              style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 12),
            Text(AppLocalizations.of(context).dataDirMigrateHint),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppLocalizations.of(context).cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(AppLocalizations.of(context).confirm),
          ),
        ],
      ),
    );
    return result == true;
  }

  /// Copies .sqlite files from the old location to [newDir].
  Future<void> _migrateDataFiles(String newDir) async {
    final oldDir = _currentDir != null
        ? Directory(_currentDir!)
        : await getApplicationCacheDirectory();
    final dest = Directory(newDir);
    dest.createSync(recursive: true);
    for (final file
        in oldDir.listSync().whereType<File>().where((f) => f.path.endsWith('.sqlite'))) {
      final target = File('${dest.path}/${file.uri.pathSegments.last}');
      if (!target.existsSync()) {
        await file.copy(target.path);
      }
    }
  }

  void _showRestartPrompt() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(context).restartRequired),
        content: Text(AppLocalizations.of(context).dataDirRestartDesc),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLocalizations.of(context).later),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              Phoenix.rebirth(context);
            },
            child: Text(AppLocalizations.of(context).restart),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SettingsPage(
      backgroundColor: backgroundColor,
      showBackButton: widget.showBackButton,
      title: Text(AppLocalizations.of(context).linuxSettings),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Text(
            AppLocalizations.of(context).dataDirSectionTitle,
            style: Theme.of(context).textTheme.labelLarge!.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Text(
            AppLocalizations.of(context).dataDirDesc,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        const SizedBox(height: 8),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16.0),
          child: ListTile(
            leading: const Icon(Icons.folder_open),
            title: Text(AppLocalizations.of(context).dataDirectory),
            subtitle: Text(
              _displayDir,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
              ),
            ),
            trailing: _isBusy
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_currentDir != null)
                        IconButton(
                          icon: const Icon(Icons.restore),
                          tooltip: AppLocalizations.of(context).dataDirReset,
                          onPressed: _resetDirectory,
                        ),
                      IconButton(
                        icon: const Icon(Icons.edit),
                        tooltip: AppLocalizations.of(context).dataDirChange,
                        onPressed: _pickDirectory,
                      ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Text(
            AppLocalizations.of(context).configFileHint(
              LinuxConfig.configFilePath,
            ),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
