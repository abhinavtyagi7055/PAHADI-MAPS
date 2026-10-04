/**
 * Pahadi Telemetry Guard - Real-Time Geospatial Collision Prediction Server
 * 
 * Express + Socket.io Server that ingests vehicle telemetry,
 * evaluates kinematic trajectory vectors and relative velocity,
 * checks for intersections inside mountain blind spot polygons,
 * and broadcasts millisecond-level collision warnings (TTC).
 */

const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const cors = require('cors');
const path = require('path');
const geometry = require('./src/geometry');

const app = express();
const server = http.createServer(app);
const io = new Server(server, {
  cors: {
    origin: '*',
    methods: ['GET', 'POST']
  }
});

const PORT = process.env.PORT || 3000;

// Middleware
app.use(cors());
app.use(express.json());

// Serve Flutter Web production build
const webBuildPath = path.join(__dirname, '..', 'build', 'web');
app.use(express.static(webBuildPath));

// ==========================================
// PRE-DEFINED HIMALAYAN BLIND SPOT ZONES
// ==========================================
const BLIND_SPOT_ZONES = [
  {
    id: 'bs_rohtang_km42',
    name: 'Rohtang Pass KM-42 Hairpin (Dead Man’s Curve)',
    elevationMeters: 3240,
    speedLimitKmh: 30,
    riskLevel: 'CRITICAL_HAIRPIN',
    description: 'Blind 180° hairpin curve carved into granite cliff wall. Zero forward sightline.',
    center: { latitude: 32.3715, longitude: 77.2472 },
    // Polygon in GeoJSON format: [ [longitude, latitude], ... ]
    polygon: [
      [77.2462, 32.3708],
      [77.2482, 32.3708],
      [77.2485, 32.3726],
      [77.2461, 32.3726],
      [77.2462, 32.3708]
    ]
  },
  {
    id: 'bs_solang_gorge',
    name: 'Solang Gorge S-Curve KM-18',
    elevationMeters: 2560,
    speedLimitKmh: 40,
    riskLevel: 'HIGH_RISK_GORGE',
    description: 'Narrow single-lane mountain passage over glacial torrent with blind entry.',
    center: { latitude: 32.3165, longitude: 77.1580 },
    polygon: [
      [77.1568, 32.3155],
      [77.1592, 32.3155],
      [77.1595, 32.3175],
      [77.1567, 32.3175],
      [77.1568, 32.3155]
    ]
  }
];

// Active State Registry
// deviceId -> { deviceId, latitude, longitude, speed, heading, timestamp, lastUpdate, projectedTrajectory, ... }
const activeVehicles = new Map();
// Set of active alert keys e.g. "vehicleA-vehicleB"
const activeAlerts = new Map();

// Configuration Thresholds
const CONFIG = {
  TRAJECTORY_HORIZON_SEC: 10,   // Look ahead up to 10 seconds
  TTC_SAFETY_THRESHOLD_SEC: 7.5,// Trigger alert if TTC <= 7.5 seconds
  CPA_MAX_DISTANCE_METERS: 16.0,// Danger if Closest Approach distance <= 16m
  MIN_CLOSING_SPEED_KMH: 5.0,   // Danger if closing speed > 5 km/h
  INACTIVE_PRUNE_MS: 15000      // Prune vehicle if no telemetry for 15s
};

/**
 * Periodically prune stale vehicles
 */
setInterval(() => {
  const now = Date.now();
  for (const [deviceId, vehicle] of activeVehicles.entries()) {
    if (now - vehicle.lastUpdate > CONFIG.INACTIVE_PRUNE_MS) {
      console.log(`[Pahadi Server] Pruning inactive device: ${deviceId}`);
      activeVehicles.delete(deviceId);
      io.emit('vehicle_disconnected', { deviceId });
    }
  }
}, 5000);

/**
 * Evaluate collision risk between all active vehicle pairs
 */
