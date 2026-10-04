import 'package:flutter/material.dart';
import '../models/telemetry_model.dart';

/// Futuristic High-Contrast Cockpit HUD Overlay
class HudOverlay extends StatelessWidget {
  final bool isConnected;
  final int latencyMs;
  final List<VehicleTelemetry> vehicles;
  final CollisionAlert? activeAlert;
  final BlindSpotZone? currentZone;
  final String serverUrl;
  final VoidCallback onFocusZone;
  final VoidCallback onToggleDemo;
  final bool isDemoRunning;
  final Function(String) onUpdateServerUrl;

  const HudOverlay({
    super.key,
    required this.isConnected,
    required this.latencyMs,
    required this.vehicles,
    required this.activeAlert,
    this.currentZone,
    required this.serverUrl,
    required this.onFocusZone,
    required this.onToggleDemo,
    required this.isDemoRunning,
    required this.onUpdateServerUrl,
  });

  @override
  Widget build(BuildContext context) {
    // Select primary vehicle (e.g. vehicle_alpha or first vehicle)
    final primaryVehicle = vehicles.isNotEmpty ? vehicles.first : null;
    final secondaryVehicle = vehicles.length > 1 ? vehicles[1] : null;

    return SafeArea(
      child: Column(
        children: [
          // Top System Status Bar
          _buildTopBar(context),

          const Spacer(),

          // Bottom Instrumentation Cockpit
          _buildBottomCockpit(context, primaryVehicle, secondaryVehicle),
        ],
      ),
    );
  }

