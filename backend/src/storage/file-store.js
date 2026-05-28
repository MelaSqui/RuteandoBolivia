const fs = require('fs');
const path = require('path');
const zlib = require('zlib');
const { promisify } = require('util');
const config = require('../config');
const logger = require('../utils/logger');

const gzip = promisify(zlib.gzip);
const gunzip = promisify(zlib.gunzip);

/**
 * Almacena y recupera snapshots de datos como JSON comprimido con gzip.
 */
class FileStore {
  constructor(dataDir) {
    this.dataDir = dataDir || config.storage.dataDir;
    this._ensureDir();
  }

  _ensureDir() {
    if (!fs.existsSync(this.dataDir)) {
      fs.mkdirSync(this.dataDir, { recursive: true });
      logger.info({ dir: this.dataDir }, 'Directorio de datos creado');
    }
  }

  /**
   * Genera el nombre de archivo para un snapshot.
   * @param {Date} date
   * @returns {string}
   */
  _filename(date) {
    return date.toISOString().replace(/[:.]/g, '-') + '.json.gz';
  }

  /**
   * Guarda un snapshot de datos comprimido.
   * @param {object} data - Datos a almacenar
   * @param {Date} [timestamp] - Timestamp del snapshot
   * @returns {Promise<string>} Ruta del archivo guardado
   */
  async save(data, timestamp = new Date()) {
    const snapshot = {
      timestamp: timestamp.toISOString(),
      source: 'transitabilidad.abc.gob.bo',
      version: 1,
      scrapedAt: new Date().toISOString(),
      data,
    };

    const json = JSON.stringify(snapshot);
    const compressed = await gzip(Buffer.from(json, 'utf-8'));

    const filename = this._filename(timestamp);
    const filepath = path.join(this.dataDir, filename);

    fs.writeFileSync(filepath, compressed);

    logger.info(
      {
        file: filename,
        originalSize: json.length,
        compressedSize: compressed.length,
        ratio: ((compressed.length / json.length) * 100).toFixed(1) + '%',
      },
      'Snapshot guardado'
    );

    return filepath;
  }

  /**
   * Carga un snapshot por nombre de archivo.
   * @param {string} filename
   * @returns {Promise<object>}
   */
  async load(filename) {
    const filepath = path.join(this.dataDir, filename);
    const compressed = fs.readFileSync(filepath);
    const json = await gunzip(compressed);
    return JSON.parse(json.toString('utf-8'));
  }

  /**
   * Lista todos los snapshots almacenados, ordenados del más reciente al más antiguo.
   * @returns {string[]} Lista de nombres de archivo
   */
  listSnapshots() {
    if (!fs.existsSync(this.dataDir)) return [];
    return fs
      .readdirSync(this.dataDir)
      .filter((f) => f.endsWith('.json.gz'))
      .sort()
      .reverse();
  }

  /**
   * Obtiene el snapshot más reciente.
   * @returns {Promise<object|null>}
   */
  async getLatest() {
    const snapshots = this.listSnapshots();
    if (snapshots.length === 0) return null;
    return this.load(snapshots[0]);
  }

  /**
   * Elimina snapshots más antiguos que el TTL especificado.
   * @param {number} maxAgeDays - Edad máxima en días
   * @returns {number} Número de snapshots eliminados
   */
  cleanup(maxAgeDays = 7) {
    const cutoff = new Date(Date.now() - maxAgeDays * 24 * 60 * 60 * 1000);
    const snapshots = this.listSnapshots();
    let deleted = 0;

    for (const filename of snapshots) {
      // Extraer fecha del nombre de archivo
      const dateStr = filename.replace('.json.gz', '').replace(/-(\d{2})-(\d{2})-(\d+)Z$/, ':$1:$2.$3Z');
      try {
        const fileDate = new Date(dateStr);
        if (fileDate < cutoff) {
          fs.unlinkSync(path.join(this.dataDir, filename));
          deleted++;
        }
      } catch {
        // Si no se puede parsear la fecha, ignorar
      }
    }

    if (deleted > 0) {
      logger.info({ deleted, maxAgeDays }, 'Snapshots antiguos eliminados');
    }

    return deleted;
  }
}

module.exports = FileStore;
