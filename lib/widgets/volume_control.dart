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
    final isMuted = _isLocalPlayer ? false : player.isMuted;

    if (widget.compact) {
      return IconButton(
        icon: Icon(
          isMuted ? Icons.volume_off : Icons.volume_up,
          color: Colors.white70,
        ),
        onPressed: () async {
          try {
            await maProvider.setMute(player.playerId, !isMuted);
          } catch (e) {
            // Error already logged by provider
          }
        },
      );
    }

    return Row(
      children: [
        IconButton(
          icon: Icon(
            isMuted
                ? Icons.volume_off
                : currentVolume < 0.3
                    ? Icons.volume_down
                    : Icons.volume_up,
            color: Colors.white70,
          ),
          onPressed: () async {
            try {
              await maProvider.setMute(player.playerId, !isMuted);
            } catch (e) {
              // Error already logged by provider
            }
          },
        ),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              activeTrackColor: Colors.white,
              inactiveTrackColor: Colors.white.withOpacity(0.3),
              thumbColor: Colors.white,
              overlayColor: Colors.white.withOpacity(0.2),
            ),
            child: Slider(
              value: currentVolume.clamp(0.0, 1.0),
              onChanged: (value) {
                setState(() {
                  _pendingVolume = _isLocalPlayer ? value : value * 100;
                });
              },
              onChangeEnd: (value) async {
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
                    if (isMuted) {
                      _logger.log('Volume: Unmuting player first');
                      await maProvider.setMute(player.playerId, false);
                    }
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
        ),
        SizedBox(
          width: 40,
          child: Text(
            '${(currentVolume * 100).round()}%',
            style: TextStyle(
              color: Colors.grey[400],
              fontSize: 12,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}
