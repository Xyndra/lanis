import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Persistent Linux-only configuration stored in ~/.config/lanis/config.json
/// (respecting XDG_CONFIG_HOME).
///
/// Writes are atomic (write-to-temp + rename). The file is watched for
/// external changes (e.g. a Nextcloud sync bringing in a change from another
/// device), which are broadcast on [changes].
///
/// Call [load()] once at startup **before** any database is opened.
class LinuxConfig {
  LinuxConfig._();

  static String? _dataDir;
  static StreamSubscription<FileSystemEvent>? _watchSub;
  static final StreamController<void> _changeCtrl =
      StreamController.broadcast();

  /// Fires whenever the config file changes externally.
  static Stream<void> get changes => _changeCtrl.stream;

  static String get _configDir {
    final xdg = Platform.environment['XDG_CONFIG_HOME'];
    final home = Platform.environment['HOME'] ?? '';
    return (xdg != null && xdg.isNotEmpty) ? '$xdg/lanis' : '$home/.config/lanis';
  }

  static String get configFilePath => '$_configDir/config.json';

  // ── public API ────────────────────────────────────────────────────────────

  /// The user-configured data directory, or null to use platform default.
  static String? get dataDir => _dataDir;

  /// Reads config from disk and begins watching for external edits.
  /// Safe to call on non-Linux platforms (no-op).
  static Future<void> load() async {
    if (!Platform.isLinux) return;
    await _reload();
    _startWatching();
  }

  /// Atomically persists [dir] as the data directory.
  /// Pass null to remove the override and fall back to the platform default.
  static Future<void> setDataDir(String? dir) async {
    if (!Platform.isLinux) return;
    _dataDir = dir;
    await _writeAtomic(dir == null ? {} : {'dataDir': dir});
  }

  // ── internals ─────────────────────────────────────────────────────────────

  static Future<void> _reload() async {
    final file = File(configFilePath);
    if (!file.existsSync()) {
      _dataDir = null;
      return;
    }
    try {
      final map = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      _dataDir = map['dataDir'] as String?;
    } catch (_) {
      _dataDir = null;
    }
  }

  /// Atomically writes [data] to the config file via a temp-file rename.
  static Future<void> _writeAtomic(Map<String, dynamic> data) async {
    final dir = Directory(_configDir);
    dir.createSync(recursive: true);
    final tmp = File('$_configDir/config.json.tmp');
    tmp.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(data),
    );
    tmp.renameSync(configFilePath);
  }

  static void _startWatching() {
    _watchSub?.cancel();
    final dir = Directory(_configDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    _watchSub = dir.watch(events: FileSystemEvent.all).listen((event) {
      if (event.path.endsWith('config.json') &&
          !event.path.endsWith('.tmp')) {
        _reload().then((_) => _changeCtrl.add(null));
      }
    }, onError: (_) {});
  }
}
