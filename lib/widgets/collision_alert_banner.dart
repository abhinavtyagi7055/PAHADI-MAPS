import 'package:flutter/material.dart';
import '../models/telemetry_model.dart';

/// High-Urgency Flashing Collision Warning Banner / Modal
class CollisionAlertBanner extends StatefulWidget {
  final CollisionAlert alert;
  final VoidCallback onDismiss;

  const CollisionAlertBanner({
    super.key,
    required this.alert,
    required this.onDismiss,
  });

  @override
  State<CollisionAlertBanner> createState() => _CollisionAlertBannerState();
}

class _CollisionAlertBannerState extends State<CollisionAlertBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    // Fast pulsing hazard animation (500ms cycle)
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);

    _glowAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final alert = widget.alert;
    final isCritical = alert.isCritical;
    final primaryColor = isCritical ? const Color(0xFFFF0055) : const Color(0xFFFF9500);

    return AnimatedBuilder(
      animation: _glowAnimation,
      builder: (context, child) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF0F0B13).withOpacity(0.96),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: primaryColor.withOpacity(_glowAnimation.value),
              width: isCritical ? 2.5 : 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: primaryColor.withOpacity(0.35 * _glowAnimation.value),
                blurRadius: 18 * _glowAnimation.value,
                spreadRadius: 2,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Top Header Strip
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  color: primaryColor.withOpacity(0.2),
                  child: Row(
                    children: [
                      Icon(
                        isCritical ? Icons.warning_rounded : Icons.info_outline_rounded,
                        color: primaryColor,
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isCritical
                              ? 'CRITICAL BLIND-SPOT COLLISION ALERT'
                              : 'PREDICTIVE PROXIMITY WARNING',
                          style: TextStyle(
                            color: primaryColor,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.1,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      // Hazard zone tag
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: primaryColor.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'ZONE: ${alert.blindSpotName.split(' ').first}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      InkWell(
                        onTap: widget.onDismiss,
                        child: const Icon(Icons.close, color: Colors.white70, size: 20),
                      ),
                    ],
                  ),
                ),

                // Main Metric Row
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          // Time-To-Collision (TTC) Countdown
                          _buildMetricColumn(
                            title: 'TIME-TO-COLLISION',
                            value: '${alert.ttc.toStringAsFixed(1)}s',
                            highlightColor: primaryColor,
                            isLarge: true,
                          ),
                          Container(
                            height: 45,
                            width: 1,
                            color: Colors.white12,
                          ),
                          // Relative Closing Velocity
                          _buildMetricColumn(
                            title: 'CLOSING SPEED',
                            value: '${alert.closingSpeedKmh.toStringAsFixed(0)} km/h',
                            highlightColor: const Color(0xFF00F0FF),
                            subtext: 'Rel: ${alert.relativeSpeedKmh.toStringAsFixed(0)} km/h',
                          ),
                          Container(
                            height: 45,
                            width: 1,
                            color: Colors.white12,
                          ),
                          // Separation Distance
                          _buildMetricColumn(
                            title: 'SEPARATION',
                            value: '${alert.currentDistanceMeters.toStringAsFixed(0)} m',
                            highlightColor: const Color(0xFFFFB703),
                            subtext: 'CPA: ${alert.cpaDistanceMeters.toStringAsFixed(1)}m',
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),
                      
                      // Advisory Banner
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: primaryColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: primaryColor.withOpacity(0.4)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.volume_up_rounded, color: primaryColor, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                alert.advisory,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMetricColumn({
    required String title,
    required String value,
    required Color highlightColor,
    bool isLarge = false,
    String? subtext,
  }) {
    return Column(
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white60,
            fontSize: 9.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: TextStyle(
            color: highlightColor,
            fontSize: isLarge ? 26 : 18,
            fontWeight: FontWeight.w900,
            fontFamily: 'monospace',
          ),
        ),
        if (subtext != null) ...[
          const SizedBox(height: 1),
          Text(
            subtext,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 9,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ],
    );
  }
}
