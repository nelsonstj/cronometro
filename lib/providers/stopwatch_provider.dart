import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/android_overlay.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LapEntry {
  final int lapNumber;
  final int startTime; // epoch millis
  final int endTime; // epoch millis
  final int duration; // millis
  final String customLabel;

  LapEntry({
    required this.lapNumber,
    required this.startTime,
    required this.endTime,
    required this.duration,
    this.customLabel = '',
  });

  Map<String, dynamic> toJson() => {
        'lapNumber': lapNumber,
        'startTime': startTime,
        'endTime': endTime,
        'duration': duration,
        'customLabel': customLabel,
      };

  factory LapEntry.fromJson(Map<String, dynamic> json) => LapEntry(
        lapNumber: json['lapNumber'],
        startTime: json['startTime'],
        endTime: json['endTime'],
        duration: json['duration'],
        customLabel: json['customLabel']?.toString() ?? '',
      );

  LapEntry copyWith({String? customLabel}) {
    return LapEntry(
      lapNumber: lapNumber,
      startTime: startTime,
      endTime: endTime,
      duration: duration,
      customLabel: customLabel ?? this.customLabel,
    );
  }
}

class Session {
  final int sessionStart; // epoch
  int sessionEnd; // epoch
  final List<LapEntry> laps;
  final bool isCountdown;
  final int countdownInitialMs;

  Session({
    required this.sessionStart,
    required this.sessionEnd,
    required this.laps,
    required this.isCountdown,
    required this.countdownInitialMs,
  });

  Map<String, dynamic> toJson() => {
        'sessionStart': sessionStart,
        'sessionEnd': sessionEnd,
        'laps': laps.map((e) => e.toJson()).toList(),
      'isCountdown': isCountdown,
      'countdownInitialMs': countdownInitialMs,
      };

  factory Session.fromJson(Map<String, dynamic> json) => Session(
        sessionStart: json['sessionStart'],
        sessionEnd: json['sessionEnd'],
        laps: (json['laps'] as List<dynamic>).map((e) => LapEntry.fromJson(Map<String, dynamic>.from(e))).toList(),
      isCountdown: json['isCountdown'] ?? false,
      countdownInitialMs: json['countdownInitialMs'] ?? 0,
      );
}

class StopwatchProvider extends ChangeNotifier {
  final SharedPreferences _prefs;

  // Estado do cronômetro
  int _accumulatedMilliseconds = 0;
  int? _lastStartTimestamp;
  bool _isRunning = false;
  final List<int> _laps = []; // keep for compatibility

  // Sessions persisted
  final List<Session> _sessions = [];
  Session? _currentSession;

  // Configurações
  bool _showLapTime = true;
  bool _showOverlay = false;
  ThemeMode _themeMode = ThemeMode.system;
  bool _showMilliseconds = true;
  bool _showHours = true;
  Color _overlayStoppedBgColor = const Color(0xD9000000);
  Color _overlayRunningBgColor = const Color(0xD9000000);
  Color _overlayTextColor = const Color(0xFFFFFFFF);
  double _overlayFontSize = 22.0;
  bool _isCountdownMode = false;
  int _countdownTotalMs = 10 * 60 * 1000;
  bool _vibrateOnCountdownFinish = true;
  bool _countdownFinishedNotified = false;
  String _lapLabel = 'Volta';
  Size? _overlayScreenSize;

  // Overlay event polling
  final Set<String> _processedOverlayIds = {};
  Timer? _overlayPoller;
  Timer? _overlayStateWriter;
  int _lastOverlayPersistMs = 0;
  int _lastOverlayStateTsFromOverlay = 0;

