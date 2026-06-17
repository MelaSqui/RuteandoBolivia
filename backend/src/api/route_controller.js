const express = require('express');
const router = express.Router();
const routeGraph = require('./route_graph');
const logger = require('../utils/logger');
const { supabase } = require('../storage/supabase-client');

// Helper para obtener los bloqueos activos
async function getActiveRoadblocks() {
  const { data, error } = await supabase
    .from('road_events')
    .select('latitud_inicio, longitud_inicio');
    
  if (error) {
    logger.error('Error obteniendo bloqueos para ruteo: ' + error.message);
    return [];
  }
  return data || [];
}

router.get('/calculate', async (req, res) => {
  try {
    const { origin, destination } = req.query;
    
    if (!origin || !destination) {
      return res.status(400).json({ error: 'Origin and destination coordinates are required' });
    }

    const [olat, olng] = origin.split(',').map(Number);
    const [dlat, dlng] = destination.split(',').map(Number);

    if (!routeGraph.isLoaded) {
      return res.status(503).json({ error: 'El motor de ruteo está inicializándose. Intente en unos momentos.' });
    }

    // Obtener los bloqueos activos y aplicarlos al grafo
    const roadblocks = await getActiveRoadblocks();
    routeGraph.updateRoadblockCosts(roadblocks);

    // Calcular la ruta óptima (Dijkstra/A* in memory)
    logger.info(`Calculando ruta desde [${olng}, ${olat}] hasta [${dlng}, ${dlat}]`);
    
    // Note: geojson-path-finder uses [lng, lat]
    const route = routeGraph.findRoute([olng, olat], [dlng, dlat]);

    if (!route) {
      return res.status(404).json({ error: 'No se encontró una ruta posible entre esos puntos debido a bloqueos totales o vías no mapeadas.' });
    }

    // Devolver formato estándar OSRM-like para que el frontend lo dibuje
    const polyline = route.path.map(coord => ({
      latitude: coord[1],
      longitude: coord[0]
    }));

    return res.json({
      routes: [
        {
          polyline: polyline,
          distance_km: route.distanceKm,
          duration_min: route.distanceKm * 0.9, // Estimación burda (1km = 0.9 min en carreteras)
          summary: 'Ruta Óptima Calculada'
        }
      ]
    });

  } catch (err) {
    logger.error('Error calculando ruta: ' + err.message);
    return res.status(500).json({ error: 'Internal server error calculating route' });
  }
});

module.exports = router;
