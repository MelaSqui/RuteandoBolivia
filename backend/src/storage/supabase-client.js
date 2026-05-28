const { createClient } = require('@supabase/supabase-js');
const config = require('../config');
const logger = require('../utils/logger');

let supabaseUrl = config.supabase.url;
let supabaseKey = config.supabase.serviceRoleKey || config.supabase.anonKey;

const supabase = supabaseUrl && supabaseKey ? createClient(supabaseUrl, supabaseKey) : null;

if (!supabase) {
  logger.warn('Supabase no está configurado correctamente. Las actualizaciones de DB serán omitidas.');
}

async function upsertTransitData(data) {
  if (!supabase) return;

  try {
    // 1. Process Road Events
    if (data.data && Array.isArray(data.data)) {
      const roadEventsRaw = data.data.map(item => ({
        id: item.id_registro,
        ruta: item.ruta,
        seccion: item.seccion,
        departamento: item.departamento,
        latitud_inicio: parseFloat(item.latitud_inicio_seccion) || null,
        longitud_inicio: parseFloat(item.longitud_inicio_seccion) || null,
        latitud_fin: parseFloat(item.latitud_fin_seccion) || null,
        longitud_fin: parseFloat(item.longitud_fin_seccion) || null,
        hora_reporte: item.fecha_registro_hora,
        evento: item.evento?.descripcion_evento || item.evento || null,
        transitable_con_desvio: item.transitable_con_desvio?.descripcion_transitable_con_desvio || item.transitable_con_desvio || null,
        restriccion_vehicular: item.restriccion_vehicular?.descripcion_restriccion_vehicular || item.restriccion_vehicular || null,
        tipo_vehiculo: item.tipo_vehiculo?.descripcion_tipo_de_vehiculo || item.tipo_vehiculo || null,
        trabajos_conservacion: item.trabajos_conservacion?.descripcion_trabajos_conservacion_vial || item.trabajos_conservacion || null,
        raw_data: item
      }));

      // Deduplicate by ID
      const roadEventsMap = new Map();
      roadEventsRaw.forEach(item => {
        if (item.id) roadEventsMap.set(item.id, item);
      });
      const roadEvents = Array.from(roadEventsMap.values());

      const { error } = await supabase
        .from('road_events')
        .upsert(roadEvents, { onConflict: 'id' });
        
      if (error) throw new Error(`Road Events Error: ${error.message}`);
      logger.info(`Upserted ${roadEvents.length} road events to Supabase`);
    }

    // 2. Process Service Stations
    if (data.serviceStations && Array.isArray(data.serviceStations)) {
      const stationsRaw = data.serviceStations.map(item => ({
        id: item.id_gasolinera,
        nombre: item.referencia,
        departamento: item.departamento || item.depa,
        latitud: parseFloat(item.latitud) || null,
        longitud: parseFloat(item.longitud) || null,
        raw_data: item
      }));

      const stationsMap = new Map();
      stationsRaw.forEach(item => {
        if (item.id) stationsMap.set(item.id, item);
      });
      const stations = Array.from(stationsMap.values());

      const { error } = await supabase
        .from('service_stations')
        .upsert(stations, { onConflict: 'id' });

      if (error) throw new Error(`Service Stations Error: ${error.message}`);
      logger.info(`Upserted ${stations.length} service stations to Supabase`);
    }

    // 3. Process Toll Booths (Retenes)
    if (data.retenes && Array.isArray(data.retenes)) {
      const tollsRaw = data.retenes.map(item => ({
        id: item.id_reten,
        nombre: item.reten,
        departamento: item.departamento,
        latitud: parseFloat(item.latitud) || null,
        longitud: parseFloat(item.longitud) || null,
        raw_data: item
      }));

      const tollsMap = new Map();
      tollsRaw.forEach(item => {
        if (item.id) tollsMap.set(item.id, item);
      });
      const tolls = Array.from(tollsMap.values());

      const { error } = await supabase
        .from('toll_booths')
        .upsert(tolls, { onConflict: 'id' });

      if (error) throw new Error(`Toll Booths Error: ${error.message}`);
      logger.info(`Upserted ${tolls.length} toll booths to Supabase`);
    }

  } catch (err) {
    logger.error({ error: err.message }, 'Failed to upsert data to Supabase');
  }
}

module.exports = {
  supabase,
  upsertTransitData
};
