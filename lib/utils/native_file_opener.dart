import 'dart:io';

import 'package:flutter/services.dart';

const _channel = MethodChannel('io.github.lanis-mobile/file_opener');

/// Opens a file at [path] using the platform-native default application.
/// On Linux this goes through the GTK / GIO portal, which works correctly
/// inside Flatpak sandboxes.  Returns `true` on success.
Future<bool> openFileNative(String path) async {
  if (!Platform.isLinux) return false;
  try {
    final result =
        await _channel.invokeMethod<bool>('open', {'path': path});
    return result ?? false;
  } on PlatformException {
    return false;
  }
}
