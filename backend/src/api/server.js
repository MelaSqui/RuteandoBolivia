const express = require('express');
const cors = require('cors');
const logger = require('../utils/logger');
const { supabase } = require('../storage/supabase-client');

const app = express();
const PORT = process.env.PORT || 3000;

app.use(cors());
app.use(express.json());

// Authentication Middleware using Supabase
const requireAuth = async (req, res, next) => {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Unauthorized: Missing token' });
  }

  const token = authHeader.split(' ')[1];
  
  // Verify token with Supabase
  const { data: { user }, error } = await supabase.auth.getUser(token);

  if (error || !user) {
    logger.warn({ error: error?.message }, 'Invalid authentication attempt');
    return res.status(401).json({ error: 'Unauthorized: Invalid token' });
  }

  req.user = user;
  next();
};

// Health Check
app.get('/health', (req, res) => {
  res.json({ status: 'ok', supabaseConnected: !!supabase });
});

// GET Road Events
app.get('/api/events', requireAuth, async (req, res) => {
  try {
    const { data, error } = await supabase
      .from('road_events')
      .select('*')
      .order('updated_at', { ascending: false });

    if (error) throw error;
    res.json(data);
  } catch (error) {
    logger.error({ error: error.message }, 'Error fetching road events');
    res.status(500).json({ error: 'Internal Server Error' });
  }
});

// GET Service Stations
app.get('/api/stations', requireAuth, async (req, res) => {
  try {
    const { data, error } = await supabase
      .from('service_stations')
      .select('*');

    if (error) throw error;
    res.json(data);
  } catch (error) {
    logger.error({ error: error.message }, 'Error fetching service stations');
    res.status(500).json({ error: 'Internal Server Error' });
  }
});

// GET Toll Booths
app.get('/api/tolls', requireAuth, async (req, res) => {
  try {
    const { data, error } = await supabase
      .from('toll_booths')
      .select('*');

    if (error) throw error;
    res.json(data);
  } catch (error) {
    logger.error({ error: error.message }, 'Error fetching toll booths');
    res.status(500).json({ error: 'Internal Server Error' });
  }
});

app.listen(PORT, () => {
  logger.info(`🚀 API Server running on port ${PORT}`);
});
