import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../providers/stopwatch_provider.dart';

class LapList extends StatefulWidget {
  const LapList({super.key});

  @override
  State<LapList> createState() => _LapListState();
}

class _LapListState extends State<LapList> {
  final ScrollController _controller = ScrollController();
  int _lastTotalLaps = 0;
  int _lastCurrentLaps = 0;

  void _scrollToTop() {
    if (_controller.hasClients) {
      _controller.jumpTo(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<StopwatchProvider>(
      builder: (context, provider, child) {
        // Build combined sessions: include current session at top
        final sessions = <Session>[];
        if (provider.currentSession != null) {
          sessions.add(provider.currentSession!);
        }
        // Add persisted sessions in reverse (newest first)
        sessions.addAll(provider.sessions.reversed);

        final totalLaps = sessions.fold<int>(0, (p, s) => p + s.laps.length);
        final currentSessionLaps = provider.currentSession?.laps.length ?? 0;
        final expandCurrentNow = currentSessionLaps > _lastCurrentLaps;

        // After build, ensure scroll is at top when new lap/session added
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (totalLaps != _lastTotalLaps) {
            _lastTotalLaps = totalLaps;
            _scrollToTop();
          }
          _lastCurrentLaps = currentSessionLaps;
        });

        return Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Column(
              children: [
                // history list (each session shows its own total)
                Expanded(
                  child: ListView.builder(
                    controller: _controller,
                    itemCount: sessions.length,
                    itemBuilder: (context, sessionIndex) {
                      final session = sessions[sessionIndex];
                      final sessionStart = DateTime.fromMillisecondsSinceEpoch(session.sessionStart);
                      final isCurrent = provider.currentSession == session;
                      final sessionEndEpoch = isCurrent && provider.isRunning
                          ? DateTime.now().millisecondsSinceEpoch
                          : session.sessionEnd;
                      final sessionEnd = DateTime.fromMillisecondsSinceEpoch(sessionEndEpoch);
                      final sessionTotal = session.isCountdown
                          ? session.countdownInitialMs
                          : (session.laps.isNotEmpty
                              ? session.laps.fold<int>(0, (p, e) => p + e.duration)
                              : (session.sessionEnd - session.sessionStart));
                      final exportText = _buildSessionExport(
                        provider: provider,
                        session: session,
                        sessionStart: sessionStart,
                        sessionEnd: sessionEnd,
                        sessionTotal: sessionTotal,
                      );

                      return ExpansionTile(
                        key: isCurrent
                            ? ValueKey('current-${session.sessionStart}-${session.laps.length}')
                            : ValueKey('session-${session.sessionStart}'),
                        initiallyExpanded: isCurrent && expandCurrentNow,
                        title: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _formatSessionRange(sessionStart, sessionEnd),
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                                fontSize: 14,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.share, size: 18),
                              tooltip: 'Compartilhar',
                              onPressed: () async {
                                await Share.share(exportText);
                              },
                            ),
                            Text(
                              _formatMilliseconds(sessionTotal),
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface,
                                fontSize: 14,
                                fontFamily: 'Roboto Mono',
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        children: [
                          const SizedBox(height: 4),
                          ...session.laps.reversed.map((lap) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '${provider.lapLabel} ${lap.lapNumber}',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  Text(
                                    _formatMilliseconds(lap.duration),
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                      fontFamily: 'Roboto Mono',
                                      color: Theme.of(context).colorScheme.onSurface,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                          Divider(color: Theme.of(context).dividerColor),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatSessionRange(DateTime start, DateTime end) {
    final startStr = '${start.day}/${start.month}/${start.year} ${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}';
    final endStr = '${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}';
    return '$startStr - $endStr';
  }

  String _formatMilliseconds(int milliseconds) {
    int totalSeconds = milliseconds ~/ 1000;
    int minutes = totalSeconds ~/ 60;
    int seconds = totalSeconds % 60;
    int ms = (milliseconds % 1000) ~/ 10;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}.${ms.toString().padLeft(2, '0')}';
  }

  String _buildSessionExport({
    required StopwatchProvider provider,
    required Session session,
    required DateTime sessionStart,
    required DateTime sessionEnd,
    required int sessionTotal,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('Sessao: ${_formatSessionRange(sessionStart, sessionEnd)}');
    if (session.isCountdown) {
      buffer.writeln('Modo: Contagem regressiva');
      buffer.writeln('Tempo inicial: ${_formatSeconds(session.countdownInitialMs)}');
    } else {
      buffer.writeln('Modo: Cronometro');
      buffer.writeln('Total: ${_formatSeconds(sessionTotal)}');
    }

    if (session.laps.isEmpty) {
      buffer.writeln('${provider.lapLabel}: nenhum registro');
    } else {
      buffer.writeln('${provider.lapLabel}:');
      for (final lap in session.laps) {
        buffer.writeln('${provider.lapLabel} ${lap.lapNumber}: ${_formatSeconds(lap.duration)}');
      }
    }

    return buffer.toString();
  }

  String _formatSeconds(int milliseconds) {
    int totalSeconds = milliseconds ~/ 1000;
    int hours = totalSeconds ~/ 3600;
    int minutes = (totalSeconds % 3600) ~/ 60;
    int seconds = totalSeconds % 60;
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