function evaluateCollisions() {
  const vehicleList = Array.from(activeVehicles.values());
  if (vehicleList.length < 2) {
    // If fewer than 2 vehicles, clear any existing alerts
    if (activeAlerts.size > 0) {
      for (const [alertKey, alert] of activeAlerts.entries()) {
        io.emit('collision_resolved', {
          alertId: alert.alertId,
          entities: alert.entities,
          reason: 'Insufficient entities active'
        });
      }
      activeAlerts.clear();
    }
    return;
  }

  const detectedAlertKeysThisCycle = new Set();

  for (let i = 0; i < vehicleList.length; i++) {
    for (let j = i + 1; j < vehicleList.length; j++) {
      const vA = vehicleList[i];
      const vB = vehicleList[j];

      const alertKey = [vA.deviceId, vB.deviceId].sort().join('<->');

      // Use the closest blind spot zone center as local origin, or the first one
      const zone = BLIND_SPOT_ZONES[0];
      const originLat = zone.center.latitude;
      const originLon = zone.center.longitude;

      // Project positions to local metric Cartesian
      const posA = geometry.toLocalCartesian(vA.latitude, vA.longitude, originLat, originLon);
      const posB = geometry.toLocalCartesian(vB.latitude, vB.longitude, originLat, originLon);

      // Velocity vectors in m/s
      const velA = geometry.headingAndSpeedToVelocity(vA.speed, vA.heading);
      const velB = geometry.headingAndSpeedToVelocity(vB.speed, vB.heading);

      // Relative kinematics calculation
      const kin = geometry.calculateRelativeKinematics(posA, velA, posB, velB);

      // Check 2D trajectory intersection
      const intersection = geometry.findTrajectoryIntersection(
        posA,
        velA,
        posB,
        velB,
        CONFIG.TRAJECTORY_HORIZON_SEC
      );

      // Verify spatial proximity to any pre-defined blind spot zone
      let associatedBlindSpot = null;
      for (const bs of BLIND_SPOT_ZONES) {
        const aNear = geometry.isPointNearPolygon(vA.latitude, vA.longitude, bs.polygon, 75);
        const bNear = geometry.isPointNearPolygon(vB.latitude, vB.longitude, bs.polygon, 75);
        
        let intersectionNear = false;
        if (intersection && intersection.intersects) {
          const geoInt = geometry.toGeographic(intersection.x, intersection.y, originLat, originLon);
          intersectionNear = geometry.isPointNearPolygon(geoInt.latitude, geoInt.longitude, bs.polygon, 50);
        }

        if (aNear || bNear || intersectionNear) {
          associatedBlindSpot = bs;
          break;
        }
      }

      // Check collision hazard criteria:
      // 1. Must be closing in on each other
      // 2. Either trajectory intersects OR CPA distance is within road width (< 16m)
      // 3. Time to collision / CPA is below safety threshold (< 7.5s)
      // 4. At least one vehicle or the impact point is in/near a designated Blind Spot Zone
      const isClosing = kin.isClosing && kin.closingSpeedKmh > CONFIG.MIN_CLOSING_SPEED_KMH;
      const hasCpaThreat = kin.timeToCpaSec > 0 &&
                           kin.timeToCpaSec <= CONFIG.TTC_SAFETY_THRESHOLD_SEC &&
                           kin.cpaDistanceMeters <= CONFIG.CPA_MAX_DISTANCE_METERS;
      
      const hasIntersectionThreat = intersection &&
                                   intersection.intersects &&
                                   Math.min(intersection.timeA, intersection.timeB) <= CONFIG.TTC_SAFETY_THRESHOLD_SEC &&
                                   intersection.timeDelta <= 3.5;

      const isCollisionThreat = isClosing && (hasCpaThreat || hasIntersectionThreat) && associatedBlindSpot !== null;

      if (isCollisionThreat) {
        detectedAlertKeysThisCycle.add(alertKey);

        const ttc = hasIntersectionThreat
          ? Math.min(intersection.timeA, intersection.timeB)
          : kin.timeToCpaSec;

        let impactGeo = null;
        if (intersection && intersection.intersects) {
          impactGeo = geometry.toGeographic(intersection.x, intersection.y, originLat, originLon);
        } else {
          impactGeo = geometry.toGeographic(kin.cpaPositionA.x, kin.cpaPositionA.y, originLat, originLon);
        }

        const alertPayload = {
          alertId: `ALERT_${vA.deviceId}_${vB.deviceId}_${Date.now()}`,
          severity: ttc < 4.0 ? 'CRITICAL' : 'WARNING',
          hazardType: 'BLIND_SPOT_COLLISION_INTERSECTION',
          blindSpot: {
            id: associatedBlindSpot.id,
            name: associatedBlindSpot.name,
            elevationMeters: associatedBlindSpot.elevationMeters
          },
          entities: [
            {
              deviceId: vA.deviceId,
              speed: vA.speed,
              heading: vA.heading,
              latitude: vA.latitude,
              longitude: vA.longitude
            },
            {
              deviceId: vB.deviceId,
              speed: vB.speed,
              heading: vB.heading,
              latitude: vB.latitude,
              longitude: vB.longitude
            }
          ],
          ttc: parseFloat(ttc.toFixed(1)),
          currentDistanceMeters: parseFloat(kin.currentDistance.toFixed(1)),
          closingSpeedKmh: parseFloat(kin.closingSpeedKmh.toFixed(1)),
          relativeSpeedKmh: parseFloat(kin.relativeSpeedKmh.toFixed(1)),
          cpaDistanceMeters: parseFloat(kin.cpaDistanceMeters.toFixed(1)),
          intersectionPoint: impactGeo,
          advisory: ttc < 4.0
            ? 'EMERGENCY: Immediate collision at blind hairpin! HARD BRAKE & SOUND HORN!'
            : 'CAUTION: Opposing vehicle approaching blind curve. Reduce speed.',
          timestamp: Date.now()
        };

        activeAlerts.set(alertKey, alertPayload);

        // Emit high-priority warning
        io.emit('collision_alert', alertPayload);
        console.log(`[ALERT EMITTED] ${alertPayload.severity} | TTC: ${alertPayload.ttc}s | Dist: ${alertPayload.currentDistanceMeters}m | Zone: ${associatedBlindSpot.name}`);
      }
    }
  }

  // Check for resolved alerts
  for (const [alertKey, alert] of activeAlerts.entries()) {
    if (!detectedAlertKeysThisCycle.has(alertKey)) {
      console.log(`[ALERT RESOLVED] Hazard cleared for ${alertKey}`);
      io.emit('collision_resolved', {
        alertId: alert.alertId,
        entities: alert.entities.map(e => e.deviceId),
        timestamp: Date.now(),
        reason: 'Vehicles safely passed or diverged.'
      });
      activeAlerts.delete(alertKey);
    }
  }
}

