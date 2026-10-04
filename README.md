# Pahadi Maps 🏔️📡

A real-time geospatial safety system engineered for mountainous terrain (narrow hairpin turns, zero-sightline cliff passes, and blind corners). It ingests high-frequency vehicle telemetry, projects kinematic motion vectors, performs 2D spatial polygon collision matching, computes Relative Velocity and Closest Point of Approach (CPA) / Time-to-Collision (TTC), and triggers predictive collision warnings for cross-platform Flutter clients with a tactical cockpit HUD.

---

## System Architecture

```
                  +---------------------------------------+
                  |       Vehicles / GPS Telemetry        |
                  |  (Vehicle-Alpha & Vehicle-Bravo)      |
                  +-------------------+-------------------+
                                      |
                  JSON Telemetry Stream (WebSocket/Socket.io)
                  { deviceId, lat, lng, speed, heading, ts }
                                      |
                                      v
                  +---------------------------------------+
                  |         Node.js Backend Engine        |
                  |   (server.js + Spatial Vector Math)   |
                  |                                       |
                  | 1. Geodesic ENU Local Projection     |
                  | 2. Kinematic Trajectory Vectors       |
                  | 3. Blind Spot Polygon Ray-Casting     |
                  | 4. Relative Velocity & CPA (TTC) Calc |
                  | 5. Predictive Collision Trigger       |
                  +-------------------+-------------------+
                                      |
                    Socket.io Broadcast / Alert Event
                    'collision_alert', 'telemetry_stream'
                                      |
                                      v
                  +---------------------------------------+
                  |     Flutter Mobile / Web Frontend     |
                  |         (MapLibre GL Vector)          |
                  |                                       |
                  | - Dark HUD / Mountain Vector Tiles    |
                  | - SymbolLayer (Moving Vehicles)       |
                  | - LineLayer (Projected Vectors)       |
                  | - Hazard Polygon (Blind Spot Curve)   |
                  | - Real-time Cockpit Speedometer/HUD   |
                  | - Flashing High-Contrast Alert Banner |
                  +-------------------+-------------------+
```

---

## Directory Structure

```text
pahadi_maps/
├── backend/
│   ├── src/
│   │   └── geometry.js           # ENU projection, CPA, TTC, polygon ray-casting
│   ├── test/
│   │   └── test_math.js          # Unit tests for vector math & collision logic
│   ├── server.js                 # Express + Socket.io collision alert engine
│   ├── simulation.js             # Live multi-vehicle mountain road simulator
│   ├── package.json              # Backend dependencies
│   └── README.md                 # Backend documentation
├── lib/
│   ├── models/
│   │   └── telemetry_model.dart  # Data models (VehicleTelemetry, CollisionAlert, BlindSpot)
│   ├── services/
│   │   └── telemetry_service.dart# Socket.io client service & stream controllers
│   ├── widgets/
│   │   ├── collision_alert_banner.dart # Flashing neon-red warning modal banner
│   │   └── hud_overlay.dart      # Tactical cockpit HUD & instrumentation gauges
│   └── main.dart                 # MapLibre map initialization, layers, and HUD integration
├── web/
│   └── index.html                # MapLibre GL JS & CSS bindings
├── test/
│   └── widget_test.dart          # Flutter model and component unit tests
└── pubspec.yaml                  # Flutter dependencies (maplibre_gl, socket_io_client)
```

---

## Run the Flutter Collision Demo

From the project root:

```powershell
flutter pub get
flutter run -d edge
```

Select **START COLLISION DEMO** and allow browser notifications when prompted.
The MapLibre map uses a dark local style and draws one shared Rohtang Pass GPS
road with two animated vehicle markers travelling in opposite directions.
Their headings follow the route bearing. Markers are stable Flutter overlays,
positioned using MapLibre screen coordinates, so movement does not recreate
map annotations. Browser and in-app collision notifications are sent only
when both vehicles are within 75 m of and still approaching the same bend, the
bend changes direction by at least 45 degrees across a 25 m measurement window,
and the vehicles are within 120 m of each other. Detection uses the vehicles'
current route positions; the **VEHICLE MEETING POINT** slider only changes the
demo trajectories for testing. Moving it resets the current pass.
The demo does not require the Node.js backend or map tiles.

## Run the Optional Node.js Backend

In separate terminals, start the server and simulator:

```powershell
cd "c:\flutter app\pahadi_maps\backend"
npm install
node server.js
```

```powershell
cd "c:\flutter app\pahadi_maps\backend"
node simulation.js
```

The backend simulator emits telemetry and collision alerts through Socket.IO;
it currently runs independently from the standalone Flutter browser demo.
