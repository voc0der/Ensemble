import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import '../providers/music_assistant_provider.dart';
import '../services/debug_logger.dart';
import '../services/settings_service.dart';

/// Volume control widget for Music Assistant players
/// For local device: controls system media volume
/// For MA players: controls player volume via API
class VolumeControl extends StatefulWidget {
  final bool compact;

  const VolumeControl({super.key, this.compact = false});

  @override
  State<VolumeControl> createState() => _VolumeControlState();
}

class _VolumeControlState extends State<VolumeControl> {
  final _logger = DebugLogger();
  double? _pendingVolume;
  double? _systemVolume;
  StreamSubscription? _volumeListener;
  String? _localPlayerId;
  bool _isLocalPlayer = false;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _initLocalPlayer();
  }

  Future<void> _initLocalPlayer() async {
    _localPlayerId = await SettingsService.getBuiltinPlayerId();

    final volume = await FlutterVolumeController.getVolume();
    if (mounted) {
      setState(() {
        _systemVolume = volume;
      });
    }

    _volumeListener = FlutterVolumeController.addListener((volume) {
      if (mounted && _isLocalPlayer) {
        setState(() {
          _systemVolume = volume;
        });
      }
    });
  }

  @override
  void dispose() {
    _volumeListener?.cancel();
    super.dispose();
  }

  Future<void> _adjustVolume(MusicAssistantProvider maProvider, String playerId, double currentVolume, int delta) async {
    final newVolume = ((currentVolume * 100).round() + delta).clamp(0, 100);

    if (_isLocalPlayer) {
      _logger.log('Volume: Setting system volume to $newVolume%');
      try {
        await FlutterVolumeController.setVolume(newVolume / 100.0);
        if (mounted) {
          setState(() {
            _systemVolume = newVolume / 100.0;
          });
        }
      } catch (e) {
        _logger.log('Volume: Error setting system volume - $e');
      }
    } else {
      _logger.log('Volume: Setting to $newVolume%');
      try {
        await maProvider.setVolume(playerId, newVolume);
      } catch (e) {
        _logger.log('Volume: Error - $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final maProvider = context.watch<MusicAssistantProvider>();
    final player = maProvider.selectedPlayer;

    if (player == null) {
      return const SizedBox.shrink();
    }

    _isLocalPlayer = _localPlayerId != null && player.playerId == _localPlayerId;

    final currentVolume = _isLocalPlayer
        ? (_pendingVolume ?? (_systemVolume ?? 0.5))
        : (_pendingVolume ?? player.volume.toDouble()) / 100.0;

    if (widget.compact) {
      return IconButton(
        icon: Icon(
          currentVolume < 0.01
              ? Icons.volume_off
              : currentVolume < 0.3
                  ? Icons.volume_down
                  : Icons.volume_up,
          color: Colors.white70,
        ),
        onPressed: () async {
          // In compact mode, toggle between 0 and 50%
          final newVolume = currentVolume < 0.01 ? 50 : 0;
          await _adjustVolume(maProvider, player.playerId, newVolume / 100.0, 0);
        },
      );
    }

    return Row(
      children: [
        // Volume decrease button
        IconButton(
          icon: const Icon(
            Icons.volume_down,
            color: Colors.white70,
          ),
          onPressed: () => _adjustVolume(maProvider, player.playerId, currentVolume, -1),
        ),
        // Slider with floating percentage indicator
        Expanded(
          child: SizedBox(
            height: 48,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final sliderWidth = constraints.maxWidth;
                final thumbPosition = currentVolume.clamp(0.0, 1.0) * sliderWidth;

                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // The slider
                    SliderTheme(
                      data: SliderThemeData(
                        trackHeight: 2,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
                        activeTrackColor: Colors.white,
                        inactiveTrackColor: Colors.white.withOpacity(0.3),
                        thumbColor: Colors.white,
                        overlayColor: Colors.white.withOpacity(0.2),
                      ),
                      child: Slider(
                        value: currentVolume.clamp(0.0, 1.0),
                        onChangeStart: (_) {
                          setState(() => _isDragging = true);
                        },
                        onChanged: (value) {
                          setState(() {
                            _pendingVolume = _isLocalPlayer ? value : value * 100;
                          });
                        },
                        onChangeEnd: (value) async {
                          setState(() => _isDragging = false);

                          if (_isLocalPlayer) {
                            _logger.log('Volume: Setting system volume to ${(value * 100).round()}%');
                            try {
                              await FlutterVolumeController.setVolume(value);
                              _systemVolume = value;
                            } catch (e) {
                              _logger.log('Volume: Error setting system volume - $e');
                            } finally {
                              if (mounted) {
                                setState(() {
                                  _pendingVolume = null;
                                });
                              }
                            }
                          } else {
                            final volumeLevel = (value * 100).round();
                            _logger.log('Volume: Setting to $volumeLevel%');
                            try {
                              await maProvider.setVolume(player.playerId, volumeLevel);
                              _logger.log('Volume: Set to $volumeLevel%');
                            } catch (e) {
                              _logger.log('Volume: Error - $e');
                            } finally {
                              if (mounted) {
                                setState(() {
                                  _pendingVolume = null;
                                });
                              }
                            }
                          }
                        },
                      ),
                    ),
                    // Floating percentage indicator (only visible when dragging)
                    if (_isDragging)
                      Positioned(
                        left: thumbPosition - 20, // Center the indicator above thumb
                        top: -4,
                        child: Container(
                          width: 40,
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${(currentVolume * 100).round()}%',
                            style: const TextStyle(
                              color: Colors.black87,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
        // Volume increase button
        IconButton(
          icon: const Icon(
            Icons.volume_up,
            color: Colors.white70,
          ),
          onPressed: () => _adjustVolume(maProvider, player.playerId, currentVolume, 1),
        ),
      ],
    );
  }
}
