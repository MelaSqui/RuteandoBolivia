# RuteandoBolivia Backend

Este es el microservicio backend oficial del proyecto RuteandoBolivia. Su propósito es actuar como puente entre los datos oficiales del estado (Administradora Boliviana de Carreteras) y nuestra aplicación móvil/frontend.

## Arquitectura

El backend está compuesto por dos piezas fundamentales:

1. **Scraper Periódico (Data Ingestion)**
   - Se encarga de hacer peticiones directas y de bajo peso a la API de transitabilidad oculta de la ABC (`/api/v1/data`, `/api/v1/serviceStations`, `/api/v1/retenes`, `/api/v1/events`).
   - Mapea y limpia la estructura JSON oficial para que sea más fácil de consultar.
   - Realiza una operación de `upsert` (insertar o actualizar) hacia la base de datos **Supabase** para mantener la información de rutas, estaciones y retenes sincronizada en tiempo real.
   - Ejecuta un scheduler dinámico que reintenta cada 10 minutos si hay fallas, o cada 3 horas si tuvo éxito.

2. **Express REST API (Microservicio)**
   - Un servidor ligero construido con Express que provee los endpoints necesarios para que la aplicación (Flutter) consuma los datos.
   - **Autenticación Nativa**: Todos los endpoints verifican que el token enviado en la cabecera `Authorization: Bearer <TOKEN>` corresponda a una sesión válida en el proyecto Supabase, protegiendo así el acceso a la base de datos.

## Tecnologías Utilizadas

- **Node.js** (v22+ con `fetch` nativo)
- **Express.js** (API y Middleware)
- **Supabase JS Client** (`@supabase/supabase-js`)
- **Pino** (Logging estructurado)
- **Dotenv** (Manejo de variables de entorno)

## Configuración Local

1. Crea un archivo `.env` en la raíz de la carpeta `backend` basado en tus credenciales de Supabase:
   ```env
   # Scraper Configuration
   SCRAPE_TARGET_URL=https://transitabilidad.abc.gob.bo

   # Logging
   LOG_LEVEL=info

   # Storage local backup (opcional)
   DATA_DIR=./data/snapshots

   # Supabase
   SUPABASE_URL=https://tu-proyecto.supabase.co
   SUPABASE_ANON_KEY=tu-anon-key
   SUPABASE_SERVICE_ROLE_KEY=tu-service-role-key
   ```

2. Ejecuta el script SQL en Supabase (`supabase/schema.sql`) para crear las tablas de datos y las políticas de acceso (RLS).

3. Instala las dependencias:
   ```bash
   npm install
   ```

## Ejecución de Servicios

El proyecto permite ejecutar el recolector de datos y la API de manera independiente:

**Para iniciar el Scraper (Sincronización):**
```bash
npm run start:scraper
```
*(También puedes forzar una sola ejecución de prueba con `npm run scrape:once`)*

**Para iniciar el Servidor API:**
```bash
npm run start:api
```

## Endpoints Disponibles

*Nota: Todos los endpoints requieren el header `Authorization: Bearer <TOKEN>`.*

- `GET /health` : Verificación de estado del servidor y conexión a Supabase.
- `GET /api/events` : Devuelve todos los eventos y estado de rutas.
- `GET /api/stations` : Devuelve las estaciones de servicio (gasolineras).
- `GET /api/tolls` : Devuelve los retenes y peajes registrados.
