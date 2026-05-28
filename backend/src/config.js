require('dotenv').config();

const config = {
  scrape: {
    targetUrl: process.env.SCRAPE_TARGET_URL || 'http://transitabilidad.abc.gob.bo',
  },
  log: {
    level: process.env.LOG_LEVEL || 'info',
  },
  storage: {
    dataDir: process.env.DATA_DIR || './data/snapshots',
  },
  supabase: {
    url: process.env.SUPABASE_URL || null,
    anonKey: process.env.SUPABASE_ANON_KEY || null,
    serviceRoleKey: process.env.SUPABASE_SERVICE_ROLE_KEY || null,
  },
};

module.exports = config;
