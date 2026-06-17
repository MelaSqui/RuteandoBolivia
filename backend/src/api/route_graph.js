const fs = require('fs');
const path = require('path');
const PathFinder = require('geojson-path-finder').default || require('geojson-path-finder');
const turf = require('@turf/turf');
const logger = require('../utils/logger');

const GEOJSON_FILE = path.join(__dirname, '../../data/road_network.json');

class RouteGraph {
  constructor() {
    this.pathFinder = null;
    this.originalWeights = new Map(); // Store original weights to revert when roadblocks are removed
    this.isLoaded = false;
  }

  loadGraph() {
    if (this.isLoaded) return;
    try {
      logger.info(`Cargando grafo vial desde ${GEOJSON_FILE}...`);
      if (!fs.existsSync(GEOJSON_FILE)) {
        logger.warn('Archivo de red vial no encontrado. Por favor corre el script de descarga.');
        return;
      }
      
      const rawData = fs.readFileSync(GEOJSON_FILE, 'utf8');
      const geojson = JSON.parse(rawData);

      // Limpiar features que no sean LineStrings o Polygons
      const linesGeoJson = {
        type: 'FeatureCollection',
        features: geojson.features.filter(f => f.geometry && (f.geometry.type === 'LineString' || f.geometry.type === 'MultiLineString'))
      };

      logger.info(`Generando topología ruteable con ${linesGeoJson.features.length} vías...`);
      // We pass precision 1e-4 which is ~11 meters to merge close intersections
      this.pathFinder = new PathFinder(linesGeoJson, { precision: 1e-4 });
      this.isLoaded = true;
      logger.info('Grafo cargado en memoria RAM con éxito (Ultra baja latencia).');
    } catch (e) {
      logger.error('Error cargando el grafo: ' + e.message);
    }
  }

  getClosestNode(targetPoint) {
    let closestNode = null;
    let minDistance = Infinity;
    
    // Iterar sobre todos los vértices del grafo compactado
    const vertices = Object.keys(this.pathFinder.graph.compactedVertices);
    
    for (let i = 0; i < vertices.length; i++) {
      const coords = vertices[i].split(',').map(Number);
      // Calcular distancia euclidiana simple (más rápido que Haversine para distancias cortas)
      const dx = coords[0] - targetPoint.geometry.coordinates[0];
      const dy = coords[1] - targetPoint.geometry.coordinates[1];
      const distance = dx * dx + dy * dy;
      
      if (distance < minDistance) {
        minDistance = distance;
        closestNode = turf.point(coords);
      }
    }
    
    return closestNode;
  }

  findRoute(startCoord, endCoord) {
    if (!this.isLoaded) {
      throw new Error('El grafo vial no está cargado.');
    }

    const start = turf.point(startCoord);
    const finish = turf.point(endCoord);

    // Encontrar los vértices más cercanos en el grafo
    const snappedStart = this.getClosestNode(start);
    const snappedFinish = this.getClosestNode(finish);

    if (!snappedStart || !snappedFinish) {
      return null;
    }

    const route = this.pathFinder.findPath(snappedStart, snappedFinish);

    if (route) {
      // route.path is an array of coordinates
      return {
        path: route.path,
        weight: route.weight,
        distanceKm: route.weight // weight is usually distance in km if not weighted
      };
    } else {
      return null; // No route found
    }
  }

  /**
   * Actualiza el costo de las aristas que intersectan o están cerca de un bloqueo.
   */
  updateRoadblockCosts(roadblocks) {
    if (!this.isLoaded) return;

    logger.info(`Aplicando pesos infinitos para ${roadblocks.length} bloqueos activos...`);
    
    // Primero, restaurar pesos originales
    this.restoreOriginalWeights();

    // pathFinder.graph.vertices y edges
    const graph = this.pathFinder.graph;
    
    roadblocks.forEach(block => {
      const { latitud_inicio, longitud_inicio } = block;
      if (!latitud_inicio || !longitud_inicio) return;
      
      const blockPoint = turf.point([parseFloat(longitud_inicio), parseFloat(latitud_inicio)]);

      // Buscar nodos en el grafo cercanos al bloqueo
      // Este enfoque es simple: iteramos los vértices para inhabilitar caminos
      // En producción a gran escala se usa un rtree, pero pathfinder expone el grafo
      
      // Una forma de evitar es hacer las aristas que caigan dentro del radio de bloqueo muy pesadas.
      Object.keys(graph.compactedVertices).forEach(v1Str => {
        const v1Coords = v1Str.split(',').map(Number);
        if (turf.distance(blockPoint, turf.point(v1Coords)) < 2.0) { // 2km de radio
          // Inhabilitar aristas conectadas
          const edges = graph.compactedVertices[v1Str];
          Object.keys(edges).forEach(v2Str => {
            const edgeKey = `${v1Str}->${v2Str}`;
            // Guardar peso original
            if (!this.originalWeights.has(edgeKey)) {
              this.originalWeights.set(edgeKey, edges[v2Str]);
            }
            // Costo infinito
            edges[v2Str] = 99999999;
          });
        }
      });
    });
  }

  restoreOriginalWeights() {
    if (!this.isLoaded) return;
    const graph = this.pathFinder.graph;
    this.originalWeights.forEach((weight, edgeKey) => {
      const [v1Str, v2Str] = edgeKey.split('->');
      if (graph.compactedVertices[v1Str] && graph.compactedVertices[v1Str][v2Str] !== undefined) {
        graph.compactedVertices[v1Str][v2Str] = weight;
      }
    });
    this.originalWeights.clear();
  }
}

// Singleton
module.exports = new RouteGraph();
