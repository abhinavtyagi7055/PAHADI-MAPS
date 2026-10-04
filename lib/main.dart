import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'services/browser_notifications.dart';

const _roadMapAspectRatio = 1.22;
const _mapCameraTarget = LatLng(32.37275, 77.2473);
const _mapZoom = 16.0;
const _initialCollisionProgress = 0.68;
const _minimumCollisionProgress = 0.1;
const _maximumCollisionProgress = 0.9;
const _minimumTightCurveTurnDegrees = 45.0;
const _curveMeasurementWindowMeters = 25.0;
const _maximumBendApproachDistanceMeters = 75.0;
const _maximumVehicleSeparationMeters = 120.0;
const _mapStyle = r'''
{
  "version": 8,
  "glyphs": "https://demotiles.maplibre.org/font/{fontstack}/{range}.pbf",
  "sources": {},
  "layers": [
    {
      "id": "background",
      "type": "background",
      "paint": { "background-color": "#1B2D2C" }
    }
  ]
}
''';

const demoRoadRoute = <LatLng>[
  LatLng(32.3742, 77.2460),
  LatLng(32.3736, 77.2462),
  LatLng(32.3730, 77.2464),
  LatLng(32.3724, 77.2467),
  LatLng(32.3719, 77.2470),
  LatLng(32.3716, 77.2472),
  LatLng(32.3714, 77.2474),
  LatLng(32.3713, 77.2476),
  LatLng(32.3714, 77.2480),
  LatLng(32.3718, 77.2484),
  LatLng(32.3724, 77.2486),
];

final _bravoRoute = demoRoadRoute.reversed.toList(growable: false);

void main() {
  runApp(const PahadiSafetyApp());
}

class PahadiSafetyApp extends StatelessWidget {
  const PahadiSafetyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Pahadi Maps',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF47D7AC),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0B1113),
        useMaterial3: true,
      ),
      home: const CollisionMapScreen(),
    );
  }
}

class CollisionMapScreen extends StatefulWidget {
  const CollisionMapScreen({super.key});

  @override
  State<CollisionMapScreen> createState() => _CollisionMapScreenState();
}

class _CollisionMapScreenState extends State<CollisionMapScreen> {
  static const _green = Color(0xFF47D7AC);
  static const _amber = Color(0xFFFFB454);
  static const _red = Color(0xFFFF5B62);

  Timer? _simulationTimer;
  MapLibreMapController? _controller;
  double _progress = 0;
  double _collisionProgress = _initialCollisionProgress;
  int _collisionHoldTicks = 0;
  bool _isRunning = false;
  bool _isAtRisk = false;
  bool _alertHandledThisPass = false;
  bool _notificationsAllowed = false;
  double? _alphaBearing;
  double? _bravoBearing;

  @override
  void dispose() {
    _simulationTimer?.cancel();
    super.dispose();
  }

  Future<void> _startSimulation() async {
    if (_isRunning) return;

    setState(() {
      _progress = 0;
      _collisionHoldTicks = 0;
      _isAtRisk = false;
      _alertHandledThisPass = false;
      _isRunning = true;
      _alphaBearing = sampleRoute(demoRoadRoute, 0).bearing;
      _bravoBearing = sampleRoute(_bravoRoute, 0).bearing;
    });
    _showMessage('Demo started. Allow browser notifications if prompted.');

    _simulationTimer?.cancel();
    _simulationTimer = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => _advanceSimulation(),
    );

