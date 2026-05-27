-- Script de creación de la tabla `puntos_abc` en Supabase
-- Puedes copiar y pegar esto en el SQL Editor de tu proyecto en Supabase (https://app.supabase.com)

DROP TABLE IF EXISTS public.puntos_abc CASCADE;

CREATE TABLE public.puntos_abc (
    id TEXT PRIMARY KEY,
    tramo TEXT,
    descripcion TEXT,
    estado TEXT,
    causa TEXT,
    latitud DOUBLE PRECISION,
    longitud DOUBLE PRECISION,
    ultima_actualizacion TIMESTAMP WITH TIME ZONE,
    datos_brutos JSONB NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Trigger para actualizar `updated_at` automáticamente
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
   NEW.updated_at = NOW();
   RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_puntos_abc_updated_at
BEFORE UPDATE ON public.puntos_abc
FOR EACH ROW
EXECUTE FUNCTION update_updated_at_column();

-- Habilitar Row Level Security
ALTER TABLE public.puntos_abc ENABLE ROW LEVEL SECURITY;

-- Crear política para permitir la lectura pública a cualquiera que tenga la Anon Key
-- Esto permitirá que la app Flutter lea los puntos sin necesidad de que el usuario haga login.
CREATE POLICY "Permitir lectura publica de puntos" 
ON public.puntos_abc
FOR SELECT 
USING (true);

-- Permitir al scraper (usando anon_key) insertar y actualizar puntos
CREATE POLICY "Permitir insert al scraper" 
ON public.puntos_abc
FOR INSERT 
WITH CHECK (true);

CREATE POLICY "Permitir update al scraper" 
ON public.puntos_abc
FOR UPDATE
USING (true)
WITH CHECK (true);

-- Nota: En un entorno de producción estricto, el scraper debería usar el Service Role Key 
-- y estas políticas de INSERT/UPDATE deberían restringirse.
