# RuteandoBolivia

RuteandoBolivia es un buscador de rutas alternativas inteligente y colaborativo para la Red Vial Fundamental de Bolivia. Su objetivo principal es ayudar a los conductores y viajeros a encontrar las rutas más seguras de un departamento a otro, esquivando automáticamente los bloqueos, derrumbes u otros obstáculos activos en las carreteras.

## Caracteristicas Principales

*   Mapa Interactivo de Carreteras: Visualizacion de la Red Vial Fundamental de Bolivia con indicadores visuales de tramos transitables e interrumpidos.
*   Enrutamiento Inteligente: Calculo automatico del camino mas corto o seguro que evite tramos con bloqueos o derrumbes activos.
*   Reportes Comunitarios: Registro dinamico de obstaculos en la via (bloqueos, derrumbes, factores climativos graves, baches graves).
*   Validacion Colaborativa: Sistema de confirmacion de reportes basado en votos para mantener el mapa actualizado en tiempo real.

## Tecnologias

*   **Frontend / Movil:** Flutter (Dart) para la aplicacion multiplataforma.
*   **Backend / Base de datos:** Supabase para el almacenamiento de incidentes en tiempo real y la gestion de base de datos relacional.

## Configuracion e Instalacion Local

1.  **Clona el repositorio:**
    ```bash
    git clone https://github.com/MelaSqui/RuteandoBolivia.git
    cd RuteandoBolivia
    ```

2.  **Configura el entorno:**
    Crea una copia del archivo de configuracion `.env`:
    ```bash
    cp .env.example .env
    ```
    Configura tus credenciales de Supabase en el archivo `.env`:
    *   `SUPABASE_URL`
    *   `SUPABASE_ANON_KEY`

3.  **Descarga las dependencias de Flutter:**
    ```bash
    flutter pub get
    ```

4.  **Ejecuta la aplicacion:**
    ```bash
    flutter run
    ```

---

## Flujo de Trabajo con Git

Para mantener la integridad del repositorio y facilitar la colaboracion, el equipo debe seguir este flujo de trabajo estandar:

### Nomenclatura de Ramas
*   Ramas de caracteristicas (features): `feat/ID-JIRA-descripcion-corta`
*   Ramas de correccion (fixes): `fix/ID-JIRA-descripcion-corta`
*   Ramas de tareas (chores): `chore/ID-JIRA-descripcion-corta`

### Commits Atomicos
Cada commit debe representar una sola unidad de cambio logica y autocontenida. Evita subir multiples cambios no relacionados en un solo commit.

### Uso de Git Stash
Si necesitas cambiar de rama pero tienes trabajo a medio terminar que no deseas confirmar todavia, utiliza:
```bash
git stash
# Cambiar de rama, realizar cambios, volver a la rama original
git stash pop
```

### Resets y Limpieza
Para deshacer cambios locales no confirmados:
*   Deshacer cambios en el directorio de trabajo: `git checkout -- <archivo>` o `git restore <archivo>`
*   Deshacer el ultimo commit manteniendo los cambios locales: `git reset --soft HEAD~1`
*   Deshacer el ultimo commit y descartar los cambios locales: `git reset --hard HEAD~1`

### Squash Local y Limpieza de Historial
Antes de publicar tu rama para revision, limpia el historial local si tienes muchos commits pequenos de prueba usando rebase interactivo:
```bash
git rebase -i HEAD~N
```
Reemplaza `pick` por `squash` (o `s`) para combinar los commits secundarios en uno solo con un mensaje estructurado.

---

## Guia de Conventional Commits y Jira

Para mantener un historial limpio y autogenerar bitacoras de cambios, todo el equipo debe seguir estrictamente Conventional Commits. La estructura obligatoria de un mensaje de commit es:

`tipo(ambito opcional): [ID-JIRA] descripcion corta en minusculas y en ingles`

### Tipos de Commits Permitidos (tipo)
*   `feat`: Anade una nueva funcionalidad (feature).
*   `fix`: Corrige un error (bug).
*   `docs`: Cambios exclusivos en manuales o documentacion (ej. README).
*   `style`: Cambios de formato (espacios, punto y coma, identacion) que no afectan la logica del codigo.
*   `refactor`: Modificacion de codigo que no arregla un error ni anade funcionalidad.
*   `perf`: Ajustes que mejoran el rendimiento de la aplicacion.
*   `test`: Anade o corrige pruebas automatizadas.
*   `chore`: Tareas de mantenimiento (actualizar dependencias, scripts de build).

### Ejemplos Correctos
*   `feat(vision): [VIN-45] implement open search client for image matching`
*   `fix(ingestion): [VIN-12] resolve nil pointer exception on empty csv rows`
*   `docs: [VIN-99] update architecture diagrams`
*   `chore(deps): [VIN-10] bump grpc-go to v1.62.0`

### Reglas para Pull Requests (PRs)
*   El Pull Request debe abrirse utilizando la convencion de Conventional Commits en el titulo.
*   Antes de hacer merge, los commits se deben hacer Squash.
*   El titulo del Squash Commit final debe seguir esta misma convencion para que el historial en la rama main quede completamente estructurado.
*   Utiliza la opcion de Squash & Merge al confirmar el cierre del PR en la interfaz de GitHub.

---

## Contribuciones

Las contribuciones son totalmente bienvenidas. Si encuentras un fallo, tienes una idea para mejorar el algoritmo de rutas o deseas integrar mas capas geograficas de Bolivia, sietete libre de abrir un Issue o enviar un Pull Request.
