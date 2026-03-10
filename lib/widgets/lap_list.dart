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

  Future<void> _showLapLabelEditor(
    BuildContext context,
    StopwatchProvider provider,
    Session session,
    LapEntry lap,
  ) async {
    final controller = TextEditingController(text: lap.customLabel);
    final labelHint = '${provider.lapLabel} ${lap.lapNumber}';
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (stateContext, setState) {
            return AlertDialog(
              title: const Text('Nome do intervalo'),
              content: TextField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: labelHint,
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: (value) {
                  Navigator.of(dialogContext).pop(value);
                },
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('Cancelar'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop(controller.text);
                  },
                  child: const Text('Salvar'),
                ),
              ],
            );
          },
        );
      },
    );
    
    // Aguarda um frame antes de descartar o controller
    await Future.delayed(const Duration(milliseconds: 100));
    controller.dispose();

    if (result == null) return;
    if (!context.mounted) return;
    
    // Dispara update no próximo frame para evitar rebuild enquanto widgets estão sendo descartados
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      provider.updateLapLabel(session, lap.lapNumber, result);
    });
  }

  Future<void> _showSessionActions(
    BuildContext context,
    StopwatchProvider provider,
    Session session,
  ) async {
    final isCurrentRunning = provider.isRunning && provider.currentSession == session;
    if (isCurrentRunning) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pausa o cronometro para excluir a serie.')),
      );
      return;
    }

    final shouldDelete = await showModalBottomSheet<bool>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Excluir serie'),
            onTap: () {
              Navigator.of(sheetContext).pop(true);
            },
          ),
        );
      },
    );

    if (shouldDelete == true && context.mounted) {
      provider.deleteSession(session);
    }
  }

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
                        title: InkWell(
                          onLongPress: () => _showSessionActions(context, provider, session),
                          child: Row(
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
                                _formatSessionTotalWithHours(sessionTotal),
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onSurface,
                                  fontSize: 14,
                                  fontFamily: 'Roboto Mono',
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        children: [
                          const SizedBox(height: 4),
                          ...session.laps.reversed.map((lap) {
                            final labelText = _lapDisplayLabel(provider, lap);
                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
                              child: InkWell(
                                onLongPress: () => _showLapLabelEditor(context, provider, session, lap),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      labelText,
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
    int hours = totalSeconds ~/ 3600;
    int minutes = (totalSeconds % 3600) ~/ 60;
    int seconds = totalSeconds % 60;
    int ms = (milliseconds % 1000) ~/ 10;
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}.${ms.toString().padLeft(2, '0')}';
  }

  String _formatSessionTotalWithHours(int milliseconds) {
    final totalSeconds = milliseconds ~/ 1000;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String _buildSessionExport({
    required StopwatchProvider provider,
    required Session session,
    required DateTime sessionStart,
    required DateTime sessionEnd,
    required int sessionTotal,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('Sessão: ${_formatSessionRange(sessionStart, sessionEnd)}');
    if (session.isCountdown) {
      buffer.writeln('Modo: Contagem regressiva');
      buffer.writeln('Tempo inicial: ${_formatSeconds(session.countdownInitialMs)}');
    } else {
      buffer.writeln('Modo: Cronômetro');
      buffer.writeln('Total: ${_formatSeconds(sessionTotal)}');
    }

    if (session.laps.isEmpty) {
      buffer.writeln('${provider.lapLabel}: nenhum registro');
    } else {
      buffer.writeln('${provider.lapLabel}:');
      for (final lap in session.laps) {
        final labelText = _lapDisplayLabel(provider, lap);
        buffer.writeln('$labelText: ${_formatSeconds(lap.duration)}');
      }
    }

    return buffer.toString();
  }

  String _formatSeconds(int milliseconds) {
    int totalSeconds = milliseconds ~/ 1000;
    int hours = totalSeconds ~/ 3600;
    int minutes = (totalSeconds % 3600) ~/ 60;
    int seconds = totalSeconds % 60;
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String _lapDisplayLabel(StopwatchProvider provider, LapEntry lap) {
    final custom = lap.customLabel.trim();
    if (custom.isEmpty) {
      return '${provider.lapLabel} ${lap.lapNumber}';
    }
    return custom;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
