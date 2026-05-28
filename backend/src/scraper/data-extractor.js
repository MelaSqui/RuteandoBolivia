const FileStore = require('../storage/file-store');
const logger = require('../utils/logger');
const config = require('../config');
const { upsertTransitData } = require('../storage/supabase-client');

const store = new FileStore();

/**
 * Ejecuta un ciclo de scraping directamente desde la API JSON.
 *
 * @returns {Promise<object>} Datos del snapshot guardado
 */
async function scrape() {
  const startTime = Date.now();
  const baseUrl = config.scrape.targetUrl;

  const endpoints = [
    { key: 'data', path: '/api/v1/data' },
    { key: 'serviceStations', path: '/api/v1/serviceStations' },
    { key: 'retenes', path: '/api/v1/retenes' },
    { key: 'eventsDictionary', path: '/api/v1/events' },
  ];

  logger.info('Iniciando extracción directa de la API JSON...');
  
  const result = {};

  for (const endpoint of endpoints) {
    try {
      const url = `${baseUrl}${endpoint.path}`;
      logger.info(`Extrayendo ${endpoint.key} desde ${url}`);
      
      const response = await fetch(url, {
        method: 'GET',
        headers: {
          'Accept': 'application/json',
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'
        },
      });

      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`);
      }

      result[endpoint.key] = await response.json();
    } catch (error) {
      logger.error(`Error extrayendo ${endpoint.key}: ${error.message}`);
      result[endpoint.key] = { error: error.message };
    }
  }

  // Almacenar snapshot
  const timestamp = new Date();
  const filepath = await store.save(result, timestamp);

  // Limpieza de snapshots antiguos (>7 días)
  store.cleanup(7);

  // Guardar en Supabase
  await upsertTransitData(result);

  const elapsed = ((Date.now() - startTime) / 1000).toFixed(1);
  logger.info({ elapsed: `${elapsed}s`, filepath }, 'Ciclo de extracción completado con éxito');

  return result;
}

module.exports = { scrape };
