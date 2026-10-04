# Pahadi Telemetry Guard - Backend Engine & Simulator

Real-time geospatial telemetry ingestion, kinematic vector mathematics, and predictive collision alert system tailored for high-risk Himalayan hairpin turns and blind mountain passes.

## Architecture

- **`server.js`**: Express & Socket.io server.
  - Ingests high-frequency device telemetry `{ deviceId, latitude, longitude, speed, heading, timestamp }`.
  - Performs local tangent plane (East-North-Up / ENU) metric conversions.
  - Projects kinematic trajectory vectors: $\vec{p}(t) = \vec{p}_0 + \vec{v} \cdot t$.
  - Solves Closest Point of Approach (CPA), relative velocity, and Time-To-Collision (TTC):
    $$t_{cpa} = -\frac{\vec{r}_{rel} \cdot \vec{v}_{rel}}{\|\vec{v}_{rel}\|^2}, \quad d_{cpa} = \|\vec{r}_{rel} + \vec{v}_{rel} \cdot t_{cpa}\|$$
  - Performs 2D Ray-Casting Point-in-Polygon checks against pre-defined blind curves (e.g. Rohtang Pass KM-42).
  - Emits `collision_alert` when TTC drops below 7.5 seconds and CPA is within collision proximity.
- **`simulation.js`**: Multi-vehicle telemetry generator.
  - Simulates Vehicle-Alpha (downhill tanker) and Vehicle-Bravo (uphill SUV) negotiating the Rohtang Pass KM-42 hairpin curve.
  - Streams live GPS coordinates, speeds, and heading changes at 2 Hz.
  - Logs ASCII tactical radar telemetry and real-time alerts.
- **`src/geometry.js`**: Math library for geodesy, ENU projection, relative kinematics, ray-casting polygon intersection.
- **`test/test_math.js`**: Unit test suite for vector math and polygon containment.

## Quick Start

### 1. Install Dependencies
```bash
npm install
```

### 2. Run Test Suite
```bash
npm test
```

### 3. Start Telemetry Server
```bash
npm start
```
Server runs at `http://localhost:3000`.

### 4. Run Mountain Road Simulator (Separate Terminal)
```bash
npm run sim
```
