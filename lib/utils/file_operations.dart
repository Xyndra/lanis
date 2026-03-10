import 'dart:io';

import 'package:flutter/material.dart';
import 'package:lanis/generated/l10n.dart';
import 'package:open_file/open_file.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:xdg_directories/xdg_directories.dart' as xdg;

import '../core/sph/sph.dart';
import 'file_icons.dart';
import 'native_file_opener.dart';

class FileInfo {
  String? name;

  /// The size + the unit. Often enclosed with parentheses.
  String? size;

  /// Remote file URL - null if this is a local file
  Uri? url;

  /// Local file path - null if this is a remote file
  String? localPath;

  /// Gets the file extension from either name or local path
  String get extension {
    if (name != null && name!.contains('.')) {
      return name!.split('.').last;
    } else if (localPath != null && localPath!.contains('.')) {
      return localPath!.split('/').last.split('.').last;
    }
    return "";
  }

  /// Create a file info for a remote file
  FileInfo({this.name, this.size, this.url}) : localPath = null;

  /// Create a file info for a local file
  FileInfo.local({String? name, String? size, required String filePath})
    : name = name ?? filePath.split('/').last,
      size = size,
      localPath = filePath,
      url = null;

  /// Returns true if this represents a local file
  bool get isLocal => localPath != null;
}

void showFileModal(BuildContext context, FileInfo file) {
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (context) {
      return SafeArea(
        child: SizedBox(
          width: double.infinity,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const SizedBox(width: 22.0),
                    Icon(getIconByFileExtension(file.extension)),
                    const SizedBox(width: 10.0),
                    Expanded(
                      child: Text(
                        file.name ?? AppLocalizations.of(context).unknownFile,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      file.size ?? "",
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    const SizedBox(width: 22.0),
                  ],
                ),
                SizedBox(height: 8),
                Divider(),
                MenuItemButton(
                  onPressed: () => {launchFile(context, file, () {})},
                  child: Row(
                    children: [
                      Padding(padding: EdgeInsets.only(left: 10.0)),
                      Icon(Icons.open_in_new),
                      Padding(padding: EdgeInsets.only(right: 8.0)),
                      Text(AppLocalizations.of(context).openFile),
                    ],
                  ),
                ),
                if (!Platform.isIOS && !file.isLocal)
                  (MenuItemButton(
                    onPressed: () => {saveFile(context, file, () {})},
                    child: Row(
                      children: [
                        Padding(padding: EdgeInsets.only(left: 10.0)),
                        Icon(Icons.save_alt_rounded),
                        Padding(padding: EdgeInsets.only(right: 8.0)),
                        Text(AppLocalizations.of(context).saveFile),
                      ],
                    ),
                  )),
                if (!Platform.isLinux)
                  (MenuItemButton(
                    onPressed: () => {shareFile(context, file, () {})},
                    child: Row(
                      children: [
                        Padding(padding: EdgeInsets.only(left: 10.0)),
                        Icon(Icons.share_rounded),
                        Padding(padding: EdgeInsets.only(right: 8.0)),
                        Text(AppLocalizations.of(context).shareFile),
                      ],
                    ),
                  )),
              ],
            ),
          ),
        ),
      );
    },
  );
}

void launchFile(BuildContext context, FileInfo file, Function callback) {
  final String filename = file.name ?? AppLocalizations.of(context).unknownFile;

  if (file.isLocal) {
    _openFilePath(context, file.localPath!, callback);
    return;
  }

  // For remote files, download then open
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) => downloadDialog(context, file.size),
  );

  sph!.storage.downloadFile(file.url.toString(), filename).then((
    filepath,
  ) async {
    if (context.mounted) Navigator.of(context).pop();

    if (filepath.isEmpty && context.mounted) {
      showDialog(context: context, builder: (context) => errorDialog(context));
    } else {
      _openFilePath(context, filepath, callback);
    }
  });
}

/// In Flatpak, the sandbox's /tmp is a private namespace the portal cannot
/// reach.  Copy the file to a temp dir inside the XDG download dir (shared
/// via --filesystem=xdg-download) so g_app_info_launch_default_for_uri_async
/// can open it.  Outside Flatpak the path is returned unchanged.
///
/// Uses browser-style versioning: if a file with the same name already exists
/// but has different content, a numbered suffix is appended (e.g. "doc (1).pdf").
/// An existing file with identical content is reused without copying.
Future<String> _portalAccessiblePath(String path) async {
  if (Platform.environment['FLATPAK_ID'] == null) return path;
  try {
    final downloadsDir =
        xdg.getUserDirectory('DOWNLOAD') ??
        Directory(p.join(Platform.environment['HOME'] ?? '', 'Downloads'));
    final tmpDir = Directory(p.join(downloadsDir.path, '.lanis-tmp'));
    tmpDir.createSync(recursive: true);

    final source = File(path);
    final sourceBytes = await source.readAsBytes();

    final basename = p.basenameWithoutExtension(path);
    final ext = p.extension(path); // includes leading dot

    // Browser-style: find a slot where either the file doesn't exist yet, or
    // the existing file already has the same content (so we can reuse it).
    for (int i = 0; ; i++) {
      final name = i == 0 ? '$basename$ext' : '$basename ($i)$ext';
      final candidate = File(p.join(tmpDir.path, name));
      if (!candidate.existsSync()) {
        await source.copy(candidate.path);
        return candidate.path;
      }
      final existingBytes = await candidate.readAsBytes();
      if (_bytesEqual(existingBytes, sourceBytes)) {
        return candidate.path; // same content → reuse
      }
    }
  } catch (e) {
    return path; // fall back to original path
  }
}

