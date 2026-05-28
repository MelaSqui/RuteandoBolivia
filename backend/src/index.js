const config = require('./config');
const logger = require('./utils/logger');
const { scrape } = require('./scraper/data-extractor');

const THREE_HOURS_MS = 3 * 60 * 60 * 1000;
const TEN_MINUTES_MS = 10 * 60 * 1000;

let timeoutId = null;

logger.info(
  { target: config.scrape.targetUrl },
  'RuteandoBolivia API Scraper iniciando (Scheduler dinámico)'
);

runScrapeLoop();

async function runScrapeLoop() {
  logger.info('Iniciando ciclo de extracción directa');
  
  let success = false;
  try {
    const data = await scrape();
    logger.info('Extracción completada con éxito');
    success = true;
  } catch (err) {
    logger.error({ error: err.message, stack: err.stack }, 'Extracción fallida');
    success = false;
  }

  const nextDelayMs = success ? THREE_HOURS_MS : TEN_MINUTES_MS;
  const nextDelayMinutes = nextDelayMs / 1000 / 60;
  
  logger.info(
    { success, delayMinutes: nextDelayMinutes },
    `Próximo intento programado en ${nextDelayMinutes} minutos`
  );

  timeoutId = setTimeout(runScrapeLoop, nextDelayMs);
}

// ── Graceful shutdown ──
function shutdown(signal) {
  logger.info({ signal }, 'Señal de shutdown recibida');
  if (timeoutId) {
    clearTimeout(timeoutId);
  }
  process.exit(0);
}

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));