  // Getters
  int get elapsedMilliseconds {
    if (_isRunning && _lastStartTimestamp != null) {
      final now = DateTime.now().millisecondsSinceEpoch;
      return _accumulatedMilliseconds + (now - _lastStartTimestamp!);
    }
    return _accumulatedMilliseconds;
  }
  int get displayMilliseconds {
    if (_isCountdownMode) {
      final remaining = _countdownTotalMs - elapsedMilliseconds;
      return remaining > 0 ? remaining : 0;
    }
    return elapsedMilliseconds;
  }
  bool get isRunning => _isRunning;
  List<int> get laps => _laps;
  bool get showLapTime => _showLapTime;
  bool get showOverlay => _showOverlay;
  ThemeMode get themeMode => _themeMode;
  bool get showMilliseconds => _showMilliseconds;
  bool get showHours => _showHours;
  Color get overlayStoppedBgColor => _overlayStoppedBgColor;
  Color get overlayRunningBgColor => _overlayRunningBgColor;
  Color get overlayTextColor => _overlayTextColor;
  double get overlayFontSize => _overlayFontSize;
  bool get isCountdownMode => _isCountdownMode;
  int get countdownTotalMilliseconds => _countdownTotalMs;
  bool get vibrateOnCountdownFinish => _vibrateOnCountdownFinish;
  String get lapLabel => _lapLabel;
  List<Session> get sessions => _sessions;
  Session? get currentSession => _currentSession;

  StopwatchProvider(this._prefs) {
    _loadPreferences();
  }

