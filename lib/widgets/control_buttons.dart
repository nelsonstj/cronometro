import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/stopwatch_provider.dart';

class ControlButtons extends StatelessWidget {
  const ControlButtons({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<StopwatchProvider>(
      builder: (context, provider, child) {
        List<Widget> withSpacing(List<Widget> items) {
          if (items.length < 2) {
            return items;
          }
          return [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(width: 24),
              items[i],
            ]
          ];
        }

        final buttons = <Widget>[];

        // Botao Reset
        if (!provider.isRunning && provider.elapsedMilliseconds > 0) {
          buttons.add(
            FloatingActionButton(
              onPressed: () {
                provider.resetStopwatch();
              },
              backgroundColor: Colors.grey[300],
              child: const Icon(
                Icons.refresh,
                color: Colors.black,
              ),
            ),
          );
        }

        // Botao Play/Pause
        buttons.add(
          FloatingActionButton(
            onPressed: () {
              if (provider.isRunning) {
                provider.stopStopwatch();
              } else {
                provider.startStopwatch();
              }
            },
            backgroundColor: provider.isRunning ? Colors.red : Colors.green,
            child: Icon(
              provider.isRunning ? Icons.pause : Icons.play_arrow,
              color: Colors.white,
            ),
          ),
        );

        // Botao Volta
        if (provider.isRunning && !provider.isCountdownMode) {
          buttons.add(
            FloatingActionButton(
              onPressed: () {
                provider.addLap();
              },
              backgroundColor: Colors.grey[300],
              child: const Icon(
                Icons.flag,
                color: Colors.black,
              ),
            ),
          );
        }

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: withSpacing(buttons),
        );
      },
    );
  }
}
