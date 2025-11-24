import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/debug_logger.dart';
import '../providers/music_assistant_provider.dart';
import '../models/player.dart';

class DebugLogScreen extends StatefulWidget {
  const DebugLogScreen({super.key});

  @override
  State<DebugLogScreen> createState() => _DebugLogScreenState();
}

class _DebugLogScreenState extends State<DebugLogScreen> {
  final _logger = DebugLogger();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // Auto-scroll to bottom when opening
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _copyLogs() {
    Clipboard.setData(ClipboardData(text: _logger.getAllLogs()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Logs copied to clipboard!'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _clearLogs() {
    setState(() {
      _logger.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Logs cleared'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  Future<void> _showAllPlayers() async {
    final maProvider = context.read<MusicAssistantProvider>();

    try {
      final allPlayers = await maProvider.getAllPlayersUnfiltered();

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF2a2a2a),
          title: const Text(
            'All Players (Including Hidden)',
            style: TextStyle(color: Colors.white),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: allPlayers.length,
              itemBuilder: (context, index) {
                final player = allPlayers[index];
                final isGhost = player.name.toLowerCase().contains('music assistant mobile');

                return Card(
                  color: isGhost ? Colors.red.withOpacity(0.2) : Colors.white.withOpacity(0.1),
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(
                      player.name,
                      style: TextStyle(
                        color: isGhost ? Colors.red[300] : Colors.white,
                        fontWeight: isGhost ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ID: ${player.playerId}',
                          style: const TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                        Text(
                          'Available: ${player.available} | State: ${player.state}',
                          style: const TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                      ],
                    ),
                    trailing: isGhost
                        ? const Icon(Icons.warning, color: Colors.red, size: 20)
                        : null,
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                final text = allPlayers.map((p) =>
                  'Name: ${p.name}\nID: ${p.playerId}\nAvailable: ${p.available}\nState: ${p.state}\n---'
                ).join('\n');
                await Clipboard.setData(ClipboardData(text: text));
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Player list copied to clipboard!')),
                  );
                }
              },
              child: const Text('Copy List'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading players: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1a1a1a),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
          color: Colors.white,
        ),
        title: const Text(
          'Debug Logs',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w300,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.speaker_group_rounded),
            onPressed: _showAllPlayers,
            color: Colors.white,
            tooltip: 'View all players',
          ),
          IconButton(
            icon: const Icon(Icons.copy_rounded),
            onPressed: _copyLogs,
            color: Colors.white,
            tooltip: 'Copy logs',
          ),
          IconButton(
            icon: const Icon(Icons.delete_rounded),
            onPressed: _clearLogs,
            color: Colors.white,
            tooltip: 'Clear logs',
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white.withOpacity(0.05),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  color: Colors.white70,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Last ${_logger.logs.length} log entries',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _logger.logs.isEmpty
                ? const Center(
                    child: Text(
                      'No logs yet',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 16,
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(8),
                    itemCount: _logger.logs.length,
                    itemBuilder: (context, index) {
                      final log = _logger.logs[index];
                      final isError = log.contains('Error') ||
                          log.contains('error') ||
                          log.contains('ERROR') ||
                          log.contains('failed') ||
                          log.contains('Failed');

                      return Container(
                        margin: const EdgeInsets.only(bottom: 4),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isError
                              ? Colors.red.withOpacity(0.1)
                              : Colors.white.withOpacity(0.03),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: isError
                                ? Colors.red.withOpacity(0.3)
                                : Colors.white.withOpacity(0.1),
                          ),
                        ),
                        child: Text(
                          log,
                          style: TextStyle(
                            color: isError ? Colors.red[300] : Colors.white70,
                            fontSize: 11,
                            fontFamily: 'monospace',
                            height: 1.4,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          setState(() {});
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        },
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1a1a1a),
        child: const Icon(Icons.refresh_rounded),
      ),
    );
  }
}