    try {
      _notificationsAllowed = await requestBrowserNotificationPermission();
    } catch (error) {
      _notificationsAllowed = false;
      _showMessage('Demo is running, but browser notifications failed: $error');
    }
    if (!mounted || !_isRunning) return;
    if (_notificationsAllowed) {
      _showMessage('Browser alerts are enabled.');
    } else {
      _showMessage(
        'Demo is running. Allow browser notifications to receive alerts.',
      );
    }
  }

  void _advanceSimulation() {
    if (!mounted) return;
    String? collisionMessage;
    var shouldNotify = false;
    setState(() {
      if (_progress < _collisionProgress) {
        _progress = (_progress + 0.01).clamp(0, _collisionProgress);
      } else {
        _collisionHoldTicks++;
        if (_collisionHoldTicks >= 18) {
          _progress = 0;
          _collisionHoldTicks = 0;
          _isAtRisk = false;
          _alertHandledThisPass = false;
        }
      }

      final alphaSample = sampleRoute(demoRoadRoute, _progress);
      final bravoProgress = bravoRouteProgressForCollision(
        _progress,
        _collisionProgress,
      );
      final bravoSample = sampleRoute(_bravoRoute, bravoProgress);
      collisionMessage = collisionNotificationText(
        demoRoadRoute,
        _progress,
        bravoProgress,
      );
      _isAtRisk = collisionMessage != null;
      _alphaBearing = smoothBearingDegrees(
        _alphaBearing ?? alphaSample.bearing,
        alphaSample.bearing,
      );
      _bravoBearing = smoothBearingDegrees(
        _bravoBearing ?? bravoSample.bearing,
        bravoSample.bearing,
      );
      if (collisionMessage != null && !_alertHandledThisPass) {
        _alertHandledThisPass = true;
        shouldNotify = true;
      }
    });
    final message = collisionMessage;
    if (message != null && shouldNotify) {
      if (_notificationsAllowed) {
        showBrowserNotification(
          'Collision warning — Rohtang Pass',
          message,
        );
      }
      _showMessage(message);
    }
  }

  void _onMapCreated(MapLibreMapController controller) {
    _controller = controller;
  }

  Future<void> _onStyleLoaded() async {
    final controller = _controller;
    if (controller == null) return;

    try {
      await controller.addLine(
        const LineOptions(
          geometry: demoRoadRoute,
          lineColor: '#10191B',
          lineWidth: 14,
          lineJoin: 'round',
        ),
      );
      await controller.addLine(
        const LineOptions(
          geometry: demoRoadRoute,
          lineColor: '#69746A',
          lineWidth: 10,
          lineJoin: 'round',
        ),
      );
      await controller.addLine(
        const LineOptions(
          geometry: demoRoadRoute,
          lineColor: '#D5C89B',
          lineWidth: 0.7,
          lineJoin: 'round',
        ),
      );
    } catch (error) {
      _showMessage('Could not initialize the MapLibre route: $error');
    }
  }

  void _stopSimulation() {
    _simulationTimer?.cancel();
    setState(() {
      _isRunning = false;
      _isAtRisk = false;
      _progress = 0;
      _collisionHoldTicks = 0;
      _alertHandledThisPass = false;
      _alphaBearing = sampleRoute(demoRoadRoute, 0).bearing;
      _bravoBearing = sampleRoute(_bravoRoute, 0).bearing;
    });
    _showMessage('Collision demo stopped.');
  }

  void _setCollisionProgress(double progress) {
    setState(() {
      _collisionProgress = progress;
      _progress = 0;
      _collisionHoldTicks = 0;
      _isAtRisk = false;
      _alertHandledThisPass = false;
      _alphaBearing = sampleRoute(demoRoadRoute, 0).bearing;
      _bravoBearing = sampleRoute(_bravoRoute, 0).bearing;
    });
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final alertColor = _isAtRisk ? _red : _green;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF10191B),
        titleSpacing: 20,
        title: const Row(
          children: [
            Text(
              'PAHADI ',
              style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2),
            ),
            ClipRRect(
              borderRadius: BorderRadius.all(Radius.circular(4)),
              child: Image(
                image: AssetImage('assets/pahadi_mountains.png'),
                width: 30,
                height: 22,
                fit: BoxFit.contain,
              ),
            ),
            SizedBox(width: 1),
            Text(
              'APS',
              style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 18),
            child: Center(
              child: _StatusPill(
                label: _isAtRisk ? 'COLLISION RISK' : 'ROAD CLEAR',
                color: alertColor,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 820;
            return SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: isWide ? 32 : 16,
                vertical: 20,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1280),
                  child: isWide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 7, child: _buildMap(alertColor)),
                            const SizedBox(width: 24),
                            SizedBox(
                                width: 310, child: _buildControls(alertColor)),
                          ],
                        )
                      : Column(
                          children: [
                            _buildMap(alertColor),
                            const SizedBox(height: 18),
                            _buildControls(alertColor),
                          ],
                        ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildMap(Color alertColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'LIVE ROAD MAP',
          style: TextStyle(
            color: Color(0xFF9AA9A6),
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.8,
          ),
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: AspectRatio(
            aspectRatio: _roadMapAspectRatio,
            child: Stack(
              fit: StackFit.expand,
              children: [
                MapLibreMap(
                  key: const ValueKey('rohtang-map'),
                  styleString: _mapStyle,
                  initialCameraPosition: const CameraPosition(
                    target: _mapCameraTarget,
                    zoom: _mapZoom,
                  ),
                  onMapCreated: _onMapCreated,
                  onStyleLoadedCallback: _onStyleLoaded,
                  rotateGesturesEnabled: false,
                  scrollGesturesEnabled: false,
                  zoomGesturesEnabled: false,
                  tiltGesturesEnabled: false,
                  dragEnabled: false,
                ),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final mapSize = Size(
                      constraints.maxWidth,
                      constraints.maxHeight,
                    );
                    final alphaSample = sampleRoute(demoRoadRoute, _progress);
                    final bravoProgress = bravoRouteProgressForCollision(
                      _progress,
                      _collisionProgress,
                    );
                    final bravoSample = sampleRoute(_bravoRoute, bravoProgress);
                    final alphaPosition = projectCoordinateToScreen(
                      alphaSample.position,
                      mapSize,
                    );
                    final bravoPosition = projectCoordinateToScreen(
                      bravoSample.position,
                      mapSize,
                    );

                    return Stack(
                      children: [
                        Positioned(
                          left: alphaPosition.dx - 42,
                          top: alphaPosition.dy - 18,
                          child: _vehicleMarker(
                            label: 'ALPHA',
                            color: _green,
                            bearing: _alphaBearing ?? alphaSample.bearing,
                          ),
                        ),
                        Positioned(
                          left: bravoPosition.dx - 42,
                          top: bravoPosition.dy - 18,
                          child: _vehicleMarker(
                            label: 'BRAVO',
                            color: _amber,
                            bearing: _bravoBearing ?? bravoSample.bearing,
                          ),
                        ),
                      ],
                    );
                  },
                ),
                Positioned(
                  left: 18,
                  top: 18,
                  child: _mapLabel(
                    'ROHTANG PASS',
                    'HIMACHAL PRADESH',
                    Icons.terrain,
                  ),
                ),
                Positioned(
                  right: 18,
                  top: 18,
                  child: _coordinateTag('32.3715° N', '77.2472° E'),
                ),
                Positioned(
                  left: 18,
                  bottom: 18,
                  child: _StatusPill(
                    label: _isAtRisk
                        ? 'BLIND BEND · COLLISION IMMINENT'
                        : 'BLIND BEND · 180 m AHEAD',
                    color: alertColor,
                  ),
                ),
                Positioned(
                  right: 18,
                  bottom: 18,
                  child: _compass(),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Row(
          children: [
            Icon(Icons.info_outline, size: 15, color: Color(0xFF7C8D89)),
            SizedBox(width: 7),
            Expanded(
              child: Text(
                'MapLibre road map · vehicle arrows follow route bearings',
                style: TextStyle(color: Color(0xFF7C8D89), fontSize: 12),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildControls(Color alertColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'APPROACHING VEHICLES',
          style: TextStyle(
            color: Color(0xFF9AA9A6),
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.8,
          ),
        ),
        const SizedBox(height: 10),
        _vehicleCard(
          name: 'VEHICLE ALPHA',
          description: 'Descending · Heavy truck',
          speed: '16 km/h',
          color: _green,
          direction: Icons.south_east,
        ),
        const SizedBox(height: 10),
        _vehicleCard(
          name: 'VEHICLE BRAVO',
          description: 'Climbing · SUV',
          speed: '14 km/h',
          color: _amber,
          direction: Icons.north_west,
        ),
        const SizedBox(height: 14),
        _meetingPointControl(),
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF141D1F),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: _isAtRisk
                  ? _red.withValues(alpha: 0.65)
                  : const Color(0xFF273638),
            ),
          ),
          child: Row(
            children: [
              Icon(
                _isAtRisk ? Icons.warning_amber_rounded : Icons.shield_outlined,
                color: alertColor,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isAtRisk ? 'COLLISION WARNING' : 'PREDICTIVE SAFETY',
                      style: TextStyle(
                        color: alertColor,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _isAtRisk
                          ? 'Vehicles are nearing the blind bend.'
                          : 'Watch for vehicles converging at the bend.',
                      style: const TextStyle(
                        color: Color(0xFFB1BFBB),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          height: 54,
          child: FilledButton.icon(
            onPressed: _isRunning ? _stopSimulation : _startSimulation,
            style: FilledButton.styleFrom(
              backgroundColor: _isRunning ? const Color(0xFF273638) : _green,
              foregroundColor:
                  _isRunning ? Colors.white : const Color(0xFF07120F),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: Icon(
                _isRunning ? Icons.stop_rounded : Icons.play_arrow_rounded),
            label: Text(
              _isRunning ? 'STOP SIMULATION' : 'START COLLISION DEMO',
              style: const TextStyle(
                  fontWeight: FontWeight.w900, letterSpacing: 0.6),
            ),
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Starting the demo asks for browser notification permission. '
          'A notification is sent when the cars approach the blind bend.',
          style: TextStyle(
            color: Color(0xFF7C8D89),
            fontSize: 12,
            height: 1.45,
          ),
        ),
      ],
    );
  }

  Widget _meetingPointControl() {
    final percentage = (_collisionProgress * 100).round();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      decoration: BoxDecoration(
        color: const Color(0xFF141D1F),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF273638)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'VEHICLE MEETING POINT',
                  style: TextStyle(
                    color: Color(0xFF9AA9A6),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              Text(
                '$percentage%',
                style: const TextStyle(
                  color: _green,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          Slider(
            key: const ValueKey('collision-meeting-point-slider'),
            min: _minimumCollisionProgress,
            max: _maximumCollisionProgress,
            divisions: 80,
            value: _collisionProgress,
            label: '$percentage%',
            onChanged: _setCollisionProgress,
          ),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'ALPHA START',
                style: TextStyle(
                  color: Color(0xFF7C8D89),
                  fontSize: 9,
                  letterSpacing: 0.7,
                ),
              ),
              Text(
                'BRAVO START',
                style: TextStyle(
                  color: Color(0xFF7C8D89),
                  fontSize: 9,
                  letterSpacing: 0.7,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Adjust where the vehicles converge along the road.',
            style: TextStyle(color: Color(0xFF7C8D89), fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _vehicleCard({
    required String name,
    required String description,
    required String speed,
    required Color color,
    required IconData direction,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
      decoration: BoxDecoration(
        color: const Color(0xFF141D1F),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF273638)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(direction, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style:
                      const TextStyle(color: Color(0xFF9AA9A6), fontSize: 11),
                ),
              ],
            ),
          ),
          Text(
            speed,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _mapLabel(String title, String subtitle, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xDD10191B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: _green, size: 20),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style:
                    const TextStyle(fontSize: 10, fontWeight: FontWeight.w900),
              ),
              Text(
                subtitle,
                style: const TextStyle(
                  color: Color(0xFF9AA9A6),
                  fontSize: 8,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _vehicleMarker({
    required String label,
    required Color color,
    required double bearing,
  }) {
    return SizedBox(
      width: 84,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFF0B1113),
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 2),
              boxShadow: [
                BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 16),
              ],
            ),
            child: Transform.rotate(
              angle: bearing * math.pi / 180,
              child: CustomPaint(
                size: const Size.square(24),
                painter: _VehicleArrowPainter(color),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xEE0B1113),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 9,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _coordinateTag(String latitude, String longitude) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xDD10191B),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Text(
        '$latitude\n$longitude',
        textAlign: TextAlign.right,
        style: const TextStyle(
          color: Color(0xFFD3DEDA),
          fontSize: 9,
          height: 1.5,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    );
  }

  Widget _compass() {
    return Container(
      width: 35,
      height: 35,
      decoration: BoxDecoration(
        color: const Color(0xDD10191B),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: const Center(
        child: Text(
          'N',
          style: TextStyle(
            color: Color(0xFFD3DEDA),
            fontSize: 11,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.7,
        ),
      ),
    );
  }
}

class _VehicleArrowPainter extends CustomPainter {
  const _VehicleArrowPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final arrow = Path()
      ..moveTo(center.dx, size.height * 0.08)
      ..lineTo(size.width * 0.84, size.height * 0.92)
      ..lineTo(center.dx, size.height * 0.70)
      ..lineTo(size.width * 0.16, size.height * 0.92)
      ..close();
    canvas.drawPath(
      arrow,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant _VehicleArrowPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

/// Returns the initial bearing clockwise from true north, in degrees.
double calculateForwardBearing(LatLng from, LatLng to) {
  final fromLatitude = from.latitude * math.pi / 180;
  final toLatitude = to.latitude * math.pi / 180;
  final longitudeDelta = (to.longitude - from.longitude) * math.pi / 180;
  final y = math.sin(longitudeDelta) * math.cos(toLatitude);
  final x = math.cos(fromLatitude) * math.sin(toLatitude) -
      math.sin(fromLatitude) * math.cos(toLatitude) * math.cos(longitudeDelta);
  return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
}

/// Projects a coordinate using the fixed, north-up demo camera.
Offset projectCoordinateToScreen(LatLng coordinate, Size mapSize) {
  const tileSize = 512.0;

  double mercatorX(double longitude) => (longitude + 180) / 360;

  double mercatorY(double latitude) {
    final clampedLatitude =
        latitude.clamp(-85.05112878, 85.05112878).toDouble();
    final radians = clampedLatitude * math.pi / 180;
    return (1 - math.log(math.tan(math.pi / 4 + radians / 2)) / math.pi) / 2;
  }

  final scale = tileSize * math.pow(2, _mapZoom).toDouble();
  final centerX = mercatorX(_mapCameraTarget.longitude);
  final centerY = mercatorY(_mapCameraTarget.latitude);
  return Offset(
    (mercatorX(coordinate.longitude) - centerX) * scale + mapSize.width / 2,
    (mercatorY(coordinate.latitude) - centerY) * scale + mapSize.height / 2,
  );
}

/// Interpolates bearings over the shortest turn, including across 0°/360°.
double smoothBearingDegrees(
  double current,
  double target, {
  double factor = 0.65,
}) {
  final shortestDelta = ((target - current + 540) % 360) - 180;
  return (current + shortestDelta * factor + 360) % 360;
}

/// Samples a route by travelled distance and returns its position and heading.
({LatLng position, double bearing}) sampleRoute(
  List<LatLng> route,
  double progress,
) {
  if (route.length < 2) {
    throw ArgumentError.value(route, 'route', 'Must contain at least 2 points');
  }

  final segmentLengths = <double>[];
  var totalLength = 0.0;
  for (var index = 0; index < route.length - 1; index++) {
    final length = _distanceMeters(route[index], route[index + 1]);
    segmentLengths.add(length);
    totalLength += length;
  }
  if (totalLength == 0) {
    return (position: route.first, bearing: 0);
  }

  var remainingDistance = totalLength * progress.clamp(0.0, 1.0);
  for (var index = 0; index < segmentLengths.length; index++) {
    final length = segmentLengths[index];
    if (length == 0) continue;
    if (remainingDistance <= length || index == segmentLengths.length - 1) {
      final from = route[index];
      final to = route[index + 1];
      final segmentProgress = (remainingDistance / length).clamp(0.0, 1.0);
      return (
        position: LatLng(
          from.latitude + (to.latitude - from.latitude) * segmentProgress,
          from.longitude + (to.longitude - from.longitude) * segmentProgress,
        ),
        bearing: calculateForwardBearing(from, to),
      );
    }
    remainingDistance -= length;
  }

  final last = route.length - 1;
  return (
    position: route[last],
    bearing: calculateForwardBearing(route[last - 1], route[last]),
  );
}

/// Maps Alpha's normalized progress to Bravo's progress toward a set meeting point.
double bravoRouteProgressForCollision(
  double alphaProgress,
  double collisionProgress,
) {
  if (collisionProgress <= 0 || collisionProgress >= 1) {
    throw ArgumentError.value(
      collisionProgress,
      'collisionProgress',
      'Must be between 0 and 1',
    );
  }
  return (alphaProgress * (1 - collisionProgress) / collisionProgress)
      .clamp(0.0, 1.0)
      .toDouble();
}

/// Samples both opposing vehicles using a configurable route meeting point.
({LatLng alpha, LatLng bravo}) sampleOpposingVehiclePositions(
  List<LatLng> route,
  double alphaProgress, {
  required double collisionProgress,
}) {
  final bravoProgress =
      bravoRouteProgressForCollision(alphaProgress, collisionProgress);
  return (
    alpha: sampleRoute(route, alphaProgress).position,
    bravo: sampleRoute(route.reversed.toList(growable: false), bravoProgress)
        .position,
  );
}

/// Returns alert text only when both vehicles approach the same tight bend.
String? collisionNotificationText(
  List<LatLng> route,
  double alphaProgress,
  double bravoProgress,
) =>
    areVehiclesApproachingSameTightBend(
      route,
      alphaProgress,
      bravoProgress,
    )
        ? 'Collision warning: two vehicles are approaching a tight bend. '
            'Take action now.'
        : null;

/// Detects whether both vehicles are close to and approaching the same bend.
bool areVehiclesApproachingSameTightBend(
  List<LatLng> route,
  double alphaProgress,
  double bravoProgress, {
  double maximumBendApproachDistanceMeters = _maximumBendApproachDistanceMeters,
  double maximumVehicleSeparationMeters = _maximumVehicleSeparationMeters,
}) {
  if (route.length < 3 ||
      alphaProgress < 0 ||
      alphaProgress > 1 ||
      bravoProgress < 0 ||
      bravoProgress > 1) {
    return false;
  }

  final segmentLengths = <double>[];
  var totalLength = 0.0;
  for (var index = 0; index < route.length - 1; index++) {
    final length = _distanceMeters(route[index], route[index + 1]);
    segmentLengths.add(length);
    totalLength += length;
  }
  if (totalLength == 0) return false;

  final alphaDistance = totalLength * alphaProgress;
  final bravoDistance = totalLength * bravoProgress;
  final alphaPosition = sampleRoute(route, alphaProgress).position;
  final bravoPosition =
      sampleRoute(route.reversed.toList(growable: false), bravoProgress)
          .position;
  if (_distanceMeters(alphaPosition, bravoPosition) >
      maximumVehicleSeparationMeters) {
    return false;
  }

  var vertexDistance = 0.0;
  for (var index = 1; index < route.length - 1; index++) {
    vertexDistance += segmentLengths[index - 1];
    final alphaDistanceToBend = vertexDistance - alphaDistance;
    final bravoDistanceToBend = totalLength - vertexDistance - bravoDistance;
    if (alphaDistanceToBend < 0 ||
        bravoDistanceToBend < 0 ||
        alphaDistanceToBend > maximumBendApproachDistanceMeters ||
        bravoDistanceToBend > maximumBendApproachDistanceMeters ||
        !isTightCurveAtProgress(
          route,
          vertexDistance / totalLength,
          minimumTurnDegrees: _minimumTightCurveTurnDegrees,
          measurementWindowMeters: _curveMeasurementWindowMeters,
        )) {
      continue;
    }
    return true;
  }

  return false;
}

/// Checks for a sharp road bend near a predicted collision point.
bool isTightCurveAtProgress(
  List<LatLng> route,
  double progress, {
  double minimumTurnDegrees = 45,
  double measurementWindowMeters = 25,
}) {
  if (route.length < 3) return false;

  var totalLength = 0.0;
  for (var index = 0; index < route.length - 1; index++) {
    totalLength += _distanceMeters(route[index], route[index + 1]);
  }
  if (totalLength == 0) return false;

  final collisionDistance = totalLength * progress.clamp(0.0, 1.0);
  final beforeDistance =
      (collisionDistance - measurementWindowMeters).clamp(0.0, totalLength);
  final afterDistance =
      (collisionDistance + measurementWindowMeters).clamp(0.0, totalLength);
  if (beforeDistance == collisionDistance ||
      afterDistance == collisionDistance) {
    return false;
  }

  final before = sampleRoute(route, beforeDistance / totalLength).position;
  final collision =
      sampleRoute(route, collisionDistance / totalLength).position;
  final after = sampleRoute(route, afterDistance / totalLength).position;
  final incomingBearing = calculateForwardBearing(before, collision);
  final outgoingBearing = calculateForwardBearing(collision, after);
  final signedTurn = ((outgoingBearing - incomingBearing + 540) % 360) - 180;
  return signedTurn.abs() >= minimumTurnDegrees;
}

double _distanceMeters(LatLng from, LatLng to) {
  const earthRadiusMeters = 6371000.0;
  final fromLatitude = from.latitude * math.pi / 180;
  final toLatitude = to.latitude * math.pi / 180;
  final latitudeDelta = toLatitude - fromLatitude;
  final longitudeDelta = (to.longitude - from.longitude) * math.pi / 180;
  final haversine = math.sin(latitudeDelta / 2) * math.sin(latitudeDelta / 2) +
      math.cos(fromLatitude) *
          math.cos(toLatitude) *
          math.sin(longitudeDelta / 2) *
          math.sin(longitudeDelta / 2);
  return 2 *
      earthRadiusMeters *
      math.atan2(math.sqrt(haversine), math.sqrt(1 - haversine));
}
