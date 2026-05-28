const logger = require('./logger');
const config = require('../config');

/**
 * Ejecuta una función async con reintentos y backoff exponencial.
 * @param {Function} fn - Función async a ejecutar
 * @param {object} opts
 * @param {number} opts.maxRetries - Número máximo de reintentos
 * @param {number} opts.baseDelayMs - Delay base en ms (default 2000)
 * @param {string} opts.label - Etiqueta para logs
 * @returns {Promise<*>} Resultado de la función
 */
async function withRetry(fn, { maxRetries = 10, baseDelayMs = 1000, label = 'operation' } = {}) {
  let lastError;

  for (let attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      logger.info({ attempt, maxRetries, label }, `Intento ${attempt}/${maxRetries}`);
      const result = await fn(attempt);
      return result;
    } catch (err) {
      lastError = err;
      logger.warn(
        { attempt, maxRetries, label, error: err.message },
        `Intento ${attempt} fallido`
      );

      if (err.message.includes('429') && !err.message.includes('[PROXY_DEAD]')) {
        logger.warn({ label }, 'Rate limit en IP local detectado. Abortando reintentos inmediatos.');
        throw err;
      }

      if (attempt < maxRetries) {
        let delay = config.scrape.retryDelayMs;

        logger.info({ delay, label }, `Esperando ${delay}ms antes del siguiente intento`);
        
        if (delay > 0) {
          await new Promise((resolve) => setTimeout(resolve, delay));
        }
      }
    }
  }

  logger.error({ label, error: lastError.message }, `Todos los ${maxRetries} intentos fallaron`);
  throw lastError;
}

module.exports = { withRetry };
