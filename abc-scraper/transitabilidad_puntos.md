# Puntos de Transitabilidad ABC - Documentación para Proyecto Flutter

Esta documentación recopila la información necesaria sobre los puntos de estado de carreteras basados en el portal oficial de la Administradora Boliviana de Carreteras (ABC) (https://transitabilidad.abc.gob.bo/) para su integración en un proyecto con Flutter y Dart.

## ⚠️ Sobre la API Key y Endpoints Oficiales

Actualmente, el sitio web de la ABC protege el acceso a su mapa interactivo mediante un sistema de **Captcha** (validación humana) y **no expone públicamente una API REST abierta (JSON/GeoJSON)** o una API Key directa de Google Maps / Leaflet para el libre consumo de aplicaciones de terceros. La aplicación móvil oficial ("Transitabilidad ABC" en Play Store) consume servicios internos que no están documentados para uso público.

**Alternativas para el proyecto:**
1. **Contacto Oficial (Recomendado):** Solicitar formalmente a la ABC (o a la AGETIC) acceso a sus servicios web cartográficos (MapServer/FeatureServer de ArcGIS) para desarrolladores.
2. **Web Scraping (Requiere precaución):** Analizar y evadir el captcha implementando un scraper en el backend, que intercepte las llamadas de red (XHR/Fetch) de la web oficial y extraiga los puntos, para luego servirlos a tu aplicación en Flutter mediante una API propia.

---

## Tipos de Puntos de Reporte en la Red Vial Fundamental

A continuación se detallan las descripciones, estados y las convenciones de colores utilizadas por la ABC para representar las diferentes situaciones en el mapa. Esta estructura te servirá para crear tus modelos de datos en Dart.

### 1. Conflictos Sociales / Tráfico Cerrado
Representa vías completamente intransitables, ya sea por problemas humanos (bloqueos) o situaciones extremas (colapsos estructurales).
*   **Estado Oficial:** `NO TRANSITABLE`
*   **Subcategorías:**
    *   **Por Conflictos Sociales (Bloqueos):** Representado gráficamente con el color **AZUL**. Son bloqueos de rutas por manifestaciones, paros cívicos o protestas sociales.
    *   **Tráfico Cerrado (Otras causas):** Representado con el color **ROJO**. Cierre total debido a la pérdida de plataforma, colapso de puentes, derrumbes masivos o inundaciones graves.
*   **Campos de Datos Útiles (Dart Model):**
    ```dart
    String id;
    String tipo = "TRAFICO_CERRADO";
    String causa; // Ej: "Bloqueo", "Derrumbe"
    String ubicacion; // Tramo afectado (Ej: "La Paz - Oruro")
    double latitud;
    double longitud;
    DateTime fechaReporte;
    ```

### 2. Transitable con Desvíos
Indica que la ruta está operativa, pero el tráfico normal se ve alterado. Los vehículos deben usar caminos alternativos temporales en un sector específico.
*   **Estado Oficial:** `TRANSITABLE CON DESVÍOS`
*   **Color en Mapa:** **NARANJA**
*   **Causas Comunes:** Trabajos de mantenimiento, construcción de nueva vía, limpieza de derrumbes menores, rehabilitación de tramos, o bacheo.
*   **Campos de Datos Útiles (Dart Model):**
    ```dart
    String id;
    String tipo = "TRANSITABLE_CON_DESVIOS";
    String descripcionDesvio; // Ej: "Desvío por el lado derecho a 200m del puente"
    String motivo; // Ej: "Trabajos de asfaltado"
    double latitud;
    double longitud;
    ```

### 3. Transitable con Precaución y Restricción Vehicular Especial
La ruta no está cortada, pero existen riesgos o normativas de paso especiales para ciertos tipos de vehículos o en ciertos horarios.
*   **Estado Oficial:** `TRANSITABLE CON RESTRICCIÓN` / `CON PRECAUCIÓN`
*   **Color en Mapa:** **VIOLETA** (o verde en ciertos contextos de restricción menor).
*   **Causas Comunes:** Lluvias intensas, neblina, nevadas, horarios de paso restringidos (ej. cierre nocturno), o restricción de paso para transporte pesado (vehículos de gran tonelaje).
*   **Campos de Datos Útiles (Dart Model):**
    ```dart
    String id;
    String tipo = "RESTRICCION_VEHICULAR";
    String nivelPrecaucion; // Alta, Media
    String detalleRestriccion; // Ej: "Prohibido paso de transporte pesado de 20:00 a 06:00"
    double latitud;
    double longitud;
    ```

---

## Modelo de Datos Sugerido en Dart (Flutter)

Para tu proyecto, puedes empezar creando un modelo unificado en Dart para manejar estos puntos en el mapa (`google_maps_flutter` o `flutter_map`):

```dart
enum TipoEstadoRuta {
  traficoCerrado,
  transitableConDesvios,
  restriccionVehicular,
  expedito // Verde
}

class PuntoTransitabilidad {
  final String id;
  final String tramo;
  final String descripcion;
  final TipoEstadoRuta estado;
  final double latitud;
  final double longitud;
  final DateTime ultimaActualizacion;

  PuntoTransitabilidad({
    required this.id,
    required this.tramo,
    required this.descripcion,
    required this.estado,
    required this.latitud,
    required this.longitud,
    required this.ultimaActualizacion,
  });

  // Factory para parsear desde un JSON futuro
  factory PuntoTransitabilidad.fromJson(Map<String, dynamic> json) {
    return PuntoTransitabilidad(
      id: json['id'],
      tramo: json['tramo'],
      descripcion: json['descripcion'],
      estado: _parseEstado(json['estado']),
      latitud: json['latitud'],
      longitud: json['longitud'],
      ultimaActualizacion: DateTime.parse(json['ultima_actualizacion']),
    );
  }

  static TipoEstadoRuta _parseEstado(String estadoStr) {
    switch (estadoStr) {
      case 'TRAFICO_CERRADO': return TipoEstadoRuta.traficoCerrado;
      case 'DESVIO': return TipoEstadoRuta.transitableConDesvios;
      case 'RESTRICCION': return TipoEstadoRuta.restriccionVehicular;
      default: return TipoEstadoRuta.expedito;
    }
  }
}
```

## Arquitectura de Sincronización y Hosting

### 1. El Scraper (Microservicio Node.js)
Este código que tienes en `abc-scraper` debe alojarse en un servicio en la nube gratuito o muy barato que soporte Node.js 24/7 (como **Render, Railway, Fly.io o Heroku**). Su único trabajo en la vida será:
*   Despertar cada 30 minutos mediante un cron job.
*   Usar Puppeteer para leer los puntos de la ABC saltando el Captcha.
*   Conectarse a tu base de datos de Supabase y guardar/actualizar los puntos geográficos en una tabla (ej. `puntos_abc`).

### 2. Base de Datos (Supabase)
Los datos estructurados vivirán en Supabase. El Scraper insertará los datos interceptados en formato JSON o parseados para que coincidan con el modelo documentado en este mismo archivo.

### Siguientes Pasos
1. **Configurar el Mapa:** Usar un paquete como `flutter_map` o `google_maps_flutter` en tu app.
2. **Conectar Flutter a Supabase:** Configurar la app móvil para que lea directamente la tabla de puntos en Supabase. Esto te permitirá tener el mapa actualizado sin recargar.
