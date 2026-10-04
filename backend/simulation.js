/**
 * Pahadi Telemetry Guard - Live Multi-Vehicle Mountain Road Simulator
 * 
 * Simulates two vehicles negotiating the Rohtang Pass KM-42 hairpin curve:
 * - Vehicle-Alpha: Heavy downhill oil tanker descending from upper pass
 * - Vehicle-Bravo: Uphill tourist SUV climbing from the valley
 * 
 * Connects to the Pahadi Telemetry Guard server via WebSockets,
 * streams high-frequency telemetry, prints an ASCII tactical dashboard,
 * and demonstrates live predictive collision alerts when intersecting at the blind spot.
 */

const { io } = require('socket.io-client');

const SERVER_URL = process.env.SERVER_URL || 'http://localhost:3000';
const UPDATE_INTERVAL_MS = 500; // 2 Hz telemetry stream

console.log('===============================================================');
console.log('🏔️  PAHADI TELEMETRY GUARD - MOUNTAIN ROAD SIMULATOR');
console.log(`   Connecting to server at: ${SERVER_URL}`);
console.log('===============================================================');

const socket = io(SERVER_URL, {
  reconnection: true,
  reconnectionAttempts: 10,
  reconnectionDelay: 1000
});

// Hairpin waypoint tracks around Rohtang Pass KM-42 (lat: ~32.3715, lng: ~77.2472)
// Downhill Route for Vehicle Alpha (North -> South towards hairpin apex)
const ROUTE_ALPHA = [
  { lat: 32.3742, lng: 77.2460, speed: 45, heading: 175 },
  { lat: 32.3736, lng: 77.2462, speed: 42, heading: 170 },
  { lat: 32.3730, lng: 77.2464, speed: 40, heading: 165 },
  { lat: 32.3724, lng: 77.2467, speed: 38, heading: 160 },
  { lat: 32.3719, lng: 77.2470, speed: 35, heading: 145 }, // Entering blind zone
  { lat: 32.3716, lng: 77.2472, speed: 32, heading: 120 }, // Apex entry
  { lat: 32.3714, lng: 77.2474, speed: 25, heading: 90 },  // Collision hotspot / apex
  { lat: 32.3713, lng: 77.2476, speed: 22, heading: 60 },  // Passing apex
  { lat: 32.3714, lng: 77.2480, speed: 28, heading: 35 },  // Exiting hairpin
  { lat: 32.3718, lng: 77.2484, speed: 35, heading: 30 },
  { lat: 32.3724, lng: 77.2486, speed: 40, heading: 25 }
];

// Uphill Route for Vehicle Bravo (South-East -> North-West towards same hairpin apex)
const ROUTE_BRAVO = [
  { lat: 32.3698, lng: 77.2484, speed: 48, heading: 340 },
  { lat: 32.3703, lng: 77.2482, speed: 45, heading: 335 },
  { lat: 32.3707, lng: 77.2479, speed: 42, heading: 330 },
  { lat: 32.3710, lng: 77.2477, speed: 38, heading: 320 },
  { lat: 32.3713, lng: 77.2475, speed: 35, heading: 300 }, // Entering blind zone
  { lat: 32.3714, lng: 77.2473, speed: 30, heading: 275 }, // Apex entry
  { lat: 32.3715, lng: 77.2472, speed: 25, heading: 250 }, // Collision hotspot / apex
  { lat: 32.3717, lng: 77.2470, speed: 22, heading: 230 }, // Passing apex
  { lat: 32.3721, lng: 77.2467, speed: 28, heading: 200 }, // Exiting hairpin
  { lat: 32.3727, lng: 77.2464, speed: 35, heading: 190 },
  { lat: 32.3734, lng: 77.2461, speed: 42, heading: 185 }
];

// Linear Interpolation helper to produce smooth sub-steps
function interpolatePath(route, subDivisions = 4) {
  const detailed = [];
  for (let i = 0; i < route.length - 1; i++) {
    const p1 = route[i];
    const p2 = route[i + 1];
    for (let s = 0; s < subDivisions; s++) {
      const frac = s / subDivisions;
      detailed.push({
        lat: p1.lat + (p2.lat - p1.lat) * frac,
        lng: p1.lng + (p2.lng - p1.lng) * frac,
        speed: p1.speed + (p2.speed - p1.speed) * frac,
        heading: p1.heading + (p2.heading - p1.heading) * frac
      });
    }
  }
  detailed.push(route[route.length - 1]);
  return detailed;
}

