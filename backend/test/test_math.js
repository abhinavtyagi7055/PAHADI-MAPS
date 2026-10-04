/**
 * Verification test for Pahadi Telemetry Guard Vector & Geospatial Math
 */

const geometry = require('../src/geometry');

console.log('--- RUNNING GEOSPATIAL & VECTOR MATH TEST SUITE ---');

// Reference center: Rohtang Pass Hairpin (Himachal Pradesh, India)
const originLat = 32.3715;
const originLon = 77.2472;

// 1. Test Geodesic Projection
const pos1 = geometry.toLocalCartesian(originLat, originLon, originLat, originLon);
console.log('Origin Cartesian Check (should be 0,0):', pos1);
if (Math.abs(pos1.x) > 0.001 || Math.abs(pos1.y) > 0.001) {
  throw new Error('Origin projection failed');
}

// 2. Test Velocity Vector
// Speed: 36 km/h = 10 m/s. Heading: 90° (due East) -> vx=10, vy=0
const velEast = geometry.headingAndSpeedToVelocity(36, 90);
console.log('Velocity Check 36 km/h @ 90°:', velEast);
if (Math.abs(velEast.vx - 10) > 0.01 || Math.abs(velEast.vy) > 0.01) {
  throw new Error('Velocity vector calculation failed');
}

// 3. Test Relative Kinematics & CPA (Head-on collision scenario)
// Car A at x=-50, y=0 moving East (+x) at 10 m/s (36 km/h)
// Car B at x=+50, y=0 moving West (-x) at 10 m/s (36 km/h)
// Separation: 100m. Closing speed: 20 m/s (72 km/h).
// Expected TTC: 100 / 20 = 5.0 seconds. Expected CPA distance: 0 meters!
const posA = { x: -50, y: 0 };
const velA = { vx: 10, vy: 0 };
const posB = { x: 50, y: 0 };
const velB = { vx: -10, vy: 0 };

const kin = geometry.calculateRelativeKinematics(posA, velA, posB, velB);
console.log('Relative Kinematics Head-On:', {
  distance: kin.currentDistance,
  closingSpeedKmh: kin.closingSpeedKmh,
  timeToCpaSec: kin.timeToCpaSec,
  cpaDistanceMeters: kin.cpaDistanceMeters
});

if (Math.abs(kin.currentDistance - 100) > 0.1) throw new Error('Distance mismatch');
if (Math.abs(kin.closingSpeedKmh - 72) > 0.1) throw new Error('Closing speed mismatch');
if (Math.abs(kin.timeToCpaSec - 5.0) > 0.1) throw new Error('TTC mismatch');
if (Math.abs(kin.cpaDistanceMeters - 0) > 0.1) throw new Error('CPA distance mismatch');

// 4. Test Trajectory Line Intersection
const inter = geometry.findTrajectoryIntersection(posA, velA, posB, velB, 10);
console.log('Trajectory Intersection:', inter);
if (!inter || !inter.intersects || Math.abs(inter.x - 0) > 0.1) {
  throw new Error('Trajectory intersection test failed');
}

// 5. Test Ray-Casting Polygon
const blindSpotPolygon = [
  [77.2465, 32.3710],
  [77.2480, 32.3710],
  [77.2480, 32.3725],
  [77.2465, 32.3725],
  [77.2465, 32.3710]
];

const inside = geometry.isPointInPolygon([77.2472, 32.3718], blindSpotPolygon);
const outside = geometry.isPointInPolygon([77.2500, 32.3750], blindSpotPolygon);
console.log('Polygon Inside Test (should be true):', inside);
console.log('Polygon Outside Test (should be false):', outside);

if (!inside || outside) {
  throw new Error('Polygon containment test failed');
}

console.log('>>> ALL GEOMETRY & VECTOR MATHEMATICS TESTS PASSED! <<<');
