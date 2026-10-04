/**
 * Pahadi Telemetry Guard - Geospatial & Vector Mathematics Engine
 * 
 * Provides high-precision local tangent plane (ENU) projections,
 * kinematic vector extrapolations, relative velocity & Closest Point of Approach (CPA) calculations,
 * and 2D spatial polygon ray-casting for mountain hairpin curves.
 */

const EARTH_RADIUS = 6371000.0; // Mean Earth radius in meters

/**
 * Convert degrees to radians
 */
function toRadians(degrees) {
  return (degrees * Math.PI) / 180.0;
}

/**
 * Convert radians to degrees
 */
function toDegrees(radians) {
  return (radians * 180.0) / Math.PI;
}

/**
 * Geodesic distance (Haversine formula) in meters
 */
function haversineDistance(lat1, lon1, lat2, lon2) {
  const dLat = toRadians(lat2 - lat1);
  const dLon = toRadians(lon2 - lon1);
  const phi1 = toRadians(lat1);
  const phi2 = toRadians(lat2);

  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(phi1) * Math.cos(phi2) * Math.sin(dLon / 2) * Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));

  return EARTH_RADIUS * c;
}

/**
 * Project geographic coordinates (lat, lon) to local Cartesian tangent plane (ENU in meters)
 * relative to a local origin point (e.g., center of the mountain pass/blind spot).
 */
function toLocalCartesian(lat, lon, originLat, originLon) {
  const phi = toRadians(lat);
  const lambda = toRadians(lon);
  const phi0 = toRadians(originLat);
  const lambda0 = toRadians(originLon);

  const meanPhi = (phi + phi0) / 2.0;
  const x = EARTH_RADIUS * (lambda - lambda0) * Math.cos(meanPhi);
  const y = EARTH_RADIUS * (phi - phi0);

  return { x, y };
}

/**
 * Convert local Cartesian tangent plane (x, y in meters) back to geographic coordinates (lat, lon)
 */
function toGeographic(x, y, originLat, originLon) {
  const phi0 = toRadians(originLat);
  const lambda0 = toRadians(originLon);

  const latRad = phi0 + y / EARTH_RADIUS;
  const lonRad = lambda0 + x / (EARTH_RADIUS * Math.cos((phi0 + latRad) / 2.0));

  return {
    latitude: toDegrees(latRad),
    longitude: toDegrees(lonRad)
  };
}

/**
 * Convert vehicle speed (km/h) and heading (degrees clockwise from North)
 * into a Cartesian velocity vector (vx: East in m/s, vy: North in m/s).
 */
function headingAndSpeedToVelocity(speedKmh, headingDeg) {
  const speedMs = (speedKmh * 1000.0) / 3600.0;
  const headingRad = toRadians(headingDeg);

  // In navigation, 0° = North (+y), 90° = East (+x), 180° = South (-y), 270° = West (-x)
  const vx = speedMs * Math.sin(headingRad);
  const vy = speedMs * Math.cos(headingRad);

  return { vx, vy, speedMs };
}

/**
 * Calculate kinematic trajectory points over a time horizon.
 */
function projectTrajectory(lat, lon, speedKmh, headingDeg, originLat, originLon, horizonSec = 10, stepSec = 1) {
  const p0 = toLocalCartesian(lat, lon, originLat, originLon);
  const { vx, vy } = headingAndSpeedToVelocity(speedKmh, headingDeg);

  const points = [];
  for (let t = 0; t <= horizonSec; t += stepSec) {
    const px = p0.x + vx * t;
    const py = p0.y + vy * t;
    const geo = toGeographic(px, py, originLat, originLon);
    points.push({
      timeOffsetSec: t,
      x: px,
      y: py,
      latitude: geo.latitude,
      longitude: geo.longitude
    });
  }

  return {
    current: { x: p0.x, y: p0.y, latitude: lat, longitude: lon },
    velocity: { vx, vy },
    projected: points
  };
}

/**
 * Calculate Relative Velocity, Closest Point of Approach (CPA), and Time-to-Collision (TTC)
 * between two moving vehicles A and B.
 * 
 * @param {Object} posA - { x, y } in meters
 * @param {Object} velA - { vx, vy } in m/s
 * @param {Object} posB - { x, y } in meters
 * @param {Object} velB - { vx, vy } in m/s
 * @returns {Object} Relative kinematics and CPA metrics
 */
function calculateRelativeKinematics(posA, velA, posB, velB) {
  // Relative position vector: r_rel = posB - posA (from A pointing to B)
  const rx = posB.x - posA.x;
  const ry = posB.y - posA.y;
  const currentDistance = Math.sqrt(rx * rx + ry * ry);

  // Relative velocity vector: v_rel = velB - velA
  const vrx = velB.vx - velA.vx;
  const vry = velB.vy - velA.vy;
  const relativeSpeedMs = Math.sqrt(vrx * vrx + vry * vry);
  const relativeSpeedKmh = (relativeSpeedMs * 3600.0) / 1000.0;

  // Closing speed (rate of decrease of distance):
  // v_closing = - (r_rel · v_rel) / |r_rel|
  const dotRV = rx * vrx + ry * vry;
  const closingSpeedMs = currentDistance > 0.001 ? -dotRV / currentDistance : 0.0;
  const closingSpeedKmh = (closingSpeedMs * 3600.0) / 1000.0;

  // Closest Point of Approach (CPA) Time:
  // t_cpa = - (r_rel · v_rel) / |v_rel|^2
  const vRelSq = vrx * vrx + vry * vry;
  let tCpa = 0.0;
  let dCpa = currentDistance;
  let cpaPointA = { x: posA.x, y: posA.y };
  let cpaPointB = { x: posB.x, y: posB.y };

  if (vRelSq > 0.0001) {
    tCpa = -dotRV / vRelSq;
    if (tCpa > 0) {
      cpaPointA = { x: posA.x + velA.vx * tCpa, y: posA.y + velA.vy * tCpa };
      cpaPointB = { x: posB.x + velB.vx * tCpa, y: posB.y + velB.vy * tCpa };
      const cpaDx = cpaPointB.x - cpaPointA.x;
      const cpaDy = cpaPointB.y - cpaPointA.y;
      dCpa = Math.sqrt(cpaDx * cpaDx + cpaDy * cpaDy);
    }
  }

  return {
    currentDistance,
    relativeSpeedKmh,
    closingSpeedKmh,
    isClosing: closingSpeedMs > 0.1,
    timeToCpaSec: tCpa,
    cpaDistanceMeters: dCpa,
    cpaPositionA: cpaPointA,
    cpaPositionB: cpaPointB
  };
}

