import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import '../providers/stopwatch_provider.dart';
import '../utils/android_overlay.dart';

class SettingsPanel extends StatefulWidget {
  const SettingsPanel({super.key});

  @override
  State<SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<SettingsPanel> {
  final TextEditingController _hoursController = TextEditingController();
  final TextEditingController _minutesController = TextEditingController();
  final TextEditingController _secondsController = TextEditingController();
  final TextEditingController _lapLabelController = TextEditingController();
  final FocusNode _hoursFocus = FocusNode();
  final FocusNode _minutesFocus = FocusNode();
  final FocusNode _secondsFocus = FocusNode();
  final FocusNode _lapLabelFocus = FocusNode();
  bool _isEditingCountdown = false;
  bool _isEditingLapLabel = false;
  late Future<PackageInfo> _packageInfo;

  static const List<_ColorOption> _overlayBgColors = [
    _ColorOption('Preto', Color(0xD9000000)),
    _ColorOption('Cinza', Color(0xD9424242)),
    _ColorOption('Azul', Color(0xD91976D2)),
    _ColorOption('Verde', Color(0xD92E7D32)),
    _ColorOption('Vermelho', Color(0xD9C62828)),
    _ColorOption('Amarelo', Color(0xD9F9A825)),
    _ColorOption('Roxo', Color(0xD95b3c88)),
    _ColorOption('Branco', Color(0xD9FFFFFF)),
  ];

  static const List<_ColorOption> _overlayTextColors = [
    _ColorOption('Preto', Color(0xFF000000)),
    _ColorOption('Cinza', Color(0xFFBDBDBD)),
    _ColorOption('Azul', Color(0xFF90CAF9)),
    _ColorOption('Verde', Color(0xFFA5D6A7)),
    _ColorOption('Vermelho', Color(0xFFEF9A9A)),
    _ColorOption('Amarelo', Color(0xFFFFF59D)),
    _ColorOption('Roxo', Color(0xFFD9C1FF)),
    _ColorOption('Branco', Color(0xFFFFFFFF)),
  ];

  @override
  void initState() {
    super.initState();
    _hoursFocus.addListener(_handleFocusChange);
    _minutesFocus.addListener(_handleFocusChange);
    _secondsFocus.addListener(_handleFocusChange);
    _lapLabelFocus.addListener(_handleLapLabelFocus);
    _packageInfo = PackageInfo.fromPlatform();
  }

  @override
  void dispose() {
    _hoursController.dispose();
    _minutesController.dispose();
    _secondsController.dispose();
    _lapLabelController.dispose();
    _hoursFocus.dispose();
    _minutesFocus.dispose();
    _secondsFocus.dispose();
    _lapLabelFocus.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    final isEditing = _hoursFocus.hasFocus || _minutesFocus.hasFocus || _secondsFocus.hasFocus;
    if (_isEditingCountdown != isEditing) {
      setState(() {
        _isEditingCountdown = isEditing;
      });
    }
  }

  void _syncCountdownFields(StopwatchProvider provider) {
    if (_isEditingCountdown) return;
    final totalSeconds = provider.countdownTotalMilliseconds ~/ 1000;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    _hoursController.text = _formatTwoDigits(hours);
    _minutesController.text = _formatTwoDigits(minutes);
    _secondsController.text = _formatTwoDigits(seconds);
  }

  void _syncLapLabel(StopwatchProvider provider) {
    if (_isEditingLapLabel) return;
    if (_lapLabelController.text != provider.lapLabel) {
      _lapLabelController.text = provider.lapLabel;
    }
  }

  void _handleLapLabelFocus() {
    final isEditing = _lapLabelFocus.hasFocus;
    if (_isEditingLapLabel != isEditing) {
      setState(() {
        _isEditingLapLabel = isEditing;
      });
    }
  }

  void _applyCountdownFromFields(StopwatchProvider provider) {
    final hours = int.tryParse(_hoursController.text) ?? 0;
    final minutes = int.tryParse(_minutesController.text) ?? 0;
    final seconds = int.tryParse(_secondsController.text) ?? 0;
    final duration = Duration(hours: hours, minutes: minutes, seconds: seconds);
    provider.setCountdownTotal(duration);
  }

  @override
  Widget build(BuildContext context) {
    final isAndroid = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

    return Consumer<StopwatchProvider>(
      builder: (context, provider, child) {
        _syncCountdownFields(provider);
        _syncLapLabel(provider);
        return Container(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Configurações',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Cronômetro',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    title: const Text('Mostrar Tempo de Volta'),
                    subtitle: const Text(
                      'Exibir o tempo de cada volta em vez do tempo total',
                    ),
                    trailing: Switch(
                      value: provider.showLapTime,
                      onChanged: (_) {
                        provider.toggleShowLapTime();
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _lapLabelController,
                    focusNode: _lapLabelFocus,
                    decoration: const InputDecoration(
                      labelText: 'Nome da volta',
                      hintText: 'Ex.: Volta, Parte, Sprint',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (value) {
                      provider.setLapLabel(value);
                    },
                    onFieldSubmitted: (value) {
                      provider.setLapLabel(value);
                    },
                    onEditingComplete: () {
                      provider.setLapLabel(_lapLabelController.text);
                    },
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    title: const Text('Mostrar milisegundos'),
                    subtitle: const Text('Exibir os dois últimos dígitos'),
                    trailing: Switch(
                      value: provider.showMilliseconds,
                      onChanged: (value) {
                        provider.setShowMilliseconds(value);
                      },
                    ),
                  ),
                  ListTile(
                    title: const Text('Mostrar horas'),
                    subtitle: const Text('Exibir o bloco de horas no cronômetro'),
                    trailing: Switch(
                      value: provider.showHours,
                      onChanged: (value) {
                        provider.setShowHours(value);
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 16),
                  const Text(
                    'Contagem regressiva',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    title: const Text('Ativar contagem regressiva'),
                    subtitle: const Text('Substitui o cronômetro por tempo restante'),
                    value: provider.isCountdownMode,
                    onChanged: (value) {
                      provider.setCountdownMode(value);
                    },
                  ),
                  if (provider.isCountdownMode) ...[
                    const Text('Tempo da contagem regressiva'),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _hoursController,
                            focusNode: _hoursFocus,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Horas',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onChanged: (_) => _applyCountdownFromFields(provider),
                            onFieldSubmitted: (_) => _applyCountdownFromFields(provider),
                            onEditingComplete: () => _applyCountdownFromFields(provider),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            controller: _minutesController,
                            focusNode: _minutesFocus,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Min',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onChanged: (_) => _applyCountdownFromFields(provider),
                            onFieldSubmitted: (_) => _applyCountdownFromFields(provider),
                            onEditingComplete: () => _applyCountdownFromFields(provider),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            controller: _secondsController,
                            focusNode: _secondsFocus,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Seg',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onChanged: (_) => _applyCountdownFromFields(provider),
                            onFieldSubmitted: (_) => _applyCountdownFromFields(provider),
                            onEditingComplete: () => _applyCountdownFromFields(provider),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      title: const Text('Vibrar ao terminar'),
                      value: provider.vibrateOnCountdownFinish,
                      onChanged: (value) {
                        provider.setVibrateOnCountdownFinish(value);
                      },
                    ),
                  ],
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 16),
                  const Text(
                    'Tema',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<ThemeMode>(
                    initialValue: provider.themeMode,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: ThemeMode.system,
                        child: Text('Sistema'),
                      ),
                      DropdownMenuItem(
                        value: ThemeMode.light,
                        child: Text('Claro'),
                      ),
                      DropdownMenuItem(
                        value: ThemeMode.dark,
                        child: Text('Escuro'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        provider.setThemeMode(value);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 16),
                  const Text(
                    'Janela flutuante',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    title: const Text('Modo Flutuante'),
                    subtitle: const Text(
                      'Exibir cronômetro flutuante sobre outros apps',
                    ),
                    trailing: Switch(
                      value: provider.showOverlay,
                      onChanged: (_) async {
                        await provider.toggleOverlay();
                      },
                    ),
                  ),
                  ExpansionTile(
                    title: const Text(
                      'Aparência da janela flutuante',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    children: [
                      const SizedBox(height: 8),
                      const Text('Cor de fundo (parado)'),
                      const SizedBox(height: 8),
                      _buildColorChips(
                        options: _overlayBgColors,
                        selected: provider.overlayStoppedBgColor,
                        onSelected: (color) async => await provider.setOverlayStoppedBgColor(color),
                      ),
                      const SizedBox(height: 12),
                      const Text('Cor de fundo (em execução)'),
                      const SizedBox(height: 8),
                      _buildColorChips(
                        options: _overlayBgColors,
                        selected: provider.overlayRunningBgColor,
                        onSelected: (color) async => await provider.setOverlayRunningBgColor(color),
                      ),
                      const SizedBox(height: 12),
                      const Text('Cor do texto da janela flutuante'),
                      const SizedBox(height: 8),
                      _buildColorChips(
                        options: _overlayTextColors,
                        selected: provider.overlayTextColor,
                        onSelected: (color) async => await provider.setOverlayTextColor(color),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Tamanho da fonte da janela flutuante'),
                          Text(provider.overlayFontSize.toStringAsFixed(0)),
                        ],
                      ),
                      Slider(
                        value: provider.overlayFontSize,
                        min: 20,
                        max: 50,
                        divisions: 12,
                        label: provider.overlayFontSize.toStringAsFixed(0),
                        onChanged: (value) {
                          provider.setOverlayFontSize(value);
                        },
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                  ListTile(
                    title: const Text('Resetar posicao da janela flutuante'),
                    subtitle: Text(
                      provider.showOverlay
                          ? 'Volta a posicao padrao do overlay'
                          : 'Ative o modo flutuante para usar esta opcao',
                    ),
                    trailing: const Icon(Icons.refresh),
                    onTap: provider.showOverlay
                        ? () async {
                            await AndroidOverlay.resetOverlayPosition();
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Posicao resetada.')),
                            );
                          }
                        : null,
                  ),
                  if (isAndroid) ...[
                    const SizedBox(height: 8),
                    ListTile(
                      title: const Text('Otimizacão de bateria'),
                      subtitle: const Text(
                        'Desative para manter o flutuante sempre no topo',
                      ),
                      trailing: const Icon(Icons.open_in_new),
                      onTap: () async {
                        await AndroidOverlay.openBatteryOptimizationSettings();
                      },
                    ),
                  ],
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 16),
                  const Text(
                    'Histórico',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    title: const Text('Apagar histórico de cronometragem'),
                    subtitle: const Text('Remove todo o histórico salvo de sessões cronometradas'),
                    trailing: const Icon(Icons.delete_outline),
                    onTap: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: const Text('Apagar histórico?'),
                          content: const Text('Essa ação não pode ser desfeita.'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Cancelar'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('Apagar'),
                            ),
                          ],
                        ),
                      );

                      if (confirm == true) {
                        provider.clearSessions();
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  ListTile(
                    title: const Text('Sobre'),
                    subtitle: FutureBuilder<PackageInfo>(
                      future: _packageInfo,
                      builder: (context, snapshot) {
                        final info = snapshot.data;
                        final versionLabel = info == null
                            ? 'Cronômetro'
                            : 'Cronômetro v${info.version}+${info.buildNumber}';
                        return Text(
                          versionLabel,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildColorChips({
    required List<_ColorOption> options,
    required Color selected,
    required ValueChanged<Color> onSelected,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((option) {
        final isSelected = selected.toARGB32() == option.color.toARGB32();
        final labelColor = option.color.computeLuminance() > 0.5 ? Colors.black : Colors.white;
        return ChoiceChip(
          label: Text(option.label),
          selected: isSelected,
          showCheckmark: true,
          checkmarkColor: labelColor,
          backgroundColor: option.color,
          selectedColor: option.color,
          labelStyle: TextStyle(color: labelColor),
          shape: StadiumBorder(
            side: isSelected
                ? const BorderSide(color: Colors.black87, width: 1.2)
                : BorderSide(color: Colors.black.withValues(alpha: 0.2)),
          ),
          onSelected: (_) => onSelected(option.color),
        );
      }).toList(),
    );
  }

  String _formatTwoDigits(int value) {
    return value.clamp(0, 99).toString().padLeft(2, '0');
  }
}

class _ColorOption {
  final String label;
  final Color color;

  const _ColorOption(this.label, this.color);
}