  /// Top System Status Bar
  Widget _buildTopBar(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF090D16).withOpacity(0.88),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF00F0FF).withOpacity(0.3), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 10,
          )
        ],
      ),
      child: Row(
        children: [
          // Telemetry Guard Branding & Status Dot
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isConnected ? const Color(0xFF00FF66) : const Color(0xFFFF3366),
              boxShadow: [
                BoxShadow(
                  color: (isConnected ? const Color(0xFF00FF66) : const Color(0xFFFF3366))
                      .withOpacity(0.8),
                  blurRadius: 6,
                  spreadRadius: 1,
                )
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'PAHADI TELEMETRY GUARD',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),
              Text(
                isConnected ? 'V2V SATELLITE RADAR ONLINE' : 'DISCONNECTED - RECONNECTING...',
                style: TextStyle(
                  color: isConnected ? const Color(0xFF00F0FF) : Colors.white54,
                  fontSize: 8.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),

          const Spacer(),

          // Active Entities Count
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.white12),
            ),
            child: Row(
              children: [
                const Icon(Icons.radar_rounded, color: Color(0xFF00F0FF), size: 14),
                const SizedBox(width: 4),
                Text(
                  '${vehicles.length} TARGETS',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9.5,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 8),

          // Latency Ping
          if (isConnected)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${latencyMs > 0 ? latencyMs : 12}ms',
                style: const TextStyle(
                  color: Color(0xFF00FF66),
                  fontSize: 9,
                  fontFamily: 'monospace',
                ),
              ),
            ),

          const SizedBox(width: 8),

          // Settings Button
          InkWell(
            onTap: () => _showServerConfigDialog(context),
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.settings_outlined, color: Colors.white70, size: 16),
            ),
          ),
        ],
      ),
    );
  }

  /// Bottom Instrumentation Deck
  Widget _buildBottomCockpit(
    BuildContext context,
    VehicleTelemetry? primary,
    VehicleTelemetry? secondary,
  ) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF090D16).withOpacity(0.92),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF00F0FF).withOpacity(0.35), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.6),
            blurRadius: 16,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Row 1: Primary Telemetry Gauges
          Row(
            children: [
              // Speedometer
              Expanded(
                flex: 3,
                child: _buildInstrumentCard(
                  title: 'TRACKED SPEED',
                  value: primary != null ? primary.speed.toStringAsFixed(0) : '--',
                  unit: 'KM/H',
                  accentColor: const Color(0xFF00F0FF),
                  icon: Icons.speed_rounded,
                  subtitle: primary?.deviceId ?? 'NO TARGET',
                ),
              ),
              const SizedBox(width: 8),

              // Relative Closing Speed
              Expanded(
                flex: 4,
                child: _buildInstrumentCard(
                  title: 'RELATIVE CLOSING SPEED',
                  value: activeAlert != null
                      ? activeAlert!.closingSpeedKmh.toStringAsFixed(0)
                      : (primary != null && secondary != null ? 'CLOSING' : '--'),
                  unit: 'KM/H',
                  accentColor: activeAlert != null
                      ? const Color(0xFFFF0055)
                      : const Color(0xFFFFB703),
                  icon: Icons.compare_arrows_rounded,
                  subtitle: activeAlert != null
                      ? 'TTC: ${activeAlert!.ttc.toStringAsFixed(1)}s'
                      : 'NORMAL HEADWAY',
                ),
              ),
              const SizedBox(width: 8),

              // Compass Heading
              Expanded(
                flex: 3,
                child: _buildInstrumentCard(
                  title: 'BEARING',
                  value: primary != null ? '${primary.heading.toStringAsFixed(0)}°' : '--°',
                  unit: _getCardinalDirection(primary?.heading ?? 0),
                  accentColor: const Color(0xFF00FF66),
                  icon: Icons.explore_rounded,
                  subtitle: 'ELEV: 3240m',
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Row 2: Tactical Action Toolbar
          Row(
            children: [
              // Blind Spot Status Badge
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF131B2E),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.terrain_rounded, color: Color(0xFFFFB703), size: 16),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          currentZone != null
                              ? 'ZONE ARMED: ${currentZone!.name.split('(').first}'
                              : 'ROHTANG PASS KM-42 HAIRPIN',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(width: 8),

              // Focus Camera Button
              InkWell(
                onTap: onFocusZone,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00F0FF).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF00F0FF).withOpacity(0.5)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.center_focus_strong_rounded,
                          color: Color(0xFF00F0FF), size: 14),
                      SizedBox(width: 4),
                      Text(
                        'FOCUS CURVE',
                        style: TextStyle(
                          color: Color(0xFF00F0FF),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(width: 8),

              // Toggle Simulation Button
              InkWell(
                onTap: onToggleDemo,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDemoRunning
                        ? const Color(0xFFFF0055).withOpacity(0.2)
                        : const Color(0xFF00FF66).withOpacity(0.18),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isDemoRunning
                          ? const Color(0xFFFF0055).withOpacity(0.6)
                          : const Color(0xFF00FF66).withOpacity(0.6),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isDemoRunning ? Icons.stop_rounded : Icons.play_arrow_rounded,
                        color: isDemoRunning ? const Color(0xFFFF0055) : const Color(0xFF00FF66),
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isDemoRunning ? 'HALT SIM' : 'LIVE DEMO',
                        style: TextStyle(
                          color: isDemoRunning ? const Color(0xFFFF0055) : const Color(0xFF00FF66),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInstrumentCard({
    required String title,
    required String value,
    required String unit,
    required Color accentColor,
    required IconData icon,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF101625),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: accentColor, size: 12),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 8,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: TextStyle(
                  color: accentColor,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(width: 3),
              Text(
                unit,
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 8.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 8,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  String _getCardinalDirection(double heading) {
    const directions = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    final idx = ((heading + 22.5) % 360) ~/ 45;
    return directions[idx];
  }

  void _showServerConfigDialog(BuildContext context) {
    final controller = TextEditingController(text: serverUrl);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        title: const Text(
          'Backend Server Configuration',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Set Node.js WebSocket Host URL:\n'
              '• Web / Desktop: http://localhost:3000\n'
              '• Android Emulator: http://10.0.2.2:3000\n'
              '• Physical Device: http://<LAN-IP>:3000',
              style: TextStyle(color: Colors.white70, fontSize: 11, height: 1.4),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white, fontFamily: 'monospace'),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFF1E293B),
                hintText: 'http://localhost:3000',
                hintStyle: const TextStyle(color: Colors.white30),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00F0FF)),
            onPressed: () {
              onUpdateServerUrl(controller.text.trim());
              Navigator.pop(ctx);
            },
            child: const Text('Connect', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }
}
