import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OverlayApp extends StatefulWidget {
  const OverlayApp({super.key});

  @override
  State<OverlayApp> createState() => _OverlayAppState();
}

class _OverlayAppState extends State<OverlayApp> {
  Timer? _refreshTimer;
  Timer? _actionsTimer;
  Timer? _positionTimer;
  bool _isResizing = false;  // Evita múltiplos resizes simultâneos
  Duration _elapsed = Duration.zero;
  int _accumulatedMs = 0;
  int _runningSinceMs = -1;
  int _lastLapElapsedMs = 0;
  bool _isRunning = false;
  int _lastStateTs = 0;
  bool _showActions = false;
  bool _showMilliseconds = true;
  bool _showHours = true;
  Color _overlayStoppedBgColor = const Color(0xD9000000);
  Color _overlayRunningBgColor = const Color(0xD9000000);
  Color _overlayTextColor = const Color(0xFFFFFFFF);
  double _overlayFontSize = 22.0;
  bool _isCountdownMode = false;
  int _countdownTotalMs = 0;
  double? _lastSavedPosX;
  double? _lastSavedPosY;
  int _lastLapSetTsMs = 0;

  @override
  void initState() {
    super.initState();
    _actionsTimer?.cancel();  // Cancela timer pendente de long press anterior
    _showActions = false;     // Reset imediato - evita mostrar opções ao reabrir
    _initFromPrefs();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _actionsTimer?.cancel();
    _positionTimer?.cancel();
    super.dispose();
  }

  void _showActionsTemporarily() {
    _actionsTimer?.cancel();
    setState(() {
      _showActions = true;
    });
    _actionsTimer = Timer(const Duration(seconds: 10), () {
      if (!mounted) return;
      setState(() {
        _showActions = false;
      });
    });
  }

  Future<void> _initFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final savedPosX = prefs.getDouble('overlay_pos_x');
    final savedPosY = prefs.getDouble('overlay_pos_y');
    final elapsedMs = prefs.getInt('overlay_elapsed_ms') ?? 0;
    final accumulatedMs = prefs.getInt('overlay_accumulated_ms') ?? elapsedMs;
    final runningSince = prefs.getInt('overlay_running_since_ms') ?? -1;
    final lastLapElapsed = prefs.getInt('overlay_last_lap_elapsed_ms') ?? 0;
    final isRunning = prefs.getBool('overlay_is_running') ?? false;
    final lastTs = prefs.getInt('overlay_state_ts') ?? 0;
    final showMilliseconds = prefs.getBool('showMilliseconds') ?? true;
    final showHours = prefs.getBool('showHours') ?? true;
    final stoppedBgColor = Color(prefs.getInt('overlayStoppedBgColor') ?? 0xD9000000);
    final runningBgColor = Color(prefs.getInt('overlayRunningBgColor') ?? 0xD9000000);
    final textColor = Color(prefs.getInt('overlayTextColor') ?? 0xFFFFFFFF);
    final fontSize = prefs.getDouble('overlayFontSize') ?? 22.0;
    final isCountdown = prefs.getBool('overlay_is_countdown') ?? false;
    final countdownTotal = prefs.getInt('overlay_countdown_total_ms') ?? 0;

    if (!mounted) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final hasRunningSince = runningSince > 0;
    final safeRunningSince = hasRunningSince ? runningSince : now;
    final safeAccumulated = hasRunningSince ? accumulatedMs : elapsedMs;
    final initialElapsed = isRunning
      ? (safeAccumulated + (now - safeRunningSince))
      : elapsedMs;
    final safeLastLap = lastLapElapsed > initialElapsed ? 0 : lastLapElapsed;

