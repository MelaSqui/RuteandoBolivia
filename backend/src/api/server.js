const express = require('express');
const cors = require('cors');
const logger = require('../utils/logger');
const { supabase } = require('../storage/supabase-client');

const app = express();
const PORT = process.env.PORT || 3000;

const routeGraph = require('./route_graph');
const routeController = require('./route_controller');

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

// Nuevo motor de ruteo
app.use('/api/route', requireAuth, routeController);

app.listen(PORT, async () => {
  logger.info(`🚀 API Server running on port ${PORT}`);
  
  // Cargar el grafo vial en memoria
  routeGraph.loadGraph();

  // Escuchar eventos en tiempo real de Supabase
  if (supabase) {
    logger.info('Suscrito a eventos en tiempo real (road_events) para actualizar ruteo...');
    supabase.channel('custom-all-channel')
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'road_events' },
        (payload) => {
          logger.info(`Evento detectado en road_events (${payload.eventType}). Actualizando pesos del grafo...`);
          // Idealmente, pedimos de nuevo los bloqueos activos:
          supabase.from('road_events').select('latitud_inicio, longitud_inicio').then(({ data }) => {
             if (data) routeGraph.updateRoadblockCosts(data);
          });
        }
      )
      .subscribe();
  }
});