  void _loadPreferences() {
    _showLapTime = _prefs.getBool('showLapTime') ?? true;
    _showMilliseconds = _prefs.getBool('showMilliseconds') ?? true;
    _showHours = _prefs.getBool('showHours') ?? true;
    _overlayStoppedBgColor = Color(_prefs.getInt('overlayStoppedBgColor') ?? 0xD9000000);
    _overlayRunningBgColor = Color(_prefs.getInt('overlayRunningBgColor') ?? 0xD9000000);
    _overlayTextColor = Color(_prefs.getInt('overlayTextColor') ?? 0xFFFFFFFF);
    _overlayFontSize = _prefs.getDouble('overlayFontSize') ?? 22.0;
    _isCountdownMode = _prefs.getBool('countdownMode') ?? false;
    _countdownTotalMs = _prefs.getInt('countdownTotalMs') ?? 10 * 60 * 1000;
    _vibrateOnCountdownFinish = _prefs.getBool('vibrateOnCountdownFinish') ?? true;
    _lapLabel = _prefs.getString('lapLabel') ?? 'Volta';
    final themeModeRaw = _prefs.getString('themeMode') ?? 'system';
    _themeMode = _parseThemeMode(themeModeRaw);
    final raw = _prefs.getString('sessions');
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        _sessions.clear();
        for (final item in list) {
          _sessions.add(Session.fromJson(Map<String, dynamic>.from(item)));
        }
      } catch (_) {}
    }
    final currentRaw = _prefs.getString('currentSession');
    if (currentRaw != null && currentRaw.isNotEmpty) {
      try {
        _currentSession = Session.fromJson(Map<String, dynamic>.from(jsonDecode(currentRaw)));
      } catch (_) {}
    }

    // Ensure the app starts with a zeroed display.
    _isRunning = false;
    _lastStartTimestamp = null;
    _accumulatedMilliseconds = 0;
    _laps.clear();
    _currentSession = null;
    _countdownFinishedNotified = false;
    _saveCurrentSession();
    _persistOverlayState(source: 'main');
  }

  void toggleShowLapTime() {
    _showLapTime = !_showLapTime;
    _prefs.setBool('showLapTime', _showLapTime);
    notifyListeners();
  }

  void setShowMilliseconds(bool value) {
    if (_showMilliseconds == value) return;
    _showMilliseconds = value;
    _prefs.setBool('showMilliseconds', _showMilliseconds);
    _persistOverlayState(source: 'main');
    notifyListeners();
  }

  void setShowHours(bool value) {
    if (_showHours == value) return;
    _showHours = value;
    _prefs.setBool('showHours', _showHours);
    _persistOverlayState(source: 'main');
    notifyListeners();
  }

  void setCountdownMode(bool value) {
    if (_isCountdownMode == value) return;
    _isCountdownMode = value;
    _countdownFinishedNotified = false;
    if (_isCountdownMode) {
      _isRunning = false;
      _lastStartTimestamp = null;
      _accumulatedMilliseconds = 0;
      _laps.clear();
    } else {
      _isRunning = false;
      _lastStartTimestamp = null;
      _accumulatedMilliseconds = 0;
      _laps.clear();
    }
    _prefs.setBool('countdownMode', _isCountdownMode);
    _persistOverlayState(source: 'main');
    notifyListeners();
  }

  void setCountdownTotal(Duration duration) {
    final nextMs = duration.inMilliseconds.clamp(0, 99 * 60 * 60 * 1000);
    if (_countdownTotalMs == nextMs) return;
    _countdownTotalMs = nextMs;
    if (_accumulatedMilliseconds > _countdownTotalMs) {
      _accumulatedMilliseconds = _countdownTotalMs;
      _lastStartTimestamp = null;
      _isRunning = false;
    }
    _countdownFinishedNotified = false;
    _prefs.setInt('countdownTotalMs', _countdownTotalMs);
    _persistOverlayState(source: 'main');
    notifyListeners();
  }

  void setVibrateOnCountdownFinish(bool value) {
    if (_vibrateOnCountdownFinish == value) return;
    _vibrateOnCountdownFinish = value;
    _prefs.setBool('vibrateOnCountdownFinish', _vibrateOnCountdownFinish);
    notifyListeners();
  }

  void setLapLabel(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || _lapLabel == trimmed) return;
    _lapLabel = trimmed;
    _prefs.setString('lapLabel', _lapLabel);
    notifyListeners();
  }

  void setOverlayScreenSize(Size size) {
    if (_overlayScreenSize == size) return;
    _overlayScreenSize = size;
    _prefs.setDouble('overlay_screen_w', size.width);
    _prefs.setDouble('overlay_screen_h', size.height);
  }

  Future<void> setOverlayStoppedBgColor(Color color) async {
    if (_overlayStoppedBgColor.toARGB32() == color.toARGB32()) return;
    _overlayStoppedBgColor = color;
    await _prefs.setInt('overlayStoppedBgColor', color.toARGB32());
    await _persistOverlayState(source: 'main');
    notifyListeners();
  }

  Future<void> setOverlayRunningBgColor(Color color) async {
    if (_overlayRunningBgColor.toARGB32() == color.toARGB32()) return;
    _overlayRunningBgColor = color;
    await _prefs.setInt('overlayRunningBgColor', color.toARGB32());
    await _persistOverlayState(source: 'main');
    notifyListeners();
  }

  Future<void> setOverlayTextColor(Color color) async {
    if (_overlayTextColor.toARGB32() == color.toARGB32()) return;
    _overlayTextColor = color;
    await _prefs.setInt('overlayTextColor', color.toARGB32());
    await _persistOverlayState(source: 'main');
    notifyListeners();
  }

  Future<void> setOverlayFontSize(double size) async {
    if (_overlayFontSize == size) return;
    _overlayFontSize = size;
    await _prefs.setDouble('overlayFontSize', size);
    await _persistOverlayState(source: 'main');
    if (_showOverlay) {
      await AndroidOverlay.hideOverlay();
      await Future.delayed(const Duration(milliseconds: 200));
      final shown = await AndroidOverlay.showOverlay(minimizeApp: false);
      if (shown) {
        startOverlayEventPoller();
        _startOverlayStateWriter();
      }
    }
    notifyListeners();
  }

  void setThemeMode(ThemeMode mode) {
    if (_themeMode == mode) return;
    _themeMode = mode;
    _prefs.setString('themeMode', _themeModeToString(mode));
    notifyListeners();
  }

  ThemeMode _parseThemeMode(String raw) {
    switch (raw) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  String _themeModeToString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }

  Future<void> toggleOverlay() async {
    if (_showOverlay) {
      final isActive = await AndroidOverlay.isOverlayActive();
      if (!isActive) {
        _showOverlay = false;
      }
    }

    _showOverlay = !_showOverlay;
    notifyListeners();

    if (_showOverlay) {
      await _persistOverlayState(source: 'main');
      // Give the overlay engine time to read prefs before it starts.
      await Future.delayed(const Duration(milliseconds: 300));
      final granted = await AndroidOverlay.requestPermission();
      if (!granted) {
        _showOverlay = false;
        notifyListeners();
        return;
      }

      final shown = await AndroidOverlay.showOverlay();
      if (shown) {
        // Start polling for overlay events
        startOverlayEventPoller();
        _startOverlayStateWriter();
      } else {
        _showOverlay = false;
        notifyListeners();
      }
    } else {
      await AndroidOverlay.hideOverlay();
      _overlayPoller?.cancel();
      _overlayStateWriter?.cancel();
    }
  }

  Future<void> shutdownOverlay() async {
    if (!_showOverlay) return;
    _showOverlay = false;
    _overlayPoller?.cancel();
    _overlayStateWriter?.cancel();
    await AndroidOverlay.hideOverlay();
    notifyListeners();
  }

  void startOverlayEventPoller() {
    _overlayPoller?.cancel();
    _overlayPoller = Timer.periodic(const Duration(milliseconds: 700), (_) => _consumeOverlayEvents());
  }

  void _startOverlayStateWriter() {
    _overlayStateWriter?.cancel();
    _overlayStateWriter = Timer.periodic(const Duration(milliseconds: 400), (_) => _persistOverlayState(source: 'main'));
  }

  Future<void> _consumeOverlayEvents() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final raw = prefs.getString('overlay_events') ?? '[]';
    List events;
    try {
      events = jsonDecode(raw) as List;
    } catch (_) {
      events = [];
    }

    for (final e in events) {
      final id = e['id']?.toString();
      if (id == null || _processedOverlayIds.contains(id)) continue;
      _processedOverlayIds.add(id);

      final type = e['type'];
      if (type == 'start') {
        startStopwatch();
      } else if (type == 'lap') {
        final elapsedMs = e['elapsedMs'];
        if (!_isRunning) {
          startStopwatch();
        }
        if (elapsedMs is int) {
          addLapWithElapsed(elapsedMs);
        } else {
          addLap();
        }
      } else if (type == 'stop') {
        stopStopwatch();
      } else if (type == 'reset') {
        resetStopwatch();
      } else if (type == 'close') {
        _showOverlay = false;
        _overlayPoller?.cancel();
        notifyListeners();
      }
    }

    // Clean up processed events
    final remaining = events.where((e) => !_processedOverlayIds.contains(e['id']?.toString())).toList();
    await prefs.setString('overlay_events', jsonEncode(remaining));

    // Prevent unbounded growth of processed ids
    if (_processedOverlayIds.length > 2000) {
      _processedOverlayIds.clear();
    }
  }

  Future<void> syncOverlayState() async {
    await _consumeOverlayEvents();

    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final source = prefs.getString('overlay_state_source');
    final ts = prefs.getInt('overlay_state_ts') ?? 0;
    if (source != 'overlay' || ts <= _lastOverlayStateTsFromOverlay) return;

    final elapsedMs = prefs.getInt('overlay_elapsed_ms') ?? 0;
    final accumulatedMs = prefs.getInt('overlay_accumulated_ms') ?? elapsedMs;
    final runningSince = prefs.getInt('overlay_running_since_ms') ?? -1;
    final isRunning = prefs.getBool('overlay_is_running') ?? false;

    final now = DateTime.now().millisecondsSinceEpoch;
    final hasRunningSince = runningSince > 0;
    final safeRunningSince = hasRunningSince ? runningSince : now;
    final safeAccumulated = hasRunningSince ? accumulatedMs : elapsedMs;

    _lastOverlayStateTsFromOverlay = ts;
    _isRunning = isRunning;
    if (isRunning) {
      _accumulatedMilliseconds = safeAccumulated;
      _lastStartTimestamp = safeRunningSince;
      if (_currentSession == null) {
        _currentSession = Session(
          sessionStart: safeRunningSince,
          sessionEnd: safeRunningSince,
          laps: [],
          isCountdown: _isCountdownMode,
          countdownInitialMs: _isCountdownMode ? _countdownTotalMs : 0,
        );
      } else if (_currentSession!.sessionStart > safeRunningSince) {
        _currentSession = Session(
          sessionStart: safeRunningSince,
          sessionEnd: safeRunningSince,
          laps: _currentSession!.laps,
          isCountdown: _currentSession!.isCountdown,
          countdownInitialMs: _currentSession!.countdownInitialMs,
        );
      }
    } else {
      _accumulatedMilliseconds = elapsedMs;
      _lastStartTimestamp = null;
    }

    notifyListeners();
  }

  void _saveSessions() {
    try {
      final raw = jsonEncode(_sessions.map((s) => s.toJson()).toList());
      _prefs.setString('sessions', raw);
    } catch (_) {}
  }

  void _saveCurrentSession() {
    try {
      if (_currentSession == null) {
        _prefs.remove('currentSession');
        return;
      }
      final raw = jsonEncode(_currentSession!.toJson());
      _prefs.setString('currentSession', raw);
    } catch (_) {}
  }

  void persistCurrentSessionSnapshot({bool updateEnd = false}) {
    if (updateEnd && _currentSession != null) {
      _currentSession!.sessionEnd = DateTime.now().millisecondsSinceEpoch;
    }
    _saveCurrentSession();
  }

  void startStopwatch() {
    if (_isRunning) return;
    if (_isCountdownMode && elapsedMilliseconds >= _countdownTotalMs) {
      _accumulatedMilliseconds = 0;
      _lastStartTimestamp = null;
    }
    _isRunning = true;
    _lastStartTimestamp = DateTime.now().millisecondsSinceEpoch;
    _countdownFinishedNotified = false;
    // If there's an existing session (paused), resume it instead of creating a new one.
    if (_currentSession == null) {
      final now = _lastStartTimestamp!;
      _currentSession = Session(
        sessionStart: now,
        sessionEnd: now,
        laps: [],
        isCountdown: _isCountdownMode,
        countdownInitialMs: _isCountdownMode ? _countdownTotalMs : 0,
      );
    } else {
      // update sessionEnd to now when resuming
      _currentSession!.sessionEnd = DateTime.now().millisecondsSinceEpoch;
    }
    _saveCurrentSession();
    notifyListeners();
    _persistOverlayState();
  }

  void stopStopwatch() {
    if (!_isRunning) return;
    _accumulatedMilliseconds = elapsedMilliseconds;
    _lastStartTimestamp = null;
    _isRunning = false;
    if (_currentSession != null) {
      _currentSession!.sessionEnd = DateTime.now().millisecondsSinceEpoch;
    }
    _saveCurrentSession();
    notifyListeners();
    _persistOverlayState();
  }

  void tick() {
    if (_isRunning) {
      if (_isCountdownMode) {
        if (elapsedMilliseconds >= _countdownTotalMs) {
          _accumulatedMilliseconds = _countdownTotalMs;
          _lastStartTimestamp = null;
          _isRunning = false;
          final now = DateTime.now().millisecondsSinceEpoch;
          if (_currentSession != null) {
            _currentSession!.sessionEnd = now;
          }
          _saveCurrentSession();
          if (!_countdownFinishedNotified && _vibrateOnCountdownFinish) {
            _countdownFinishedNotified = true;
            HapticFeedback.vibrate();
          }
          notifyListeners();
          _persistOverlayState(source: 'main');
          return;
        }
      }

      notifyListeners();
      if (_showOverlay) {
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - _lastOverlayPersistMs >= 400) {
          _lastOverlayPersistMs = now;
          _persistOverlayState(source: 'main');
        }
      }
    }
  }

  void addLap() {
    if (_isCountdownMode) return;
    if (_isRunning) {
      // compute lap times relative to sessionStart
      final elapsed = elapsedMilliseconds;
      final session = _currentSession;
      if (session == null) return;
      final sessionStart = session.sessionStart;
      final previousElapsed = session.laps.isNotEmpty ? session.laps.last.endTime - sessionStart : 0;
      final lapStartTime = sessionStart + previousElapsed;
      final lapEndTime = sessionStart + elapsed;
      final duration = lapEndTime - lapStartTime;
      final lapNumber = session.laps.length + 1;
      final entry = LapEntry(lapNumber: lapNumber, startTime: lapStartTime, endTime: lapEndTime, duration: duration);
      session.laps.add(entry);
      // also keep a simple elapsed list for compatibility
      _laps.add(elapsed);
      notifyListeners();
      // persist sessions list but not yet finalized until reset
      _saveSessions();
      _saveCurrentSession();
    }
  }

  void addLapWithElapsed(int elapsedMs) {
    if (_isCountdownMode) return;
    final session = _currentSession;
    if (session == null) return;
    final sessionStart = session.sessionStart;
    final previousElapsed = session.laps.isNotEmpty ? session.laps.last.endTime - sessionStart : 0;
    final safeElapsed = elapsedMs < previousElapsed ? previousElapsed : elapsedMs;
    final lapStartTime = sessionStart + previousElapsed;
    final lapEndTime = sessionStart + safeElapsed;
    final duration = lapEndTime - lapStartTime;
    final lapNumber = session.laps.length + 1;
    final entry = LapEntry(lapNumber: lapNumber, startTime: lapStartTime, endTime: lapEndTime, duration: duration);
    session.laps.add(entry);
    _laps.add(safeElapsed);
    notifyListeners();
    _saveSessions();
    _saveCurrentSession();
  }

  void updateLapLabel(Session session, int lapNumber, String label) {
    final normalized = label.trim();
    final sessionStart = session.sessionStart;
    var updated = false;

    if (_currentSession != null && _currentSession!.sessionStart == sessionStart) {
      updated = _setLapLabel(_currentSession!, lapNumber, normalized) || updated;
    }

    for (final stored in _sessions) {
      if (stored.sessionStart != sessionStart) continue;
      updated = _setLapLabel(stored, lapNumber, normalized) || updated;
      break;
    }

    if (updated) {
      _saveSessions();
      _saveCurrentSession();
      notifyListeners();
    }
  }

  bool _setLapLabel(Session session, int lapNumber, String label) {
    final index = session.laps.indexWhere((lap) => lap.lapNumber == lapNumber);
    if (index == -1) return false;
    final current = session.laps[index];
    if (current.customLabel == label) return false;
    session.laps[index] = current.copyWith(customLabel: label);
    return true;
  }

  void resetStopwatch() {
    // finalize current session
    if (_currentSession != null) {
      final session = _currentSession!;
      session.sessionEnd = session.sessionStart + elapsedMilliseconds;
      _sessions.add(session);
      _currentSession = null;
      _saveSessions();
    }
    _saveCurrentSession();

    _accumulatedMilliseconds = 0;
    _lastStartTimestamp = null;
    _isRunning = false;
    _countdownFinishedNotified = false;
    _laps.clear();
    notifyListeners();
    _persistOverlayState();
  }

  void deleteSession(Session session) {
    final sessionStart = session.sessionStart;
    if (_isRunning && _currentSession != null && _currentSession!.sessionStart == sessionStart) {
      return;
    }
    _sessions.removeWhere((s) => s.sessionStart == sessionStart);
    if (_currentSession != null && _currentSession!.sessionStart == sessionStart) {
      _currentSession = null;
      _accumulatedMilliseconds = 0;
      _lastStartTimestamp = null;
      _isRunning = false;
      _countdownFinishedNotified = false;
      _laps.clear();
    }
    _saveSessions();
    _saveCurrentSession();
    notifyListeners();
    _persistOverlayState();
  }


  Future<void> _persistOverlayState({String source = 'main'}) async {
    try {
      final lastLapElapsed = _laps.isNotEmpty ? _laps.last : 0;
      await _prefs.setInt('overlay_elapsed_ms', elapsedMilliseconds);
      await _prefs.setInt('overlay_accumulated_ms', _accumulatedMilliseconds);
      await _prefs.setInt('overlay_running_since_ms', _lastStartTimestamp ?? -1);
      await _prefs.setBool('overlay_is_running', _isRunning);
      await _prefs.setInt('overlay_last_lap_elapsed_ms', lastLapElapsed);
      await _prefs.setInt('overlay_state_ts', DateTime.now().millisecondsSinceEpoch);
      await _prefs.setString('overlay_state_source', source);
      await _prefs.setBool('overlay_is_countdown', _isCountdownMode);
      await _prefs.setInt('overlay_countdown_total_ms', _countdownTotalMs);
    } catch (_) {
      // ignore - best effort
    }
  }


  /// Add a method to clear all persisted sessions (for debug)
  void clearSessions() {
    _sessions.clear();
    _currentSession?.laps.clear();
    _laps.clear();
    _prefs.remove('sessions');
    notifyListeners();
  }

  @override
  void dispose() {
    _overlayPoller?.cancel();
    _overlayStateWriter?.cancel();
    super.dispose();
  }
}