// ==========================================
// REST API ROUTES
// ==========================================

app.get('/api/status', (req, res) => {
  res.json({
    status: 'ONLINE',
    service: 'Pahadi Telemetry Guard Engine',
    uptimeSeconds: process.uptime(),
    activeVehiclesCount: activeVehicles.size,
    activeAlertsCount: activeAlerts.size,
    timestamp: Date.now()
  });
});

app.get('/api/blind-spots', (req, res) => {
  res.json({
    success: true,
    blindSpots: BLIND_SPOT_ZONES
  });
});

app.get('/api/vehicles', (req, res) => {
  res.json({
    success: true,
    vehicles: Array.from(activeVehicles.values()),
    count: activeVehicles.size
  });
});

app.post('/api/telemetry', (req, res) => {
  const telemetry = req.body;
  if (!telemetry.deviceId || telemetry.latitude === undefined || telemetry.longitude === undefined) {
    return res.status(400).json({ error: 'Missing required telemetry fields' });
  }

  processTelemetry(telemetry);
  res.json({ success: true, received: Date.now() });
});

/**
 * Core Telemetry Processor
 */
function processTelemetry(data) {
  const { deviceId, latitude, longitude, speed = 0, heading = 0, timestamp = Date.now(), vehicleType = 'VEHICLE' } = data;

  const originLat = BLIND_SPOT_ZONES[0].center.latitude;
  const originLon = BLIND_SPOT_ZONES[0].center.longitude;

  // Project trajectory vectors into the future
  const trajectory = geometry.projectTrajectory(
    latitude,
    longitude,
    speed,
    heading,
    originLat,
    originLon,
    CONFIG.TRAJECTORY_HORIZON_SEC,
    1.0
  );

  const vehicleState = {
    deviceId,
    latitude,
    longitude,
    speed,
    heading,
    vehicleType,
    timestamp,
    lastUpdate: Date.now(),
    velocityVector: trajectory.velocity,
    projectedTrajectory: trajectory.projected
  };

  activeVehicles.set(deviceId, vehicleState);

  // Evaluate collisions with other vehicles
  evaluateCollisions();

  // Broadcast unified telemetry stream to all connected dashboards
  io.emit('telemetry_stream', {
    vehicles: Array.from(activeVehicles.values()),
    timestamp: Date.now()
  });
}

// ==========================================
// SOCKET.IO EVENT HANDLERS
// ==========================================

io.on('connection', (socket) => {
  console.log(`[Socket] Client connected: ${socket.id}`);

  // Send initial state to newly connected client
  socket.emit('init_state', {
    blindSpots: BLIND_SPOT_ZONES,
    vehicles: Array.from(activeVehicles.values()),
    alerts: Array.from(activeAlerts.values()),
    config: CONFIG
  });

  // Client streams telemetry
  socket.on('telemetry', (data) => {
    processTelemetry(data);
  });

  // Client requests manual collision evaluation
  socket.on('request_evaluation', () => {
    evaluateCollisions();
  });

  // Reset or clear vehicles
  socket.on('clear_vehicles', () => {
    activeVehicles.clear();
    activeAlerts.clear();
    io.emit('vehicles_cleared');
    console.log('[Pahadi Server] Vehicles cleared by client');
  });

  socket.on('disconnect', () => {
    console.log(`[Socket] Client disconnected: ${socket.id}`);
  });
});

// Start Server
server.listen(PORT, () => {
  console.log('====================================================');
  console.log(`🏔️  PAHADI TELEMETRY GUARD BACKEND RUNNING ON PORT ${PORT}`);
  console.log(`   HTTP Status: http://localhost:${PORT}/api/status`);
  console.log(`   Blind Spots: http://localhost:${PORT}/api/blind-spots`);
  console.log(`   WebSocket:   ws://localhost:${PORT}`);
  console.log('====================================================');
});
