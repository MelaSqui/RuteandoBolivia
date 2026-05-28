-- schema.sql
-- Run this in your Supabase SQL Editor

-- 1. Table for Road Events (Transitabilidad)
CREATE TABLE IF NOT EXISTS public.road_events (
    id BIGINT PRIMARY KEY,
    ruta TEXT,
    seccion TEXT,
    departamento TEXT,
    latitud_inicio NUMERIC,
    longitud_inicio NUMERIC,
    latitud_fin NUMERIC,
    longitud_fin NUMERIC,
    hora_reporte TIMESTAMP WITH TIME ZONE,
    evento TEXT,
    transitable_con_desvio TEXT,
    restriccion_vehicular TEXT,
    tipo_vehiculo TEXT,
    trabajos_conservacion TEXT,
    raw_data JSONB,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_road_events_departamento ON public.road_events(departamento);

-- 2. Table for Service Stations (Gasolineras)
CREATE TABLE IF NOT EXISTS public.service_stations (
    id BIGINT PRIMARY KEY,
    nombre TEXT,
    departamento TEXT,
    latitud NUMERIC,
    longitud NUMERIC,
    raw_data JSONB,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 3. Table for Toll Booths (Retenes)
CREATE TABLE IF NOT EXISTS public.toll_booths (
    id BIGINT PRIMARY KEY,
    nombre TEXT,
    departamento TEXT,
    latitud NUMERIC,
    longitud NUMERIC,
    raw_data JSONB,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 4. Enable Row Level Security (RLS)
ALTER TABLE public.road_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.service_stations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.toll_booths ENABLE ROW LEVEL SECURITY;

-- 5. Create Policies for Public Read Access (since the API will fetch these)
CREATE POLICY "Allow public read-only access to road_events"
    ON public.road_events FOR SELECT
    USING (true);

CREATE POLICY "Allow public read-only access to service_stations"
    ON public.service_stations FOR SELECT
    USING (true);

CREATE POLICY "Allow public read-only access to toll_booths"
    ON public.toll_booths FOR SELECT
    USING (true);

-- Note: Inserts will be handled by the backend using the SERVICE_ROLE_KEY which bypasses RLS.
