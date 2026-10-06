# 🏔️ Pahadi Telemetry Guard

> **Real-Time Geospatial Collision Prediction System for Mountain Hairpin Curves & Blind Passes**

A full-stack, cross-platform safety application designed specifically for high-risk Himalayan terrains — narrow hairpin turns, zero-sightline cliff passes, and blind mountain corridors where two opposing vehicles can only "see" each other when it is already too late to brake.

---

## Table of Contents

1. [Project Overview](#project-overview)
2. [System Architecture](#system-architecture)
3. [Directory Structure](#directory-structure)
4. [The Prediction Algorithm — Full Mathematical Derivation](#the-prediction-algorithm--full-mathematical-derivation)
   - [Step 1: Geodesic Projection — Sphere to Flat Plane](#step-1-geodesic-projection--sphere-to-flat-plane)
   - [Step 2: Kinematic Velocity Decomposition](#step-2-kinematic-velocity-decomposition)
   - [Step 3: Trajectory Extrapolation](#step-3-trajectory-extrapolation)
   - [Step 4: Relative Velocity & Closing Speed](#step-4-relative-velocity--closing-speed)
   - [Step 5: Closest Point of Approach (CPA)](#step-5-closest-point-of-approach-cpa)
   - [Step 6: 2D Trajectory Intersection](#step-6-2d-trajectory-intersection)
   - [Step 7: Blind Spot Polygon Ray-Casting](#step-7-blind-spot-polygon-ray-casting)
   - [Step 8: Unified Threat Decision Function](#step-8-unified-threat-decision-function)
   - [Step 9: Severity Classification](#step-9-severity-classification)
5. [Tech Stack](#tech-stack)
6. [Backend API Reference](#backend-api-reference)
7. [Flutter Frontend Features](#flutter-frontend-features)
8. [Configuration Thresholds](#configuration-thresholds)
9. [How to Run](#how-to-run)
10. [Test Verification](#test-verification)

---

## Project Overview

Mountain roads in the Himalayas frequently feature single-lane paths carved into cliff faces, with blind hairpin curves that allow zero forward visibility. Two vehicles approaching the same blind apex from opposite directions have no way to detect each other until they are a few meters apart — too close for emergency braking.

**Pahadi Telemetry Guard** solves this by:

- Ingesting real-time GPS telemetry from all nearby vehicles at 2–4 Hz.
- Mathematically projecting each vehicle's kinematic trajectory forward in time.
- Computing whether two vehicles' future paths will intersect inside a pre-defined **Blind Spot Polygon Zone**.
- Alerting all drivers via WebSocket events **seconds before** the physical encounter at the curve apex.

---

## System Architecture

```
                 ┌─────────────────────────────────────────────────┐
                 │         GPS Telemetry Sources                   │
                 │  { deviceId, lat, lng, speed, heading, ts }     │
                 └──────────────────┬──────────────────────────────┘
                                    │ WebSocket (Socket.io, 2–4 Hz)
                                    ▼
                 ┌─────────────────────────────────────────────────┐
                 │         Node.js Backend Engine (server.js)      │
                 │                                                 │
                 │  1. ENU Geodesic Projection (lat,lon → x,y)     │
                 │  2. Velocity Vector Decomposition               │
                 │  3. Kinematic Trajectory Extrapolation          │
                 │  4. Relative Velocity & Closing Speed           │
                 │  5. CPA / TTC Calculation                       │
                 │  6. 2D Line Intersection Detection              │
                 │  7. Blind Spot Polygon Ray-Casting              │
                 │  8. Unified Threat Decision Function            │
                 └──────────────────┬──────────────────────────────┘
                                    │ Broadcast Events:
                                    │ 'collision_alert'
                                    │ 'telemetry_stream'
                                    │ 'collision_resolved'
                                    ▼
                 ┌─────────────────────────────────────────────────┐
                 │       Flutter Cross-Platform Frontend            │
                 │                                                 │
                 │  • MapLibre GL Vector Map (Dark HUD style)      │
                 │  • SymbolLayer: Live vehicle markers            │
                 │  • LineLayer: Projected trajectory vectors      │
                 │  • Hazard Polygon: Blind spot boundary          │
                 │  • Cockpit HUD: Speedometer, closing speed      │
                 │  • Flashing Alert Banner: TTC countdown         │
                 └─────────────────────────────────────────────────┘
```

---

## Directory Structure

```
pahadi_maps/
│
├── backend/                         # Node.js Telemetry Engine
│   ├── src/
│   │   └── geometry.js              # All vector mathematics & geodesy
│   ├── test/
│   │   └── test_math.js             # Unit tests for all math routines
│   ├── server.js                    # Express + Socket.io server
│   ├── simulation.js                # Live multi-vehicle road simulator
│   ├── package.json                 # Node.js dependencies
│   └── README.md                    # Backend documentation
│
├── lib/                             # Flutter Dart source code
│   ├── models/
│   │   └── telemetry_model.dart     # VehicleTelemetry, CollisionAlert, BlindSpotZone
│   ├── services/
│   │   └── telemetry_service.dart   # Socket.io client, stream controllers
│   ├── widgets/
│   │   ├── collision_alert_banner.dart  # Flashing emergency warning banner
│   │   └── hud_overlay.dart             # Cockpit HUD with instrumentation
│   └── main.dart                    # App root, MapLibre map, layer rendering
│
├── web/
│   └── index.html                   # MapLibre GL JS/CSS bindings for Web target
│
├── android/
│   └── app/src/main/
│       └── AndroidManifest.xml      # INTERNET permission + cleartext traffic
│
├── test/
│   └── widget_test.dart             # Flutter model & widget unit tests
│
├── pubspec.yaml                     # Flutter dependencies
└── README.md                        # This file
```

---

## The Prediction Algorithm — Full Mathematical Derivation

The core of this system is a **multi-stage kinematic collision prediction pipeline** implemented in [`backend/src/geometry.js`](backend/src/geometry.js). It operates in 9 sequential steps on every telemetry tick.

---

### Step 1: Geodesic Projection — Sphere to Flat Plane

**Problem**: GPS coordinates are spherical (latitude `φ`, longitude `λ` in degrees). Vector arithmetic requires a flat Euclidean metric space (meters).

**Solution**: A Local Tangent Plane approximation — the **East-North-Up (ENU)** projection — is applied around the centroid of the mountain blind spot zone, designated as the **local origin** `(φ₀, λ₀)`.

$$x = R_E \cdot (\lambda - \lambda_0) \cdot \frac{\pi}{180} \cdot \cos\!\left(\frac{\phi + \phi_0}{2} \cdot \frac{\pi}{180}\right)$$

$$y = R_E \cdot (\phi - \phi_0) \cdot \frac{\pi}{180}$$

Where:
- `x` = **East displacement** in meters from origin
- `y` = **North displacement** in meters from origin
- `R_E = 6,371,000 m` = Mean Earth radius
- `φ₀, λ₀` = Blind spot zone center (e.g. Rohtang Pass KM-42 at `32.3715°N, 77.2472°E`)
- The `cos(φ_mean)` term corrects for meridian convergence at higher latitudes

**Accuracy**: This approximation is valid to < 1 mm error within a 10 km radius — entirely sufficient for mountain road detection zones of < 500 m.

---

### Step 2: Kinematic Velocity Decomposition

GPS devices report heading `θ` in degrees clockwise from North, and speed `v` in km/h. These must be decomposed into Cartesian velocity components in the ENU frame.

First, convert speed to SI units:

$$v_{ms} = \frac{v_{kmh} \times 1000}{3600}$$

Then decompose using the navigation heading convention (`0° = North = +y`, `90° = East = +x`):

$$v_x = v_{ms} \cdot \sin(\theta)$$
$$v_y = v_{ms} \cdot \cos(\theta)$$

The resulting **velocity vector** for each vehicle is:

$$\vec{v} = \begin{pmatrix} v_x \\ v_y \end{pmatrix} \quad \text{[m/s in ENU frame]}$$

---

### Step 3: Trajectory Extrapolation

Using Newton's First Law of Motion (constant velocity assumption over the lookahead horizon `T_H = 10 s`), the future position of a vehicle at time offset `t` is:

$$\vec{p}(t) = \vec{p}_0 + \vec{v} \cdot t \qquad \text{for } 0 \leq t \leq T_H$$

Where:
- `p₀ = (x₀, y₀)` is the current ENU position
- `v = (vₓ, vᵧ)` is the velocity vector from Step 2
- `t` is the time offset in seconds (sampled at 1 s intervals)

This generates a **10-point trajectory polyline** for each vehicle, rendered as the neon directional arrow on the Flutter map.

> **Why constant-velocity?** On steep mountain hairpins, the lookahead window is short (≤ 10 s), and GPS telemetry is typically 2–4 Hz. A constant-velocity model matches GPS measurement assumptions and is computationally trivial compared to model-predictive approaches.

---

### Step 4: Relative Velocity & Closing Speed

For a vehicle pair `(A, B)`, define:

**Relative position vector** (from A to B):
$$\vec{r}_{rel} = \vec{p}_B - \vec{p}_A = \begin{pmatrix} x_B - x_A \\ y_B - y_A \end{pmatrix}$$

**Current separation distance**:
$$d = \|\vec{r}_{rel}\| = \sqrt{(x_B - x_A)^2 + (y_B - y_A)^2}$$

**Relative velocity vector** (motion of B as observed from A's reference frame):
$$\vec{v}_{rel} = \vec{v}_B - \vec{v}_A = \begin{pmatrix} v_{Bx} - v_{Ax} \\ v_{By} - v_{Ay} \end{pmatrix}$$

**Relative speed magnitude**:
$$\|\vec{v}_{rel}\| = \sqrt{(v_{Bx} - v_{Ax})^2 + (v_{By} - v_{Ay})^2}$$

**Closing speed** (rate at which separation is decreasing; positive = vehicles approaching):
$$v_{closing} = -\frac{\vec{r}_{rel} \cdot \vec{v}_{rel}}{\|\vec{r}_{rel}\|}$$

The dot product `r_rel · v_rel` is negative when the vehicles are converging, so the negation makes `v_closing` positive during an approach.

A vehicle pair is flagged as **actively closing** when:

$$v_{closing} > v_{min} = 5 \text{ km/h}$$

---

### Step 5: Closest Point of Approach (CPA)

The **CPA** is the future moment when the two vehicles will be nearest to each other along their linear extrapolated paths. It answers: *"Even if they don't hit, how close will they get?"*

**CPA time** (minimise `‖r_rel(t)‖²` by setting derivative to zero):

$$t_{cpa} = -\frac{\vec{r}_{rel} \cdot \vec{v}_{rel}}{\|\vec{v}_{rel}\|^2}$$

Only valid for `t_cpa > 0` (in the future). If `t_cpa ≤ 0`, vehicles are already diverging.

**Predicted CPA positions**:
$$\vec{p}_A(t_{cpa}) = \vec{p}_A + \vec{v}_A \cdot t_{cpa}$$
$$\vec{p}_B(t_{cpa}) = \vec{p}_B + \vec{v}_B \cdot t_{cpa}$$

**Minimum separation at CPA**:
$$d_{cpa} = \|\vec{p}_B(t_{cpa}) - \vec{p}_A(t_{cpa})\|$$

A **CPA Threat** is triggered when ALL of the following hold:

$$t_{cpa} > 0 \quad \wedge \quad t_{cpa} \leq T_{TTC} = 7.5\text{ s} \quad \wedge \quad d_{cpa} \leq D_{road} = 16\text{ m}$$

where `D_road = 16 m` represents the effective width of a single-lane mountain road including the reaction envelope.

---

### Step 6: 2D Trajectory Intersection

Rather than waiting for the CPA condition, the system also geometrically checks whether the two trajectory **line segments** cross each other in 2D space within the 10-second horizon — a more aggressive early warning.

Define trajectory line segments as parametric vectors:
$$\vec{L}_A(u) = \vec{p}_A + u \cdot (\vec{v}_A \cdot T_H), \qquad u \in [0, 1]$$
$$\vec{L}_B(w) = \vec{p}_B + w \cdot (\vec{v}_B \cdot T_H), \qquad w \in [0, 1]$$

Solve for the intersection by setting `L_A(u) = L_B(w)`:

$$\Delta x = x_B - x_A, \qquad \Delta y = y_B - y_A$$

$$D = d_{1x} \cdot d_{2y} - d_{1y} \cdot d_{2x} \qquad \text{(2D cross product / determinant)}$$

where `d₁ = v_A · T_H` and `d₂ = v_B · T_H`.

$$u = \frac{\Delta x \cdot d_{2y} - \Delta y \cdot d_{2x}}{D}, \qquad w = \frac{\Delta x \cdot d_{1y} - \Delta y \cdot d_{1x}}{D}$$

An intersection exists **within the horizon** when:

$$0 \leq u \leq 1 \quad \wedge \quad 0 \leq w \leq 1$$

The corresponding real-world times are:

$$t_A = u \cdot T_H, \qquad t_B = w \cdot T_H$$

**Special case — Collinear head-on collision** (vehicles on the same road line, `D ≈ 0`):

Test collinearity via the cross product of the displacement and direction:

$$C = \Delta x \cdot v_{Ay} - \Delta y \cdot v_{Ax} \approx 0$$

If collinear and the dot product of velocity directions is negative (vehicles facing each other):

$$\vec{v}_A \cdot \vec{v}_B < 0$$

Then the head-on collision time is:

$$t_{collide} = \frac{\|\vec{r}_{rel}\|}{\|\vec{v}_A\| + \|\vec{v}_B\|}$$

**Intersection Threat** is triggered when:

$$\min(t_A, t_B) \leq T_{TTC} \quad \wedge \quad |t_A - t_B| \leq 3.5\text{ s}$$

The `Δt ≤ 3.5 s` constraint ensures both vehicles reach the crossing zone within 3.5 seconds of each other — a simultaneous occupancy window.

---

### Step 7: Blind Spot Polygon Ray-Casting

Not all close approaches are dangerous. Two vehicles reversing into a parking lot may trigger the CPA test. The system only elevates a warning if the collision point (or the vehicles themselves) fall **within or near a designated Blind Spot Zone polygon**.

Each blind spot zone is stored as a closed polygon in geographic coordinates:

```json
{
  "id": "bs_rohtang_km42",
  "polygon": [
    [77.2462, 32.3708],
    [77.2482, 32.3708],
    [77.2485, 32.3726],
    [77.2461, 32.3726],
    [77.2462, 32.3708]
  ]
}
```

**Ray-Casting Algorithm** for point-in-polygon (`P = (x, y)`):

Cast a horizontal ray from P to `x = +∞`. Count crossings with each polygon edge `(V_i, V_j)`:

$$\text{crossing} = \left( y_i > y \;\neq\; y_j > y \right) \;\wedge\; \left( x < \frac{(x_j - x_i)(y - y_i)}{y_j - y_i} + x_i \right)$$

An **odd** number of crossings means P is **inside** the polygon:

$$P \in \text{Zone} \iff \sum \text{crossings} \equiv 1 \pmod{2}$$

Additionally, vehicles within a **75 m buffer** of any zone boundary are considered "approaching zone":

$$d_{haversine}(P, V_i) \leq 75 \text{ m} \implies \text{Zone Proximity TRUE}$$

The Haversine distance formula used for boundary-vertex proximity:

$$a = \sin^2\!\left(\frac{\Delta\phi}{2}\right) + \cos\phi_1 \cos\phi_2 \sin^2\!\left(\frac{\Delta\lambda}{2}\right)$$

$$d = 2 R_E \arctan2\!\left(\sqrt{a},\, \sqrt{1-a}\right)$$

---

### Step 8: Unified Threat Decision Function

All the above metrics are combined into a single **Boolean threat gate**. An alert is fired if and only if **all four** of the following conditions are simultaneously satisfied:

$$\boxed{\text{ALERT} = \underbrace{v_{closing} > 5\text{ km/h}}_{\text{(1) Closing}} \;\wedge\; \underbrace{(C_{CPA} \;\vee\; C_{INT})}_{\text{(2) Collision path}} \;\wedge\; \underbrace{C_{ZONE}}_{\text{(3) In blind spot}}}$$

Where:

| Condition | Expression | Meaning |
|:---|:---|:---|
| **(1) Closing** | `v_closing > 5 km/h` | Vehicles are actively converging |
| **(2a) CPA Threat** `C_CPA` | `0 < t_cpa ≤ 7.5 s` AND `d_cpa ≤ 16 m` | CPA is imminent and within road-width |
| **(2b) Intersection Threat** `C_INT` | `min(tA, tB) ≤ 7.5 s` AND `Δt ≤ 3.5 s` | Trajectory paths cross simultaneously |
| **(3) Zone** `C_ZONE` | `P_A ∈ Zone` OR `P_B ∈ Zone` OR `P_impact ∈ Zone` | Impact point or vehicles near defined hazard |

The final **Time-To-Collision** reported to drivers:

$$TTC = \begin{cases} \min(t_A, t_B) & \text{if Intersection Threat active} \\ t_{cpa} & \text{if CPA Threat active} \end{cases}$$

---

### Step 9: Severity Classification

Based on TTC, the system classifies the alert severity:

$$\text{Severity} = \begin{cases} \textbf{CRITICAL} & \text{if } TTC < 4.0 \text{ s} \\ \textbf{WARNING} & \text{if } 4.0 \leq TTC \leq 7.5 \text{ s} \end{cases}$$

| Severity | TTC Range | Advisory Action | Flutter Banner Colour |
|:---|:---|:---|:---|
| `WARNING` | 4.0 s – 7.5 s | "Opposing vehicle approaching blind curve. Reduce speed." | Neon amber |
| `CRITICAL` | < 4.0 s | "EMERGENCY: Immediate collision! HARD BRAKE & SOUND HORN!" | Pulsing crimson `#FF0055` |

---

## Tech Stack

| Layer | Technology | Purpose |
|:---|:---|:---|
| **Backend Runtime** | Node.js v24 | Real-time telemetry event loop |
| **HTTP Server** | Express.js | REST API + static Flutter web file serving |
| **WebSocket Transport** | Socket.io v4 | Bidirectional sub-100ms telemetry & alert events |
| **Vector Mathematics** | Pure JavaScript (`geometry.js`) | ENU projection, CPA, ray-casting |
| **Mobile / Desktop / Web** | Flutter 3.47 (Dart 3.13) | Cross-platform cockpit application |
| **Vector Map Rendering** | MapLibre GL (`maplibre_gl: ^0.27.1`) | GPU-accelerated OSM vector tile rendering |
| **WebSocket Client (Flutter)** | `socket_io_client: ^3.1.6` | Real-time event subscriptions |

---

## Backend API Reference

### REST Endpoints

| Method | Endpoint | Description |
|:---|:---|:---|
| `GET` | `/api/status` | Server health: uptime, vehicle count, alert count |
| `GET` | `/api/blind-spots` | All registered blind spot zone definitions (GeoJSON polygons) |
| `GET` | `/api/vehicles` | All currently active vehicle states with projected trajectories |
| `POST` | `/api/telemetry` | Submit a telemetry payload via HTTP (alternative to WebSocket) |

### Socket.io Events

| Direction | Event | Payload Summary |
|:---|:---|:---|
| Client → Server | `telemetry` | `{ deviceId, latitude, longitude, speed, heading, timestamp }` |
| Client → Server | `clear_vehicles` | Wipes all active vehicle states (for demo reset) |
| Server → Client | `init_state` | Full initial state on connect: vehicles, blind spots, active alerts |
| Server → Client | `telemetry_stream` | All current vehicle states + projected trajectories (every tick) |
| Server → Client | `collision_alert` | Full alert object: TTC, closing speed, CPA, impact coordinates, advisory |
| Server → Client | `collision_resolved` | Alert cleared — vehicles safely passed or diverged |

---

## Flutter Frontend Features

### Map Layers

| Layer Type | Vehicles | Content |
|:---|:---|:---|
| `SymbolLayer` | Alpha (Cyan `#00F0FF`) | Vehicle marker with ID, speed, heading rotation |
| `SymbolLayer` | Bravo (Amber `#FFB703`) | Vehicle marker with ID, speed, heading rotation |
| `LineLayer` | Alpha | Neon cyan projected 10-second trajectory vector |
| `LineLayer` | Bravo | Neon amber projected 10-second trajectory vector |
| `LineLayer` | Hazard Zone | Neon red perimeter of blind spot polygon |
| `SymbolLayer` | Impact Beacon | `💥` marker at predicted collision coordinates |

### HUD Cockpit Instruments

- **Digital Speedometer**: Real-time tracked speed of primary vehicle (km/h).
- **Relative Closing Speed**: Dynamically computed `v_closing` between all active vehicle pairs (km/h).
- **Compass Bearing**: Vehicle heading in degrees with cardinal direction label.
- **Zone Badge**: Name of the active hazard zone currently armed for monitoring.
- **Connection Health**: WebSocket link status + latency ping (ms).

### Collision Alert Banner

Displayed as a full-width, pulsing modal when `ALERT = TRUE`:

- **TTC Countdown** (large, centred): e.g. `4.2 s` — updates every 500ms.
- **Closing Speed**: `v_closing` in km/h.
- **Separation Distance**: Current geodesic gap between vehicles in metres.
- **CPA Distance**: Predicted minimum separation at closest approach.
- **Emergency Advisory**: Driver action text from the severity table above.

---

## Configuration Thresholds

All safety thresholds are centralised in [`backend/server.js`](backend/server.js):

```js
const CONFIG = {
  TRAJECTORY_HORIZON_SEC:  10,    // Lookahead window for trajectory projection (seconds)
  TTC_SAFETY_THRESHOLD_SEC: 7.5,  // Maximum TTC before alert is triggered (seconds)
  CPA_MAX_DISTANCE_METERS:  16.0, // Maximum CPA separation for danger (meters ≈ single-lane road)
  MIN_CLOSING_SPEED_KMH:    5.0,  // Minimum closing speed to flag convergence (km/h)
  INACTIVE_PRUNE_MS:       15000  // Remove vehicle if silent for this duration (ms)
};
```

> **Tuning**: For urban deployments with wider roads, increase `CPA_MAX_DISTANCE_METERS`. For faster-moving vehicles on NH highways, reduce `TTC_SAFETY_THRESHOLD_SEC`.

---

## How to Run

### 1. Install Backend Dependencies

```powershell
cd "c:\flutter app\pahadi_maps\backend"
npm install
```

### 2. Run Math Unit Tests

```powershell
npm test
```

Expected output:
```
>>> ALL GEOMETRY & VECTOR MATHEMATICS TESTS PASSED! <<<
```

### 3. Start Backend Server

```powershell
npm start
```

The server will boot at:
- **Flutter App**: `http://localhost:3000` (serves pre-built web assets)
- **REST API**: `http://localhost:3000/api/status`
- **WebSocket**: `ws://localhost:3000`

### 4. Run Mountain Road Simulator (separate terminal)

```powershell
npm run sim
```

Vehicle-Alpha (downhill tanker) and Vehicle-Bravo (uphill SUV) will negotiate the Rohtang Pass KM-42 hairpin curve and trigger live collision alerts as they approach the blind apex.

### 5. Launch Flutter Cockpit

**Option A — Web via Node.js** (open `http://localhost:3000` in your browser after `npm start`):
```powershell
flutter build web --no-pub
npm start
```

**Option B — Flutter web-server** (with Hot Reload):
```powershell
cd "c:\flutter app\pahadi_maps"
flutter run -d web-server --web-port 8080 --web-hostname 127.0.0.1
```
Then open **http://127.0.0.1:8080** in Edge or Chrome.

**Option C — Native Windows Desktop** (no browser needed):
```powershell
flutter run -d windows
```

---

## Test Verification

### Backend Math Tests (`node test/test_math.js`)

| Test | Input | Expected | Result |
|:---|:---|:---|:---|
| ENU Origin Projection | `(φ₀, λ₀) → (φ₀, λ₀)` | `x = 0, y = 0` | ✅ Pass |
| Velocity Vector | `36 km/h @ 90°` | `vx = 10 m/s, vy ≈ 0` | ✅ Pass |
| Head-On CPA | A@(-50,0) 10m/s East, B@(50,0) 10m/s West | `d=100m, v_close=72km/h, TTC=5s, d_cpa=0m` | ✅ Pass |
| Collinear Intersection | Same as above | `t_intersect = 5s, x_impact = 0` | ✅ Pass |
| Point-in-Polygon | Point inside 5-vertex zone polygon | `true` | ✅ Pass |
| Point-outside-Polygon | Point outside zone | `false` | ✅ Pass |

### Flutter Tests (`flutter test`)

| Test | Result |
|:---|:---|
| `VehicleTelemetry.fromJson()` parsing | ✅ Pass |
| `CollisionAlert.fromJson()` parsing | ✅ Pass |
| Dashboard renders status readout | ✅ Pass |
| Dashboard renders 4 sensor cards | ✅ Pass |
| FAB toggles system status text | ✅ Pass |

### Static Analysis (`flutter analyze`)

```
No issues found!
```

### Production Build (`flutter build web`)

```
√ Built build\web
```
