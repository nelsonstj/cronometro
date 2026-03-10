import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/stopwatch_provider.dart';

class StopwatchDisplay extends StatelessWidget {
  const StopwatchDisplay({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<StopwatchProvider>(
      builder: (context, provider, child) {
        // Compute lap display and total display
        final displayMs = provider.displayMilliseconds;
        String lapMain = _formatMain(displayMs, provider.showHours, provider.breakMinutesByHour);
        String lapMs = _formatMs(displayMs);
        String totalMain = _formatMain(displayMs, provider.showHours, provider.breakMinutesByHour);
        String totalMs = _formatMs(displayMs);

        final currentSession = provider.currentSession;
        if (!provider.isCountdownMode && provider.showLapTime && currentSession != null && currentSession.laps.isNotEmpty) {
          final sessionStart = currentSession.sessionStart;
          final lastLapEnd = currentSession.laps.last.endTime - sessionStart;
          final currentLapTime = provider.elapsedMilliseconds - lastLapEnd;
          lapMain = _formatMain(currentLapTime, provider.showHours, provider.breakMinutesByHour);
          lapMs = _formatMs(currentLapTime);
        } else if (!provider.isCountdownMode && provider.showLapTime && provider.laps.isNotEmpty) {
          // fallback to old behavior
          final currentLapTime = provider.elapsedMilliseconds - provider.laps.last;
          lapMain = _formatMain(currentLapTime, provider.showHours, provider.breakMinutesByHour);
          lapMs = _formatMs(currentLapTime);
        } else {
          lapMain = _formatMain(displayMs, provider.showHours, provider.breakMinutesByHour);
          lapMs = _formatMs(displayMs);
        }

        if (provider.isCountdownMode) {
          totalMain = _formatMain(provider.countdownTotalMilliseconds, provider.showHours, provider.breakMinutesByHour);
          totalMs = _formatMs(provider.countdownTotalMilliseconds);
        } else {
          totalMain = _formatMain(displayMs, provider.showHours, provider.breakMinutesByHour);
          totalMs = _formatMs(displayMs);
        }

        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Lap timer (big)
            if (provider.showMilliseconds)
              Text.rich(
                TextSpan(
                  text: lapMain,
                  style: const TextStyle(
                    fontSize: 72,
                    fontWeight: FontWeight.w200,
                    fontFamily: 'Roboto Mono',
                  ),
                  children: [
                    TextSpan(
                      text: '.$lapMs',
                      style: const TextStyle(
                        fontSize: 52,
                        fontWeight: FontWeight.w200,
                        fontFamily: 'Roboto Mono',
                      ),
                    ),
                  ],
                ),
              )
            else
              Text(
                lapMain,
                style: const TextStyle(
                  fontSize: 72,
                  fontWeight: FontWeight.w200,
                  fontFamily: 'Roboto Mono',
                ),
              ),
            const SizedBox(height: 8),
            // Total timer (smaller)
            if (provider.showMilliseconds)
              Text.rich(
                TextSpan(
                  text: totalMain,
                  style: const TextStyle(
                    fontSize: 20,
                    color: Colors.grey,
                    fontFamily: 'Roboto Mono',
                  ),
                  children: [
                    TextSpan(
                      text: '.$totalMs',
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.grey,
                        fontFamily: 'Roboto Mono',
                      ),
                    ),
                  ],
                ),
              )
            else
              Text(
                totalMain,
                style: const TextStyle(
                  fontSize: 20,
                  color: Colors.grey,
                  fontFamily: 'Roboto Mono',
                ),
              ),
          ],
        );
      },
    );
  }

  String _formatMain(int milliseconds, bool showHours, bool breakMinutesByHour) {
    int totalSeconds = milliseconds ~/ 1000;
    int minutes = totalSeconds ~/ 60;
    
    // Determinar se deve mostrar horas
    final shouldShowHours = showHours || (breakMinutesByHour && minutes >= 60);
    
    if (shouldShowHours) {
      int hours = totalSeconds ~/ 3600;
      int mins = (totalSeconds % 3600) ~/ 60;
      int seconds = totalSeconds % 60;
      return '${hours.toString().padLeft(2, '0')}:${mins.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }

    int seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String _formatMs(int milliseconds) {
    int ms = (milliseconds % 1000) ~/ 10;
    return ms.toString().padLeft(2, '0');
  }
}
