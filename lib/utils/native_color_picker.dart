import 'dart:io';

import 'package:flutter/services.dart';

/// Calls the native GTK colour chooser dialog on Linux.
/// Returns the picked [Color], or null if the user cancelled.
/// Falls back to null on non-Linux platforms (caller should show its own UI).
Future<Color?> pickColorNative(Color initial) async {
  if (!Platform.isLinux) return null;
  const channel = MethodChannel('io.github.lanis-mobile/color_picker');
  try {
    final hex = await channel.invokeMethod<String?>('pick', {
      'initial': _colorToHex(initial),
    });
    if (hex == null) return null;
    return _hexToColor(hex);
  } on PlatformException {
    return null;
  }
}

String _colorToHex(Color color) {
  return '${(color.r * 255).round().toRadixString(16).padLeft(2, '0')}'
          '${(color.g * 255).round().toRadixString(16).padLeft(2, '0')}'
          '${(color.b * 255).round().toRadixString(16).padLeft(2, '0')}'
      .toUpperCase();
}

Color _hexToColor(String hex) {
  final h = hex.replaceAll('#', '');
  return Color(int.parse('FF$h', radix: 16));
}