const detailedAlpha = interpolatePath(ROUTE_ALPHA, 5);
const detailedBravo = interpolatePath(ROUTE_BRAVO, 5);
const totalSteps = Math.min(detailedAlpha.length, detailedBravo.length);

let currentStep = 0;
let loopCount = 1;
let activeAlert = null;
let simTimer = null;

socket.on('connect', () => {
  console.log(`[CONNECTED] Socket ID: ${socket.id}`);
  console.log('[SIMULATOR] Starting telemetry transmission in 1 second...\n');
  setTimeout(startSimulation, 1000);
});

socket.on('collision_alert', (alert) => {
  activeAlert = alert;
});

socket.on('collision_resolved', (data) => {
  if (activeAlert) {
    console.log(`\n✅ >>> [HAZARD RESOLVED] ${data.reason} <<<\n`);
  }
  activeAlert = null;
});

socket.on('disconnect', () => {
  console.log('[DISCONNECTED] Lost connection to server.');
});

function startSimulation() {
  if (simTimer) clearInterval(simTimer);

  simTimer = setInterval(() => {
    const stepAlpha = detailedAlpha[currentStep];
    const stepBravo = detailedBravo[currentStep];

    const timestamp = Date.now();

    // Transmit telemetry for Vehicle-Alpha
    socket.emit('telemetry', {
      deviceId: 'vehicle_alpha',
      latitude: stepAlpha.lat,
      longitude: stepAlpha.lng,
      speed: stepAlpha.speed,
      heading: stepAlpha.heading,
      vehicleType: 'HEAVY_TRUCK',
      timestamp
    });

    // Transmit telemetry for Vehicle-Bravo
    socket.emit('telemetry', {
      deviceId: 'vehicle_bravo',
      latitude: stepBravo.lat,
      longitude: stepBravo.lng,
      speed: stepBravo.speed,
      heading: stepBravo.heading,
      vehicleType: 'SUV',
      timestamp
    });

    // Render Tactical Status Line
    renderDashboard(currentStep, stepAlpha, stepBravo);

    currentStep++;
    if (currentStep >= totalSteps) {
      console.log(`\n🔁 --- COMPLETED PASS #${loopCount} -> RESETTING ROUTE FOR CONTINUOUS DEMO ---\n`);
      currentStep = 0;
      loopCount++;
    }
  }, UPDATE_INTERVAL_MS);
}

function renderDashboard(step, a, b) {
  // Rough distance calculation
  const dLat = (a.lat - b.lat) * 111139;
  const dLng = (a.lng - b.lng) * 111139 * Math.cos((a.lat * Math.PI) / 180);
  const dist = Math.sqrt(dLat * dLat + dLng * dLng);

  let statusStr = '🟢 CLEAR';
  if (activeAlert) {
    if (activeAlert.severity === 'CRITICAL') {
      statusStr = `🚨 CRITICAL ALERT! TTC: ${activeAlert.ttc}s | Dist: ${activeAlert.currentDistanceMeters}m | RelSpeed: ${activeAlert.closingSpeedKmh}km/h`;
    } else {
      statusStr = `⚠️ WARNING | TTC: ${activeAlert.ttc}s | Dist: ${activeAlert.currentDistanceMeters}m`;
    }
  }

  process.stdout.write(
    `[Step ${String(step).padStart(2, '0')}/${totalSteps}] ` +
    `Alpha: (${a.lat.toFixed(4)}, ${a.lng.toFixed(4)}) ${a.speed.toFixed(0)}km/h | ` +
    `Bravo: (${b.lat.toFixed(4)}, ${b.lng.toFixed(4)}) ${b.speed.toFixed(0)}km/h | ` +
    `Dist: ${dist.toFixed(0)}m | Status: ${statusStr}\r`
  );

  if (activeAlert && activeAlert.severity === 'CRITICAL') {
    // Print dedicated alert line when critical
    console.log(`\n⚡ [${activeAlert.blindSpot.name}] ${activeAlert.advisory}`);
  }
}

// Graceful exit
process.on('SIGINT', () => {
  console.log('\nStopping simulator...');
  if (simTimer) clearInterval(simTimer);
  socket.disconnect();
  process.exit(0);
});