    setState(() {
      _elapsed = Duration(milliseconds: initialElapsed);
      _accumulatedMs = safeAccumulated;
      _runningSinceMs = isRunning ? safeRunningSince : -1;
      _lastLapElapsedMs = safeLastLap;
      _isRunning = isRunning;
      _lastStateTs = lastTs;
      _showMilliseconds = showMilliseconds;
      _showHours = showHours;
      _overlayStoppedBgColor = stoppedBgColor;
      _overlayRunningBgColor = runningBgColor;
      _overlayTextColor = textColor;
      _overlayFontSize = fontSize;
      _isCountdownMode = isCountdown;
      _countdownTotalMs = countdownTotal;
      _lastSavedPosX = savedPosX;
      _lastSavedPosY = savedPosY;
      _showActions = false;
    });

    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      _pullFromPrefs();
      _recomputeElapsed();
    });

    await _resizeOverlayWindow();
    await Future.delayed(const Duration(milliseconds: 200));
    await _restoreLastPosition(savedPosX, savedPosY);
    _startPositionPoller();

  }

  void _startPositionPoller() {
    _positionTimer?.cancel();
    _positionTimer = Timer.periodic(const Duration(milliseconds: 300), (_) {
      _saveOverlayPosition();
    });
  }

  Future<void> _saveOverlayPosition() async {
    try {
      final position = await FlutterOverlayWindow.getOverlayPosition();
      var x = position.x.toDouble();
      var y = position.y.toDouble();
      
      // Protege contra salvar (0,0) quando overlay foi destruído
      if (x == 0.0 && y == 0.0 && (_lastSavedPosX != 0.0 || _lastSavedPosY != 0.0)) {
        return;
      }
      
      if (_lastSavedPosX == x && _lastSavedPosY == y) {
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      final screenW = prefs.getDouble('overlay_screen_w');
      final screenH = prefs.getDouble('overlay_screen_h');
      if (screenW != null && screenH != null) {
        final maxX = screenW - _overlayWidth();
        final maxY = screenH - _overlayExpandedHeight();
        final clampedX = x.clamp(0.0, maxX < 0 ? 0.0 : maxX);
        final clampedY = y.clamp(0.0, maxY < 0 ? 0.0 : maxY);
        if (clampedX != x || clampedY != y) {
          await FlutterOverlayWindow.moveOverlay(OverlayPosition(clampedX, clampedY));
          x = clampedX;
          y = clampedY;
        }
      }
      await prefs.setDouble('overlay_pos_x', x);
      await prefs.setDouble('overlay_pos_y', y);
      _lastSavedPosX = x;
      _lastSavedPosY = y;
    } catch (_) {
      // Best effort - if position cannot be saved, continue
    }
  }

  Future<void> _restoreLastPosition(double? savedX, double? savedY) async {
    if (savedX == null || savedY == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final screenW = prefs.getDouble('overlay_screen_w');
      final screenH = prefs.getDouble('overlay_screen_h');
      var x = savedX;
      var y = savedY;
      if (screenW != null && screenH != null) {
        final maxX = screenW - _overlayWidth();
        final maxY = screenH - _overlayExpandedHeight();
        if (maxX >= 0) x = x.clamp(0.0, maxX);
        if (maxY >= 0) y = y.clamp(0.0, maxY);
      }
      await FlutterOverlayWindow.moveOverlay(OverlayPosition(x, y));
      _lastSavedPosX = x;
      _lastSavedPosY = y;
    } catch (_) {
      // Best effort - if restore fails, overlay will use last known position
    }
  }

  Future<void> _pullFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final elapsedMs = prefs.getInt('overlay_elapsed_ms');
    final accumulatedMs = prefs.getInt('overlay_accumulated_ms');
    final runningSince = prefs.getInt('overlay_running_since_ms');
    final lastLapElapsed = prefs.getInt('overlay_last_lap_elapsed_ms');
    final isRunning = prefs.getBool('overlay_is_running');
    final source = prefs.getString('overlay_state_source');
    final ts = prefs.getInt('overlay_state_ts') ?? 0;
    final showMilliseconds = prefs.getBool('showMilliseconds') ?? true;
    final showHours = prefs.getBool('showHours') ?? true;
    final stoppedBgColor = Color(prefs.getInt('overlayStoppedBgColor') ?? 0xD9000000);
    final runningBgColor = Color(prefs.getInt('overlayRunningBgColor') ?? 0xD9000000);
    final textColor = Color(prefs.getInt('overlayTextColor') ?? 0xFFFFFFFF);
    final fontSize = prefs.getDouble('overlayFontSize') ?? 22.0;
    final isCountdown = prefs.getBool('overlay_is_countdown') ?? false;
    final countdownTotal = prefs.getInt('overlay_countdown_total_ms') ?? 0;
    if (elapsedMs == null || isRunning == null) return;

    // Mudanças que afetam TAMANHO requerem resize
    final sizeSettingsChanged = showMilliseconds != _showMilliseconds ||
        showHours != _showHours ||
        fontSize != _overlayFontSize;
    
    // Mudanças de COR não afetam tamanho, apenas visual
    final colorSettingsChanged = stoppedBgColor.toARGB32() != _overlayStoppedBgColor.toARGB32() ||
        runningBgColor.toARGB32() != _overlayRunningBgColor.toARGB32() ||
        textColor.toARGB32() != _overlayTextColor.toARGB32();
    
    final countdownSettingsChanged = isCountdown != _isCountdownMode ||
        countdownTotal != _countdownTotalMs;

    final settingsChanged = sizeSettingsChanged || colorSettingsChanged || countdownSettingsChanged;

    if (source != 'main') {
      if (settingsChanged) {
        setState(() {
          _showMilliseconds = showMilliseconds;
          _showHours = showHours;
          _overlayStoppedBgColor = stoppedBgColor;
          _overlayRunningBgColor = runningBgColor;
          _overlayTextColor = textColor;
          _overlayFontSize = fontSize;
          _isCountdownMode = isCountdown;
          _countdownTotalMs = countdownTotal;
        });
        // Só faz resize se mudanças afetam TAMANHO
        if (sizeSettingsChanged) {
          await _resizeOverlayWindow();
        }
      }
      return;
    }

    final needsUpdate = ts > _lastStateTs ||
        elapsedMs != _elapsed.inMilliseconds ||
        (accumulatedMs != null && accumulatedMs != _accumulatedMs) ||
        (runningSince != null && runningSince != _runningSinceMs) ||
        (lastLapElapsed != null && lastLapElapsed != _lastLapElapsedMs) ||
        isRunning != _isRunning;
    if (!needsUpdate && !settingsChanged) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final hasRunningSince = (runningSince ?? -1) > 0;
    final nextAccumulated = accumulatedMs ?? _accumulatedMs;
    final nextRunningSince = hasRunningSince ? runningSince! : now;
    final nextElapsed = isRunning
        ? (nextAccumulated + (now - nextRunningSince))
        : elapsedMs;
    var nextLastLap = (lastLapElapsed ?? _lastLapElapsedMs);
    final keepLocalLap = isRunning == true &&
        nextLastLap < _lastLapElapsedMs &&
        elapsedMs >= _lastLapElapsedMs &&
        (now - _lastLapSetTsMs) < 1500;
    if (keepLocalLap) {
      nextLastLap = _lastLapElapsedMs;
    }
    setState(() {
      _elapsed = Duration(milliseconds: nextElapsed);
      _accumulatedMs = isRunning && !hasRunningSince ? elapsedMs : nextAccumulated;
      _runningSinceMs = isRunning ? nextRunningSince : -1;
      _lastLapElapsedMs = nextLastLap > nextElapsed ? 0 : nextLastLap;
      _isRunning = isRunning;
      _lastStateTs = ts;
      _showMilliseconds = showMilliseconds;
      _showHours = showHours;
      _overlayStoppedBgColor = stoppedBgColor;
      _overlayRunningBgColor = runningBgColor;
      _overlayTextColor = textColor;
      _overlayFontSize = fontSize;
      _isCountdownMode = isCountdown;
      _countdownTotalMs = countdownTotal;
    });
    if (sizeSettingsChanged) {
      await _resizeOverlayWindow();
    }
  }

  void _recomputeElapsed() {
    if (!mounted) return;
    if (!_isRunning || _runningSinceMs <= 0) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final elapsedMs = _accumulatedMs + (now - _runningSinceMs);
    setState(() {
      _elapsed = Duration(milliseconds: elapsedMs);
    });
  }

  Duration _currentLapElapsed() {
    if (_isCountdownMode) {
      final remaining = _countdownTotalMs - _elapsed.inMilliseconds;
      final safe = remaining > 0 ? remaining : 0;
      return Duration(milliseconds: safe);
    }
    final total = _elapsed.inMilliseconds;
    final base = _lastLapElapsedMs;
    final lapMs = total >= base ? (total - base) : total;
    return Duration(milliseconds: lapMs);
  }

  Future<void> _pushEvent(Map<String, dynamic> event) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('overlay_events') ?? '[]';
    List events;
    try {
      events = jsonDecode(raw) as List;
    } catch (_) {
      events = [];
    }
    events.add(event);
    if (events.length > 200) {
      events = events.sublist(events.length - 200);
    }
    await prefs.setString('overlay_events', jsonEncode(events));
  }

  Future<void> _persistOverlayState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('overlay_elapsed_ms', _elapsed.inMilliseconds);
    await prefs.setInt('overlay_accumulated_ms', _accumulatedMs);
    await prefs.setInt('overlay_running_since_ms', _runningSinceMs);
    await prefs.setBool('overlay_is_running', _isRunning);
    await prefs.setInt('overlay_last_lap_elapsed_ms', _lastLapElapsedMs);
    await prefs.setInt('overlay_state_ts', DateTime.now().millisecondsSinceEpoch);
    await prefs.setString('overlay_state_source', 'overlay');
  }

  Future<void> _onSingleTap() async {
    _actionsTimer?.cancel();  // Cancela timer de ações ao tocar
    if (!_isRunning) {
      setState(() {
        _isRunning = true;
        _runningSinceMs = DateTime.now().millisecondsSinceEpoch;
        _showActions = false;
      });
      await _persistOverlayState();
      await _pushEvent({
        'type': 'start',
        'timestamp': DateTime.now().toIso8601String(),
        'elapsedMs': _elapsed.inMilliseconds,
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
      });
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    setState(() {
      _lastLapElapsedMs = _elapsed.inMilliseconds;
      _lastLapSetTsMs = now;
    });
    await _persistOverlayState();
    await _pushEvent({
      'type': 'lap',
      'timestamp': DateTime.now().toIso8601String(),
      'elapsedMs': _elapsed.inMilliseconds,
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
    });
  }

  Future<void> _onDoubleTap() async {
    if (_isRunning) {
      setState(() {
        _isRunning = false;
        _accumulatedMs = _elapsed.inMilliseconds;
        _runningSinceMs = -1;
      });
    }
    await _persistOverlayState();
    await _pushEvent({
      'type': 'stop',
      'timestamp': DateTime.now().toIso8601String(),
      'elapsedMs': _elapsed.inMilliseconds,
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
    });
  }

  Future<void> _resetFromOverlay() async {
    setState(() {
      _isRunning = false;
      _elapsed = Duration.zero;
      _accumulatedMs = 0;
      _runningSinceMs = -1;
      _lastLapElapsedMs = 0;
      _lastLapSetTsMs = 0;
      _showActions = false;
    });
    await _persistOverlayState();
    await _pushEvent({
      'type': 'reset',
      'timestamp': DateTime.now().toIso8601String(),
      'elapsedMs': _elapsed.inMilliseconds,
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
    });
  }

  Future<void> _closeFromOverlay() async {
    try {
      _actionsTimer?.cancel();    // Cancela qualquer timer de ações pendente
      _showActions = false;       // Reseta o estado das opções
      await _saveOverlayPosition();
      await _pushEvent({
        'type': 'close',
        'timestamp': DateTime.now().toIso8601String(),
        'elapsedMs': _elapsed.inMilliseconds,
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
      });
      await FlutterOverlayWindow.closeOverlay();
    } catch (_) {}
  }

  String _formatMain(Duration d) {
    if (_showHours) {
      final hours = d.inHours.toString().padLeft(2, '0');
      final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
      final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
      return '$hours:$minutes:$seconds';
    }

    final totalMinutes = d.inMinutes.toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$totalMinutes:$seconds';
  }

  String _formatMs(Duration d) {
    final centis = (d.inMilliseconds.remainder(1000) ~/ 10).toString().padLeft(2, '0');
    return centis;
  }

  double _overlayScale() {
    return (_overlayFontSize / 22.0).clamp(0.7, 2.0);
  }

  int _overlayCharCount() {
    final base = _showHours ? 8 : 5;
    final ms = _showMilliseconds ? 3 : 0;
    return base + ms;
  }

  double _overlayTextWidth() {
    return _overlayFontSize * 0.6 * _overlayCharCount();
  }

  double _overlayWidth() {
    final minWidth = 90 * _overlayScale();
    final width = _overlayTextWidth() + (_overlayPaddingH() * 2);
    return width < minWidth ? minWidth : width;
  }

  double _overlayBaseHeight() {
    final padding = _overlayPaddingV();
    final textHeight = _overlayFontSize * 1.2;
    return textHeight + (padding * 2);
  }

  double _overlayExpandedHeight() {
    return _overlayBaseHeight() + (44 * _overlayScale());
  }

  double _overlayPaddingH() {
    return 0.1 * _overlayScale();
  }

  double _overlayPaddingV() {
    return 0.8 * _overlayScale();
  }

  Future<void> _resizeOverlayWindow() async {
    if (_isResizing) return; // Evita múltiplos resizes simultâneos
    _isResizing = true;
    try {
      // Preserva a posição atual antes do resize
      final currentPosition = await FlutterOverlayWindow.getOverlayPosition();
      
      final dpr = PlatformDispatcher.instance.views.isNotEmpty
          ? PlatformDispatcher.instance.views.first.devicePixelRatio
          : 1.0;
      final widthPx = (_overlayWidth() * dpr).round();
      final heightPx = (_overlayExpandedHeight() * dpr).round();
      await FlutterOverlayWindow.resizeOverlay(widthPx, heightPx, true);
      
      // Restaura a posição após o resize
      await Future.delayed(const Duration(milliseconds: 150));
      await FlutterOverlayWindow.moveOverlay(currentPosition);
    } catch (_) {
      // Best effort - se resize falhar, continua
    } finally {
      _isResizing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: SizedBox.expand(
          child: Center(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _onSingleTap,
              onDoubleTap: _onDoubleTap,
              onLongPress: () {
                if (_showActions) {
                  setState(() {
                    _showActions = false;
                  });
                  _actionsTimer?.cancel();
                } else {
                  _showActionsTemporarily();
                }
              },
              child: Container(
                width: _overlayWidth(),
                  height: _showActions ? _overlayExpandedHeight() : _overlayBaseHeight(),
                alignment: Alignment.center,
                padding: EdgeInsets.symmetric(
                  horizontal: _overlayPaddingH(),
                  vertical: _overlayPaddingV(),
                ),
                decoration: BoxDecoration(
                  color: _isRunning ? _overlayRunningBgColor : _overlayStoppedBgColor,
                  borderRadius: BorderRadius.circular(8 * _overlayScale()),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 10 * _overlayScale(),
                      spreadRadius: 3 * _overlayScale(),
                    ),
                  ],
                ),
                child: _showActions
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (_showMilliseconds)
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text.rich(
                                TextSpan(
                                  text: _formatMain(_currentLapElapsed()),
                                  style: TextStyle(
                                    color: _overlayTextColor,
                                    fontSize: _overlayFontSize,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Roboto Mono',
                                  ),
                                  children: [
                                    TextSpan(
                                      text: '.${_formatMs(_currentLapElapsed())}',
                                      style: TextStyle(
                                        color: _overlayTextColor.withValues(alpha: 0.75),
                                        fontSize: _overlayFontSize * 0.72,
                                        fontWeight: FontWeight.bold,
                                        fontFamily: 'Roboto Mono',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          else
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                _formatMain(_currentLapElapsed()),
                                style: TextStyle(
                                  color: _overlayTextColor,
                                  fontSize: _overlayFontSize,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Roboto Mono',
                                ),
                              ),
                            ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: _resetFromOverlay,
                                  child: Container(
                                    height: 24 * _overlayScale(),
                                    alignment: Alignment.center,
                                    margin: const EdgeInsets.only(left: 6, right: 3),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(4 * _overlayScale()),
                                    ),
                                    child: Text(
                                      'Zerar',
                                      style: TextStyle(
                                        color: _overlayTextColor.withValues(alpha: 0.85),
                                        fontSize: 10 * _overlayScale(),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: _closeFromOverlay,
                                  child: Container(
                                    height: 24 * _overlayScale(),
                                    alignment: Alignment.center,
                                    margin: const EdgeInsets.only(left: 3, right: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(4 * _overlayScale()),
                                    ),
                                    child: Text(
                                      'Fechar',
                                      style: TextStyle(
                                        color: _overlayTextColor.withValues(alpha: 0.85),
                                        fontSize: 10 * _overlayScale(),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      )
                    : Center(
                        child: _showMilliseconds
                            ? FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text.rich(
                                  TextSpan(
                                    text: _formatMain(_currentLapElapsed()),
                                    style: TextStyle(
                                      color: _overlayTextColor,
                                      fontSize: _overlayFontSize,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'Roboto Mono',
                                    ),
                                    children: [
                                      TextSpan(
                                        text: '.${_formatMs(_currentLapElapsed())}',
                                        style: TextStyle(
                                          color: _overlayTextColor.withValues(alpha: 0.75),
                                          fontSize: _overlayFontSize * 0.72,
                                          fontWeight: FontWeight.bold,
                                          fontFamily: 'Roboto Mono',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  _formatMain(_currentLapElapsed()),
                                  style: TextStyle(
                                    color: _overlayTextColor,
                                    fontSize: _overlayFontSize,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Roboto Mono',
                                  ),
                                ),
                              ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
