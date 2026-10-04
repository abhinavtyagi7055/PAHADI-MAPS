const express = require('express');
const cors = require('cors');

const app = express();
app.use(cors());
app.use(express.json());

// Add this root route so visiting localhost:3000 doesn't error out
app.get('/', (req, res) => {
  res.send('Pahadi Maps Backend is running successfully!');
});

// Mock database of locations
let locations = [
  { id: 1, name: 'Gaur City Mall', latitude: 28.6139, longitude: 77.4278 },
  { id: 2, name: 'Connaught Place', latitude: 28.6280, longitude: 77.2090 }
];

// GET endpoint to fetch markers
app.get('/api/locations', (req, res) => {
  res.json(locations);
});

// POST endpoint to add a new marker
app.post('/api/locations', (req, res) => {
  const { name, latitude, longitude } = req.body;
  const newLoc = { id: locations.length + 1, name, latitude, longitude };
  locations.push(newLoc);
  res.status(201).json(newLoc);
});

const PORT = 3000;
app.listen(PORT, () => console.log(`Backend server running on http://localhost:${PORT}`));