bool _bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Opens a local file using the platform's default application.
/// In Flatpak, copies to a subdir of XDG_DOWNLOAD_DIR (shared between
/// sandbox and host) so the portal can reach the file.
void _openFilePath(BuildContext context, String filepath, Function callback) {
  if (Platform.isLinux) {
    _portalAccessiblePath(filepath).then((sharedPath) {
      openFileNative(sharedPath).then((success) {
        if (success) {
          callback();
        } else if (context.mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text("${AppLocalizations.of(ctx).error}!"),
              icon: const Icon(Icons.error),
              content: Text(AppLocalizations.of(ctx).noAppToOpen),
              actions: [
                FilledButton(
                  child: const Text('Ok'),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ],
            ),
          );
        }
      });
    });
    return;
  }
  OpenFile.open(filepath).then((result) {
    if (result.message.contains("No APP found to open this file") &&
        context.mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text("${AppLocalizations.of(context).error}!"),
          icon: const Icon(Icons.error),
          content: Text(AppLocalizations.of(context).noAppToOpen),
          actions: [
            FilledButton(
              child: const Text('Ok'),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      );
    }
    callback();
  });
}

/// Saves a file to ~/Downloads on Linux using XDG directories.
Future<void> _saveFileLinux(
  BuildContext context,
  FileInfo file,
  String filename,
  Function callback,
) async {
  // Resolve the XDG download directory (falls back to ~/Downloads).
  final downloadsDir =
      xdg.getUserDirectory('DOWNLOAD') ??
      Directory(p.join(Platform.environment['HOME'] ?? '', 'Downloads'));

  Future<void> copyToDownloads(String sourcePath) async {
    if (!downloadsDir.existsSync()) {
      downloadsDir.createSync(recursive: true);
    }
    final destPath = p.join(downloadsDir.path, filename);
    await File(sourcePath).copy(destPath);
  }

  if (file.isLocal) {
    await copyToDownloads(file.localPath!);
    callback();
    return;
  }

  if (!context.mounted) return;
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => downloadDialog(ctx, file.size),
  );

  final filepath = await sph!.storage.downloadFile(
    file.url.toString(),
    filename,
  );

  if (context.mounted) Navigator.of(context).pop();

  if (filepath.isEmpty) {
    if (context.mounted) {
      showDialog(context: context, builder: (ctx) => errorDialog(ctx));
    }
    return;
  }

  await copyToDownloads(filepath);

  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${AppLocalizations.of(context).saveFile}: ${downloadsDir.path}/$filename',
        ),
      ),
    );
  }

  callback();
}

void saveFile(BuildContext context, FileInfo file, Function callback) {
  final String filename = file.name ?? AppLocalizations.of(context).unknownFile;

  if (Platform.isLinux) {
    _saveFileLinux(context, file, filename, callback);
    return;
  }

  const platform = MethodChannel('io.github.lanis-mobile/storage');

  if (file.isLocal) {
    // For local files, just save directly
    platform
        .invokeMethod('saveFile', {
          'fileName': filename,
          'mimeType': lookupMimeType(file.localPath!) ?? "*/*",
          'filePath': file.localPath,
        })
        .then((_) {
          callback();
        });
    return;
  }

  // For remote files, download then save
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) => downloadDialog(context, file.size),
  );

  sph!.storage.downloadFile(file.url.toString(), filename).then((
    filepath,
  ) async {
    if (context.mounted) Navigator.of(context).pop();

    if (filepath == "" && context.mounted) {
      showDialog(context: context, builder: (context) => errorDialog(context));
    } else {
      await platform.invokeMethod('saveFile', {
        'fileName': filename,
        'mimeType': lookupMimeType(filepath) ?? "*/*",
        'filePath': filepath,
      });
      callback();
    }
  });
}

void shareFile(BuildContext context, FileInfo file, Function callback) {
  final String filename = file.name ?? AppLocalizations.of(context).unknownFile;

  if (file.isLocal) {
    // For local files, share directly
    Share.shareXFiles([XFile(file.localPath!)]).then((_) {
      callback();
    });
    return;
  }

  // For remote files, download then share
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) => downloadDialog(context, file.size),
  );

  sph!.storage.downloadFile(file.url.toString(), filename).then((
    filepath,
  ) async {
    if (context.mounted) Navigator.of(context).pop();

    if (filepath == "" && context.mounted) {
      showDialog(context: context, builder: (context) => errorDialog(context));
    } else {
      await Share.shareXFiles([XFile(filepath)]);
      callback();
    }
  });
}

AlertDialog errorDialog(BuildContext context) => AlertDialog(
  title: Text("${AppLocalizations.of(context).error}!"),
  icon: const Icon(Icons.error),
  content: Text(AppLocalizations.of(context).reportError),
  actions: [
    TextButton(
      onPressed: () {
        launchUrl(
          Uri.parse("https://github.com/alessioC42/lanis-mobile/issues"),
        );
      },
      child: const Text("GitHub"),
    ),
    FilledButton(
      child: const Text('Ok'),
      onPressed: () {
        Navigator.of(context).pop();
      },
    ),
  ],
);

AlertDialog downloadDialog(BuildContext context, String? fileSize) =>
    AlertDialog(
      title: Text("Download... ${fileSize ?? ""}"),
      content: const Center(
        heightFactor: 1.1,
        child: CircularProgressIndicator(),
      ),
    );

Future<File> moveFile(String originPath, String targetPath) async {
  final originFile = File.fromUri(Uri.file(originPath));
  try {
    return await originFile.rename(targetPath);
  } on FileSystemException catch (_) {
    final newFile = await originFile.copy(targetPath);
    await originFile.delete();
    return newFile;
  }
}
