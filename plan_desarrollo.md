# Plan de Desarrollo: RuteandoBolivia

Este documento detalla la hoja de ruta y la bitacora de trabajo para construir la aplicacion RuteandoBolivia utilizando Flutter y Supabase. El plan esta dividido en fases logicas que permiten al equipo (Daniela, Angel, Alex, Erika, Carlos) trabajar en paralelo y avanzar paso a paso.

---

## Fase 1: Datos y Modelado del Grafo (Semana 1)
El objetivo es obtener los datos geograficos y de conexion de las carreteras principales de Bolivia.

*   **Actividad 1:** Crear un script en Python que consulte una API de mapas (OSRM) para extraer las coordenadas precisas y distancias de la Red Vial Fundamental de Bolivia.
*   **Actividad 2:** Consolidar estos datos en un archivo JSON ligero (`bolivia_road_graph.json`) que contenga los nodos (ciudades/intersecciones) y las aristas (carreteras con su trazado exacto).
*   **Responsable principal:** Angel (con apoyo de Carlos para verificar la precision geografica).

---

## Fase 2: Configuracion del Backend en Supabase (Semana 1)
Establecer la base de datos en tiempo real que almacenara los reportes de incidentes.

*   **Actividad 1:** Crear el proyecto en Supabase y activar la extension PostGIS para manejar coordenadas geograficas.
*   **Actividad 2:** Diseñar y crear las tablas en la base de datos:
    *   `perfiles`: Informacion de usuarios registrados.
    *   `incidentes`: Datos del bloqueo/derrumbe (tipo, coordenadas, descripcion, timestamp, estado).
    *   `votos`: Historial de votacion para evitar votos duplicados de un mismo usuario sobre un incidente.
*   **Actividad 3:** Configurar las politicas de seguridad Row Level Security (RLS) y habilitar los servicios Realtime en la tabla `incidentes`.
*   **Responsable principal:** Daniela.

---

## Fase 3: Interfaz Base en Flutter (Semana 2)
Construir la interfaz de usuario en base a los diseños premium aprobados.

*   **Actividad 1:** Crear el proyecto de Flutter y configurar la estructura de carpetas (models, views, controllers, services).
*   **Actividad 2:** Maquetar las 4 pantallas principales en modo oscuro (Azul Indigo y Gris Pizarra):
    *   Pantalla del Mapa (con un placeholder visual del mapa).
    *   Pantalla del Listado de Alertas por departamento con tarjetas de incidentes.
    *   Pantalla de Formulario de Reporte.
    *   Pantalla de Login / Registro.
*   **Responsable principal:** Alex.

---

## Fase 4: Integracion del Mapa y Algoritmo de Rutas (Semana 2 - 3)
Dar vida al mapa e implementar la logica de desvios en el celular.

*   **Actividad 1:** Integrar el paquete `flutter_map` en la pantalla principal para mostrar el mapa real de OpenStreetMap de Bolivia.
*   **Actividad 2:** Implementar la lectura del archivo `bolivia_road_graph.json` y pintar las carreteras sobre el mapa.
*   **Actividad 3:** Programar el algoritmo de busqueda de rutas (Dijkstra) en Dart. El algoritmo debe recibir un origen y destino, y calcular la ruta mas corta. Si un tramo de carretera esta marcado como bloqueado, el algoritmo debe recalcular el camino por una ruta alternativa.
*   **Responsable principal:** Angel.

---

## Fase 5: Conexion de Datos e Integracion de Supabase (Semana 3)
Conectar el cerebro de la app (Flutter) con la base de datos (Supabase).

*   **Actividad 1:** Implementar la autenticacion de usuarios en Flutter con Supabase Auth.
*   **Actividad 2:** Programar el envio de nuevos reportes desde el formulario de Flutter hacia la tabla `incidentes` en Supabase.
*   **Actividad 3:** Conectar el listado de alertas y los marcadores del mapa a Supabase Realtime, para que aparezcan o desaparezcan del telefono al instante cuando sean creados o eliminados.
*   **Actividad 4:** Implementar el sistema de votacion (Sigue ahi / Despejado) en Flutter, actualizando el conteo de votos en Supabase.
*   **Responsable principal:** Erika.

---

## Fase 6: Modulo de Inteligencia Artificial para el Concurso (Semana 4)
Integrar las funcionalidades inteligentes que haran destacar el proyecto en el concurso de IA.

*   **Actividad 1 (NLP):** Crear una Supabase Edge Function (o un servicio en Python) que use una API de LLM para leer textos informales de reportes de transito y convertirlos automaticamente en registros estructurados (JSON) de bloqueos.
*   **Actividad 2 (Vision AI):** Integrar un modelo de analisis de imagenes para validar que las fotos subidas por los usuarios correspondan a un bloqueo, derrumbe o camino dañado real.
*   **Actividad 3 (Asistente de Voz):** Implementar la funcionalidad de copiloto conversacional por voz en Flutter para permitir consultas de ruta manos libres durante la conduccion.
*   **Responsables:** Todo el equipo (Erika y Daniela en backend/APIs, Alex y Angel en integracion movil).

---

## Fase 7: Cache Offline, Pruebas y Despliegue (Semana 4+)
Optimizar la aplicacion para condiciones reales de carretera y subirla a produccion.

*   **Actividad 1:** Configurar la base de datos SQLite local en Flutter y usar `flutter_map_tile_caching` para almacenar las imagenes del mapa de las rutas principales, permitiendo que la navegacion funcione sin internet en tramos intermedios.
*   **Actividad 2:** Realizar pruebas de rendimiento de rutas, simulacion de perdida de conexion y depuracion de errores.
*   **Actividad 3:** Subir los cambios finales al repositorio de GitHub mediante el flujo de Pull Requests y Squash & Merge.
*   **Responsable principal:** Carlos.