/**
 * 2D Trajectory Intersection Algorithm
 * Determines if linear trajectory vectors intersect within time horizon,
 * handling both angled crossing paths and collinear head-on trajectories.
 */
function findTrajectoryIntersection(p1, v1, p2, v2, horizonSec = 10) {
  const d1x = v1.vx * horizonSec;
  const d1y = v1.vy * horizonSec;
  const d2x = v2.vx * horizonSec;
  const d2y = v2.vy * horizonSec;

  const denom = d1x * d2y - d1y * d2x;

  // Handle collinear or parallel vectors
  if (Math.abs(denom) < 1e-6) {
    const dx = p2.x - p1.x;
    const dy = p2.y - p1.y;
    // Check if p2 lies along the ray of p1
    const crossProduct = dx * v1.vy - dy * v1.vx;
    if (Math.abs(crossProduct) < 0.1) {
      // Lines are collinear. Check if they are moving towards each other
      const dotV = v1.vx * v2.vx + v1.vy * v2.vy;
      const speed1 = Math.sqrt(v1.vx * v1.vx + v1.vy * v1.vy);
      const speed2 = Math.sqrt(v2.vx * v2.vx + v2.vy * v2.vy);
      const relSpeed = speed1 + speed2;

      if (dotV < 0 && relSpeed > 0.001) {
        const dist = Math.sqrt(dx * dx + dy * dy);
        const tCollide = dist / relSpeed;
        if (tCollide <= horizonSec) {
          return {
            intersects: true,
            isCollinear: true,
            timeA: tCollide,
            timeB: tCollide,
            timeDelta: 0,
            x: p1.x + v1.vx * tCollide,
            y: p1.y + v1.vy * tCollide
          };
        }
      }
    }
    return null;
  }

  const dx = p2.x - p1.x;
  const dy = p2.y - p1.y;

  const u = (dx * d2y - dy * d2x) / denom;
  const w = (dx * d1y - dy * d1x) / denom;

  if (u >= 0 && u <= 1 && w >= 0 && w <= 1) {
    const tA = u * horizonSec;
    const tB = w * horizonSec;
    const intX = p1.x + v1.vx * tA;
    const intY = p1.y + v1.vy * tA;

    return {
      intersects: true,
      isCollinear: false,
      timeA: tA,
      timeB: tB,
      timeDelta: Math.abs(tA - tB),
      x: intX,
      y: intY
    };
  }

  return null;
}

/**
 * Ray-Casting algorithm to check if a 2D coordinate is inside a polygon.
 * Coordinates can be either [lon, lat] or { x, y }.
 */
function isPointInPolygon(point, polygon) {
  const x = Array.isArray(point) ? point[0] : (point.x !== undefined ? point.x : point.longitude);
  const y = Array.isArray(point) ? point[1] : (point.y !== undefined ? point.y : point.latitude);

  let inside = false;
  for (let i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    const xi = Array.isArray(polygon[i]) ? polygon[i][0] : (polygon[i].x !== undefined ? polygon[i].x : polygon[i].longitude);
    const yi = Array.isArray(polygon[i]) ? polygon[i][1] : (polygon[i].y !== undefined ? polygon[i].y : polygon[i].latitude);
    const xj = Array.isArray(polygon[j]) ? polygon[j][0] : (polygon[j].x !== undefined ? polygon[j].x : polygon[j].longitude);
    const yj = Array.isArray(polygon[j]) ? polygon[j][1] : (polygon[j].y !== undefined ? polygon[j].y : polygon[j].latitude);

    const intersect = yi > y !== yj > y && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi;
    if (intersect) inside = !inside;
  }

  return inside;
}

/**
 * Check if a point is within a given buffer distance (meters) of a polygon
 */
function isPointNearPolygon(pointLat, pointLon, polygonGeoCoords, bufferMeters = 25) {
  // If point is strictly inside, return true
  if (isPointInPolygon([pointLon, pointLat], polygonGeoCoords)) {
    return true;
  }

  // Otherwise check distance to all polygon perimeter edges
  for (let i = 0, j = polygonGeoCoords.length - 1; i < polygonGeoCoords.length; j = i++) {
    const p1 = polygonGeoCoords[i];
    const p2 = polygonGeoCoords[j];
    const d1 = haversineDistance(pointLat, pointLon, p1[1], p1[0]);
    const d2 = haversineDistance(pointLat, pointLon, p2[1], p2[0]);
    if (d1 <= bufferMeters || d2 <= bufferMeters) {
      return true;
    }
  }

  return false;
}

module.exports = {
  EARTH_RADIUS,
  toRadians,
  toDegrees,
  haversineDistance,
  toLocalCartesian,
  toGeographic,
  headingAndSpeedToVelocity,
  projectTrajectory,
  calculateRelativeKinematics,
  findTrajectoryIntersection,
  isPointInPolygon,
  isPointNearPolygon
};
