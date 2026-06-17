const fs = require('fs');
const path = require('path');
const https = require('https');
const osmtogeojson = require('osmtogeojson');
const logger = require('./logger');

const DATA_DIR = path.join(__dirname, '../../data');
const OSM_FILE = path.join(DATA_DIR, 'bolivia_roads.osm.json');
const GEOJSON_FILE = path.join(DATA_DIR, 'road_network.json');

// Consulta Overpass: Carreteras principales y secundarias en Bolivia
// Se usa un bounding box o searchArea. Usaremos searchArea de Bolivia.
const OVERPASS_QUERY = `
[out:json][timeout:300];
area["ISO3166-1"="BO"]->.searchArea;
(
  way["highway"~"trunk|primary|secondary"](area.searchArea);
);
out body;
>;
out skel qt;
`;

async function fetchRoadNetwork() {
  logger.info('Iniciando descarga de grafo vial desde Overpass API (OSM)...');

  if (!fs.existsSync(DATA_DIR)) {
    fs.mkdirSync(DATA_DIR, { recursive: true });
  }

  const data = `data=${encodeURIComponent(OVERPASS_QUERY)}`;

  const options = {
    hostname: 'overpass-api.de',
    path: '/api/interpreter',
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
      'Content-Length': Buffer.byteLength(data),
      'User-Agent': 'RuteandoBolivia/1.0',
    },
  };

  return new Promise((resolve, reject) => {
    const req = https.request(options, (res) => {
      logger.info(`Overpass API status: ${res.statusCode}`);
      let rawData = '';

      res.on('data', (chunk) => {
        rawData += chunk;
      });

      res.on('end', () => {
        if (res.statusCode !== 200) {
          return reject(new Error(`Overpass API Error: ${rawData}`));
        }
        
        try {
          const osmJson = JSON.parse(rawData);
          logger.info(`Descarga completa. Elementos OSM obtenidos: ${osmJson.elements?.length || 0}`);
          
          logger.info('Convirtiendo OSM a GeoJSON...');
          const geoJson = osmtogeojson(osmJson);
          
          fs.writeFileSync(GEOJSON_FILE, JSON.stringify(geoJson), 'utf8');
          logger.info(`Red ruteable guardada en ${GEOJSON_FILE}`);
          
          resolve(geoJson);
        } catch (e) {
          reject(new Error('Error parseando OSM JSON o convirtiendo a GeoJSON: ' + e.message));
        }
      });
    });

    req.on('error', (e) => reject(e));
    req.write(data);
    req.end();
  });
}

if (require.main === module) {
  fetchRoadNetwork().catch(console.error);
}

module.exports = { fetchRoadNetwork };
