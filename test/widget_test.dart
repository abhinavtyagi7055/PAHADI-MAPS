import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:pahadi_maps/main.dart';

void main() {
  test('bearing helper returns clockwise degrees from north', () {
    expect(
      calculateForwardBearing(const LatLng(0, 0), const LatLng(1, 0)),
      closeTo(0, 1e-9),
    );
    expect(
      calculateForwardBearing(const LatLng(0, 0), const LatLng(0, 1)),
      closeTo(90, 1e-9),
    );
    expect(
      calculateForwardBearing(const LatLng(0, 0), const LatLng(-1, 0)),
      closeTo(180, 1e-9),
    );
    expect(
      calculateForwardBearing(const LatLng(0, 0), const LatLng(0, -1)),
      closeTo(270, 1e-9),
    );
  });

  test('route sampling changes position and heading along a bend', () {
    const route = [
      LatLng(0, 0),
      LatLng(0, 1),
      LatLng(1, 1),
    ];

    final firstHalf = sampleRoute(route, 0.25);
    final secondHalf = sampleRoute(route, 0.75);

    expect(firstHalf.bearing, closeTo(90, 1e-6));
    expect(secondHalf.bearing, closeTo(0, 1e-6));
    expect(secondHalf.position.latitude, greaterThan(0));
    expect(secondHalf.position.longitude, closeTo(1, 1e-6));
  });

  test('bearing smoothing takes the short turn across north', () {
    expect(smoothBearingDegrees(350, 10, factor: 0.5), closeTo(0, 1e-9));
  });

  test('tight curve detection only accepts nearby sharp bends', () {
    const tightCurve = [
      LatLng(0, 0),
      LatLng(0, 0.001),
      LatLng(0.001, 0.001),
    ];
    const straightRoad = [
      LatLng(0, 0),
      LatLng(0, 0.001),
      LatLng(0, 0.002),
    ];

    expect(isTightCurveAtProgress(tightCurve, 0.5), isTrue);
    expect(isTightCurveAtProgress(tightCurve, 0.2), isFalse);
    expect(isTightCurveAtProgress(straightRoad, 0.5), isFalse);
    expect(
      isTightCurveAtProgress(
        tightCurve,
        0.5,
        minimumTurnDegrees: 100,
      ),
      isFalse,
    );
  });

  test('imminent collision on a tight bend produces notification text', () {
    const tightCurve = [
      LatLng(0, 0),
      LatLng(0, 0.001),
      LatLng(0.001, 0.001),
    ];

    expect(
      collisionNotificationText(
        tightCurve,
        0.4,
        0.4,
      ),
      'Collision warning: two vehicles are approaching a tight bend. '
      'Take action now.',
    );
  });

  test('cars meet on an adjustable tight bend and produce notification text',
      () {
    const collisionProgress = 0.3;
    const tightBendAtMeetingPoint = [
      LatLng(0, 0),
      LatLng(0, 0.001),
      LatLng(0.002333333, 0.001),
    ];

    final meetingPositions = sampleOpposingVehiclePositions(
      tightBendAtMeetingPoint,
      collisionProgress,
      collisionProgress: collisionProgress,
    );

    expect(
      meetingPositions.alpha.latitude,
      closeTo(meetingPositions.bravo.latitude, 1e-9),
    );
    expect(
      meetingPositions.alpha.longitude,
      closeTo(meetingPositions.bravo.longitude, 1e-9),
    );
    expect(
      collisionNotificationText(
        tightBendAtMeetingPoint,
        collisionProgress - 0.05,
        bravoRouteProgressForCollision(
          collisionProgress - 0.05,
          collisionProgress,
        ),
      ),
      'Collision warning: two vehicles are approaching a tight bend. '
      'Take action now.',
    );
  });

  test(
      'no notification text is produced without an imminent tight-bend collision',
      () {
    const straightRoad = [
      LatLng(0, 0),
      LatLng(0, 0.001),
      LatLng(0, 0.002),
    ];
    const tightCurve = [
      LatLng(0, 0),
      LatLng(0, 0.001),
      LatLng(0.001, 0.001),
    ];

    expect(collisionNotificationText(straightRoad, 0.4, 0.4), isNull);
    expect(collisionNotificationText(tightCurve, 0.1, 0.1), isNull);
    expect(collisionNotificationText(tightCurve, 0.6, 0.6), isNull);
    expect(collisionNotificationText(tightCurve, 0.2, 0.8), isNull);
    expect(
      collisionNotificationText(tightCurve, 0.2, 0.2),
      'Collision warning: two vehicles are approaching a tight bend. '
      'Take action now.',
    );
  });

  test('demo route alerts only when cars approach the tight bend', () {
    const meetingPoint = 0.68;
    const alphaApproachingProgress = 0.64;
    const bravoApproachingProgress =
        alphaApproachingProgress * (1 - meetingPoint) / meetingPoint;

    expect(isTightCurveAtProgress(demoRoadRoute, meetingPoint), isTrue);
    expect(
      collisionNotificationText(demoRoadRoute, 0.48, 0.48),
      isNull,
    );
    expect(
      collisionNotificationText(
        demoRoadRoute,
        alphaApproachingProgress,
        bravoApproachingProgress,
      ),
      isNotNull,
    );
    expect(
      collisionNotificationText(
        demoRoadRoute,
        0.5,
        bravoRouteProgressForCollision(0.5, meetingPoint),
      ),
      isNull,
    );
  });

  test('fixed-camera projection centers the route and keeps it in view', () {
    const size = Size(600, 492);
    const route = [
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

    final center = projectCoordinateToScreen(
      const LatLng(32.37275, 77.2473),
      size,
    );
    expect(center.dx, closeTo(size.width / 2, 1e-6));
    expect(center.dy, closeTo(size.height / 2, 1e-6));

    for (final coordinate in route) {
      final point = projectCoordinateToScreen(coordinate, size);
      expect(point.dx, inInclusiveRange(42, size.width - 42));
      expect(point.dy, inInclusiveRange(18, size.height - 70));
    }
  });
}
