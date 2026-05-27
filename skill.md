# Skill de Diseño Visual

Este documento define los tokens visuales para la aplicación `RuteandoBolivia`, incluidos los colores, tamaños, espaciados y estilos para modo claro y modo oscuro.

## 1. Filosofía visual

La app busca ser moderna, clara y fácil de leer en contextos de movilidad. El diseño se apoya en:

- Contraste fuerte para texto y tarjetas sobre fondos oscuros.
- Colores de estado bien distinguidos para alertas, bloqueos y caminos seguros.
- Tipografía grande y legible para títulos y rutas.
- Espacio suficiente entre elementos para interacción táctil.

## 2. Paleta principal

### Colores base

- `primary`: `#22C55E` — verde principal para rutas seguras y acciones importantes.
- `primary-variant`: `#16A34A` — verde usado en estados activos y botones primarios.
- `secondary`: `#38BDF8` — color frío para clima, etiquetas neutrales y acentos suaves.
- `accent`: `#EAB308` — amarillo para precaución moderada y notas importantes.

### Colores de estado

- `success`: `#22C55E` — ruta segura / confirmación.
- `warning`: `#F97316` — derrumbe / advertencia.
- `danger`: `#EF4444` — bloqueo social / peligro.
- `climate`: `#38BDF8` — neblina / condiciones climáticas.
- `caution`: `#EAB308` — precaución moderada.

### Neutros

- `text-primary`: `#F3F4F6`
- `text-secondary`: `#9CA3AF`
- `surface`: `#181C23`
- `surface-variant`: `#1F2430`
- `background`: `#0F1115`
- `border`: `#252B36`

## 3. Modo oscuro

### Tokens de color

- `dark-background`: `#0F1115`
- `dark-card`: `#181C23`
- `dark-border`: `#252B36`
- `dark-text-primary`: `#F3F4F6`
- `dark-text-secondary`: `#9CA3AF`
- `dark-placeholder`: `#5D6C7E`
- `dark-shadow`: `rgba(0, 0, 0, 0.35)`

### Uso recomendado

- Fondo general: `dark-background`
- Tarjetas y paneles: `dark-card`
- Paneles resaltados: `#1F2430`
- Texto principal: `dark-text-primary`
- Texto secundario: `dark-text-secondary`
- Bordes / separadores: `dark-border`

## 4. Modo claro

### Tokens de color

- `light-background`: `#F3F4F6`
- `light-card`: `#FFFFFF`
- `light-border`: `#E5E7EB`
- `light-text-primary`: `#111827`
- `light-text-secondary`: `#6B7280`
- `light-placeholder`: `#9CA3AF`
- `light-shadow`: `rgba(15, 23, 42, 0.08)`

### Uso recomendado

- Fondo general: `light-background`
- Tarjetas y paneles: `light-card`
- Paneles resaltados: `#F8FAFC`
- Texto principal: `light-text-primary`
- Texto secundario: `light-text-secondary`
- Bordes / separadores: `light-border`

## 5. Fondo con patrón de mapa

### Objetivo

El fondo debe incluir un patrón muy sutil inspirado en redes viales:

- carreteras
- curvas topográficas
- rutas GPS
- malla de caminos

### Reglas

- MUY sutil
- casi invisible
- elegante
- ambiental
- orgánico

### No debe

- distraer
- competir con el contenido
- usar brillo excesivo
- parecer cyberpunk

### Implementación recomendada

- Usar SVG como capa de fondo
- Opacidad: `0.04 - 0.08` en modo oscuro
- Opacidad: `0.03 - 0.05` en modo claro
- Permanecer fijo y sin scroll independiente
- Verse más en bordes y esquinas
- Desaparecer detrás de cards

### Assets sugeridos

```txt
assets/
 ├── patterns/
 │    ├── roads_dark.svg
 │    └── roads_light.svg
```

## 6. Tipografía y escala de tamaños

### Familias de fuente

- `font-family-base`: `Inter`, `Roboto`, `sans-serif`
- `font-family-heading`: `Inter`, `sans-serif`

### Escala principal

- `display-xl`: `34px` / `bold` — pantallas principales, encabezado de la app.
- `display-lg`: `28px` / `bold` — títulos de pantallas.
- `title`: `22px` / `semibold` — títulos de sección.
- `subtitle`: `18px` / `medium` — subtítulos y headers.
- `body-large`: `16px` / `regular` — texto principal.
- `body`: `14px` / `regular` — texto de contenido.
- `caption`: `12px` / `medium` — etiquetas, notas y botones pequeños.
- `micro`: `10px` / `medium` — indicadores pequeños y helper text.

### Peso de fuente

- `font-weight-bold`: `700`
- `font-weight-semibold`: `600`
- `font-weight-medium`: `500`
- `font-weight-regular`: `400`

## 6. Espaciado y forma

### Espaciado

- `spacing-xxs`: `4px`
- `spacing-xs`: `8px`
- `spacing-sm`: `12px`
- `spacing-md`: `16px`
- `spacing-lg`: `20px`
- `spacing-xl`: `24px`
- `spacing-xxl`: `32px`

### Bordes y radios

- `radius-sm`: `8px`
- `radius-md`: `16px`
- `radius-lg`: `24px`
- `radius-full`: `999px`

### Sombra

- `shadow-low`: `0 4px 12px rgba(0, 0, 0, 0.12)`
- `shadow-medium`: `0 8px 24px rgba(0, 0, 0, 0.18)`

## 7. Componentes clave

### Botón primario

- Fondo: `primary`
- Texto: `#0B1118` o `light-surface` en modo claro
- Radio: `radius-lg`
- Altura: `48px`
- Padding: `0 20px`
- Hover / Press: `primary-variant`

### Botón secundario

- Fondo: `surface` / `light-surface`
- Texto: `primary`
- Borde: `1px solid primary`
- Radio: `radius-lg`

### Tarjeta de alerta

- Fondo: `surface-variant` / `light-surface-variant`
- Borde izquierdo: `4px solid danger` / `warning` / `success`
- Texto principal: `text-primary` / `light-text-primary`
- Texto secundario: `text-secondary` / `light-text-secondary`
- Padding: `spacing-lg`
- Radio: `radius-md`

### Badge de estado

- `success`: fondo `#0F3F2A`, texto `#CFFFE7`
- `warning`: fondo `#553E10`, texto `#FFF1BE`
- `danger`: fondo `#5A1515`, texto `#FFD7D1`
- `info`: fondo `#153A82`, texto `#D6E8FF`
- Padding: `spacing-xxs` vertical y `spacing-sm` horizontal
- Radio: `radius-full`

## 8. Guía rápida de uso

### Pantalla principal / Header

- Usa `background` / `light-background`
- Encabezado con `display-lg` y `text-primary`
- Barra de búsqueda: `surface` / `light-surface`
- Botones del menú: iconos `secondary`

### Alertas y reportes

- Tarjetas de bloqueo: color `danger` + fondo `surface-variant`
- Tarjetas de derrumbe: color `warning`
- Rutas despejadas: color `success`
- Texto de tiempo / distancia: `text-secondary`

### Mapa

- Superficie sobre mapa: `surface` con opacidad suave.
- Indicadores activos: `primary` y `accent`.
- Etiquetas de información: `text-primary` con `shadow-low`.

## 9. Notas finales

- Esta hoja de estilo está pensada para ser una guía de tokens y no un estilo fijo final.
- Ajusta los valores según la experiencia de usuario en dispositivos móviles y la visibilidad del mapa.
- El contraste debe mantenerse alto en modo oscuro para lectura fácil mientras el diseño conservador en modo claro debe ser neutro y limpio.
