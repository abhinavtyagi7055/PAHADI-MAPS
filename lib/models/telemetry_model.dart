import 'package:maplibre_gl/maplibre_gl.dart';

/// Vehicle Telemetry Data Model
class VehicleTelemetry {
  final String deviceId;
  final double latitude;
  final double longitude;
  final double speed; // km/h
  final double heading; // degrees (0-360)
  final String vehicleType;
  final int timestamp;
  final Map<String, dynamic>? velocityVector;
  final List<LatLng> projectedTrajectory;

  VehicleTelemetry({
    required this.deviceId,
    required this.latitude,
    required this.longitude,
    required this.speed,
    required this.heading,
    this.vehicleType = 'VEHICLE',
    required this.timestamp,
    this.velocityVector,
    this.projectedTrajectory = const [],
  });

  LatLng get position => LatLng(latitude, longitude);

  factory VehicleTelemetry.fromJson(Map<String, dynamic> json) {
    List<LatLng> trajectory = [];
    if (json['projectedTrajectory'] != null && json['projectedTrajectory'] is List) {
      for (var p in json['projectedTrajectory']) {
        if (p['latitude'] != null && p['longitude'] != null) {
          trajectory.add(LatLng(
            (p['latitude'] as num).toDouble(),
            (p['longitude'] as num).toDouble(),
          ));
        }
      }
    }

    return VehicleTelemetry(
      deviceId: json['deviceId'] ?? 'unknown',
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      speed: (json['speed'] as num?)?.toDouble() ?? 0.0,
      heading: (json['heading'] as num?)?.toDouble() ?? 0.0,
      vehicleType: json['vehicleType'] ?? 'VEHICLE',
      timestamp: json['timestamp'] ?? DateTime.now().millisecondsSinceEpoch,
      velocityVector: json['velocityVector'] is Map<String, dynamic>
          ? json['velocityVector'] as Map<String, dynamic>
          : null,
      projectedTrajectory: trajectory,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'deviceId': deviceId,
      'latitude': latitude,
      'longitude': longitude,
      'speed': speed,
      'heading': heading,
      'vehicleType': vehicleType,
      'timestamp': timestamp,
    };
  }
}

/// Pre-defined Himalayan Blind Spot Hazard Zone Model
class BlindSpotZone {
  final String id;
  final String name;
  final double elevationMeters;
  final double speedLimitKmh;
  final String riskLevel;
  final String description;
  final LatLng center;
  final List<LatLng> polygon;

  BlindSpotZone({
    required this.id,
    required this.name,
    required this.elevationMeters,
    required this.speedLimitKmh,
    required this.riskLevel,
    required this.description,
    required this.center,
    required this.polygon,
  });

  factory BlindSpotZone.fromJson(Map<String, dynamic> json) {
    final centerJson = json['center'] ?? {};
    final centerLatLng = LatLng(
      (centerJson['latitude'] as num?)?.toDouble() ?? 32.3715,
      (centerJson['longitude'] as num?)?.toDouble() ?? 77.2472,
    );

    List<LatLng> polyCoords = [];
    if (json['polygon'] != null && json['polygon'] is List) {
      for (var pt in json['polygon']) {
        if (pt is List && pt.length >= 2) {
          // GeoJSON is [longitude, latitude]
          polyCoords.add(LatLng(
            (pt[1] as num).toDouble(),
            (pt[0] as num).toDouble(),
          ));
        }
      }
    }

    return BlindSpotZone(
      id: json['id'] ?? '',
      name: json['name'] ?? 'Blind Curve',
      elevationMeters: (json['elevationMeters'] as num?)?.toDouble() ?? 0.0,
      speedLimitKmh: (json['speedLimitKmh'] as num?)?.toDouble() ?? 30.0,
      riskLevel: json['riskLevel'] ?? 'HIGH',
      description: json['description'] ?? '',
      center: centerLatLng,
      polygon: polyCoords,
    );
  }
}

/// Predictive Collision Warning Alert Model
class CollisionAlert {
  final String alertId;
  final String severity; // 'CRITICAL' | 'WARNING'
  final String hazardType;
  final String blindSpotName;
  final List<String> entityIds;
  final double ttc; // Time to collision in seconds
  final double currentDistanceMeters;
  final double closingSpeedKmh;
  final double relativeSpeedKmh;
  final double cpaDistanceMeters;
  final LatLng? intersectionPoint;
  final String advisory;
  final int timestamp;

  CollisionAlert({
    required this.alertId,
    required this.severity,
    required this.hazardType,
    required this.blindSpotName,
    required this.entityIds,
    required this.ttc,
    required this.currentDistanceMeters,
    required this.closingSpeedKmh,
    required this.relativeSpeedKmh,
    required this.cpaDistanceMeters,
    this.intersectionPoint,
    required this.advisory,
    required this.timestamp,
  });

  bool get isCritical => severity == 'CRITICAL';

  factory CollisionAlert.fromJson(Map<String, dynamic> json) {
    LatLng? interPt;
    if (json['intersectionPoint'] != null && json['intersectionPoint'] is Map) {
      final ip = json['intersectionPoint'];
      if (ip['latitude'] != null && ip['longitude'] != null) {
        interPt = LatLng(
          (ip['latitude'] as num).toDouble(),
          (ip['longitude'] as num).toDouble(),
        );
      }
    }

    List<String> entities = [];
    if (json['entities'] != null && json['entities'] is List) {
      for (var e in json['entities']) {
        if (e is Map && e['deviceId'] != null) {
          entities.add(e['deviceId'].toString());
        } else if (e is String) {
          entities.add(e);
        }
      }
    }

    final bs = json['blindSpot'] is Map ? json['blindSpot'] : {};

    return CollisionAlert(
      alertId: json['alertId'] ?? 'ALERT_${DateTime.now().millisecondsSinceEpoch}',
      severity: json['severity'] ?? 'WARNING',
      hazardType: json['hazardType'] ?? 'BLIND_SPOT_COLLISION',
      blindSpotName: bs['name'] ?? 'Rohtang Pass KM-42 Hairpin',
      entityIds: entities,
      ttc: (json['ttc'] as num?)?.toDouble() ?? 5.0,
      currentDistanceMeters: (json['currentDistanceMeters'] as num?)?.toDouble() ?? 100.0,
      closingSpeedKmh: (json['closingSpeedKmh'] as num?)?.toDouble() ?? 0.0,
      relativeSpeedKmh: (json['relativeSpeedKmh'] as num?)?.toDouble() ?? 0.0,
      cpaDistanceMeters: (json['cpaDistanceMeters'] as num?)?.toDouble() ?? 0.0,
      intersectionPoint: interPt,
      advisory: json['advisory'] ?? 'CAUTION: Approach with extreme care.',
      timestamp: json['timestamp'] ?? DateTime.now().millisecondsSinceEpoch,
    );
  }
}
