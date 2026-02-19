import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AndroidOverlay {
  static const _appChannel = MethodChannel('app_channel');

  static void _log(String message) {
    if (kDebugMode) {
      debugPrint(message);
    }
  }

  /// Requests the system permission to draw over other apps (opens settings).
  static Future<bool> requestPermission() async {
    if (!Platform.isAndroid) return false;
    try {
      _log('Requesting overlay permission...');
      
      // Check if permission is already granted
      final canDraw = await _appChannel.invokeMethod<bool>('canDrawOverlays') ?? false;
      _log('canDrawOverlays check: $canDraw');
      
      if (canDraw) {
        _log('Overlay permission already granted');
        return true;
      }
      
      // Request permission via settings
      final result = await _appChannel.invokeMethod<bool>('requestOverlayPermission') ?? false;
      _log('requestOverlayPermission result: $result');
      
      return result;
    } catch (e) {
      _log('Error requesting overlay permission: $e');
      return false;
    }
  }

  /// Shows the overlay using flutter_overlay_window.
  static Future<bool> showOverlay({bool minimizeApp = true}) async {
    if (!Platform.isAndroid) return false;
    try {
        _log('[OVERLAY] Showing overlay...');

          final dpr = PlatformDispatcher.instance.views.isNotEmpty
            ? PlatformDispatcher.instance.views.first.devicePixelRatio
            : 1.0;
        final prefs = await SharedPreferences.getInstance();
        await prefs.reload();
          final fontSize = prefs.getDouble('overlayFontSize') ?? 22.0;
          final showMilliseconds = prefs.getBool('showMilliseconds') ?? true;
          final showHours = prefs.getBool('showHours') ?? true;
          final scale = (fontSize / 22.0).clamp(0.7, 2.0);
          final paddingH = 0.1 * scale;
          final paddingV = 0.8 * scale;
          final charCount = (showHours ? 8 : 5) + (showMilliseconds ? 3 : 0);
          final textWidth = fontSize * 0.6 * charCount;
          final minWidth = 90 * scale;
          final width = (textWidth + (paddingH * 2));
          final baseHeight = (fontSize * 1.2) + (paddingV * 2);
          final expandedHeight = baseHeight + (44 * scale);
          final widthPx = ((width < minWidth ? minWidth : width) * dpr).round();
          final heightPx = (expandedHeight * dpr).round();
        final savedX = prefs.getDouble('overlay_pos_x');
        final savedY = prefs.getDouble('overlay_pos_y');
        var startX = savedX ?? 0.0;
        var startY = savedY ?? (60 * scale);
        final screenW = prefs.getDouble('overlay_screen_w');
        final screenH = prefs.getDouble('overlay_screen_h');
        if (screenW != null && screenH != null) {
          final overlayWidth = width < minWidth ? minWidth : width;
          final maxX = screenW - overlayWidth;
          final maxY = screenH - expandedHeight;
          startX = startX.clamp(0.0, maxX < 0 ? 0.0 : maxX);
          startY = startY.clamp(0.0, maxY < 0 ? 0.0 : maxY);
        }
      
      await FlutterOverlayWindow.showOverlay(
        height: heightPx,
        width: widthPx,
        alignment: OverlayAlignment.topLeft,
        startPosition: OverlayPosition(startX, startY),
        flag: OverlayFlag.defaultFlag,
        enableDrag: true,
        overlayTitle: '',
      );
      
      await _waitForOverlayActive();
      await FlutterOverlayWindow.moveOverlay(OverlayPosition(startX, startY));
      await Future.delayed(const Duration(milliseconds: 600));
      
      if (minimizeApp) {
        _log('[OVERLAY] Minimizing main app...');

        try {
          await _appChannel.invokeMethod('moveToBackground');
          _log('[OVERLAY] App minimized');
        } catch (e) {
          _log('[OVERLAY] Error minimizing: $e');
        }
      }
      
      _log('[OVERLAY] Show overlay completed');
      return true;
    } catch (e) {
      _log('[OVERLAY] Error showing overlay: $e');
      return false;
    }
  }

  static Future<void> _waitForOverlayActive() async {
    const maxWaitMs = 6000;
    const stepMs = 250;
    var waited = 0;

    while (waited < maxWaitMs) {
      try {
        final isActive = await FlutterOverlayWindow.isActive();
        if (isActive) {
          _log('[OVERLAY] Overlay is active');
          return;
        }
      } catch (e) {
        _log('[OVERLAY] isActive check failed: $e');
      }

      await Future.delayed(const Duration(milliseconds: stepMs));
      waited += stepMs;
    }

    _log('[OVERLAY] Overlay did not become active before timeout');
  }

  /// Hides the overlay.
  static Future<bool> hideOverlay() async {
    if (!Platform.isAndroid) return false;
    try {
      await _persistOverlayPosition();
      await FlutterOverlayWindow.closeOverlay();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Checks if the overlay is currently active.
  static Future<bool> isOverlayActive() async {
    if (!Platform.isAndroid) return false;
    try {
      return await FlutterOverlayWindow.isActive();
    } catch (e) {
      return false;
    }
  }

  static Future<void> _persistOverlayPosition() async {
    try {
      final position = await FlutterOverlayWindow.getOverlayPosition();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('overlay_pos_x', position.x.toDouble());
      await prefs.setDouble('overlay_pos_y', position.y.toDouble());
    } catch (_) {
      // Best effort - if position cannot be persisted, continue
    }
  }

  /// Opens the system battery optimization settings for the app.
  static Future<void> openBatteryOptimizationSettings() async {
    if (!Platform.isAndroid) return;
    try {
      await _appChannel.invokeMethod('openBatteryOptimizationSettings');
    } catch (e) {
      // ignore - best effort
    }
  }

  static Future<void> resetOverlayPosition() async {
    if (!Platform.isAndroid) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final fontSize = prefs.getDouble('overlayFontSize') ?? 22.0;
      final scale = (fontSize / 22.0).clamp(0.7, 2.0);
      final x = 0.0;
      final y = 60 * scale;
      await prefs.setDouble('overlay_pos_x', x);
      await prefs.setDouble('overlay_pos_y', y);
      try {
        final isActive = await FlutterOverlayWindow.isActive();
        if (isActive) {
          await FlutterOverlayWindow.moveOverlay(OverlayPosition(x, y));
        }
      } catch (_) {}
    } catch (_) {}
  }
}
