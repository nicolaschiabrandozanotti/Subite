# Estructura de Subite

Actualizado el 8 de octubre de 2026. La aplicación distribuida es Flutter para Android; el backend es Go.

## Responsabilidades

| Módulo de `bondi_app/` | Qué mantiene |
| --- | --- |
| `lib/main.dart` | Arranque y configuración del sistema. |
| `lib/screens/journey_screen.dart` | Navegación, diálogos, permisos de ubicación y cámara del mapa. |
| `lib/controllers/journey_controller.dart` | Estado del viaje, selección, planificación, consultas, temporizador, seguimiento de interno y transición sin conexión. |
| `lib/widgets/journey_map.dart` | Capas de mapa, polilíneas, pines y marcadores. |
| `lib/widgets/journey_results_panel.dart` | Llegadas, alternativas y panel del viaje seleccionado. |
| `lib/widgets/journey_preferences_sheet.dart` | Elección de línea y parada mediante acciones del controlador. |
| `lib/widgets/journey_alerts_sheet.dart` | Configuración de los dos avisos. |
| `lib/widgets/journey_stop_timeline.dart` | Presentación del avance del usuario sobre las paradas. |
| Buscador y editor de guardados en `lib/widgets/` | Búsqueda, confirmación de direcciones y edición de lugares/viajes. |
| `lib/services/journey_planner.dart` y `route_position.dart` | Geometría, viajes directos y ajuste de posiciones. |
| `lib/services/arrival_time.dart` | Interpretación de horarios del proveedor, sin permisos ni notificaciones. |
| `lib/services/arrival_alert.dart` y `trip_alert_service.dart` | Seguimiento y emisión de avisos. |
| `lib/services/api_service.dart` | HTTP y caché del catálogo y trazas; no decide el modo del viaje. |
| `lib/services/offline_trip.dart` y `predictive_engine.dart` | Persistencia y avance estimado desde la referencia guardada. |
| Mapa local en `lib/services/`, `lib/widgets/` y `assets/maps/` | Lectura de un paquete de imágenes de Córdoba generado en la PC. |
| `lib/theme/app_theme.dart` | Tema y colores compartidos. |

La pantalla llama acciones del controlador y observa sus cambios; los widgets no modifican sus campos. El controlador no conoce BuildContext, navegación, cámara, diálogos ni permisos. Las consultas y el reloj pueden proporcionarse en las pruebas, sin clases que sólo deleguen.

## Reglas del viaje

- Una respuesta tardía no reemplaza una selección o búsqueda más reciente. Cancelar invalida sus identificadores de solicitud.
- Un único temporizador actualiza el viaje. Se suspende en segundo plano, se reanuda al volver y se cancela al destruir el controlador.
- Elegir un viaje guarda extremos, recorrido y paradas. Las posiciones válidas actualizan la referencia; una lista vacía conserva la última útil.
- El guardado sólo coincide si coinciden empresa, línea, sentido, recorrido, paradas y ambos extremos.
- Sin conexión se usa la hora original del guardado. No se consultan posiciones nuevas ni se guarda una estimación como referencia en vivo.
- La selección de interno se conserva aunque falte su ubicación; sus coordenadas anteriores dejan de mostrarse como seguimiento actual.
- La geometría y las paradas ordenadas se reutilizan mientras sus entradas no cambian.

## Limpieza

Se retiraron las cuatro pantallas antiguas sin acceso desde el arranque y su tema oscuro, la delegación `asyncFetchLineas`, la caché alternativa `fetchCoches` sin llamadas de producción y los paneles inalcanzables del viaje activo. La estimación sin conexión tiene un solo camino. Los cálculos de llegada se separaron de las notificaciones.

Se conservaron las claves de viajes y lugares guardados. No se borran datos anteriores para limpiar código. No se agregaron paquetes, repositorios de delegación ni jerarquías de clases.

`server_go/` ya agrupa funciones por responsabilidad: rutas/sesión del proveedor, llegadas, lugares, caché, compresión y ciclo de vida HTTP. Sus endpoints públicos tienen manejadores y pruebas; no se retiraron por dejar de usarse desde una pantalla Flutter. Los prototipos locales ignorados por Git no se eliminaron.

## Extenderla

Una regla nueva de planificación o seguimiento va en el controlador o en el cálculo específico existente y se comprueba a través de sus acciones. La presentación va en su widget. Los permisos y operaciones de Android siguen en sus módulos de plataforma.

La pantalla conserva composición de controles, navegación y exploración. El controlador reúne la sesión del viaje; no se dividió en clases por cada método. Los mapas JSON de llegadas se interpretan cerca del proveedor: agregar otro modelo sólo cuando un requisito real lo justifique.

## Validación

49 pruebas Flutter comprueban búsquedas, persistencia, geometría, mapa local, avance estimado, respuestas tardías, identidad del viaje, snapshots, seguimiento del interno y ciclo de vida del temporizador. El analizador no informa incidencias. La compilación release Android se verifica por separado.

Las capturas Android anteriores acreditan la revisión inicial, no esta refactorización. Falta una comprobación física posterior: el teléfono dejó de aparecer por ADB. No se midieron batería, memoria ni tiempos de cuadros.

## GitNexus

GitNexus 1.6.12 está instalado y configurado como MCP de Codex. Índice y caché están fuera de la APK. Sus parsers de Dart/Go y la conexión MCP se comprobaron durante la instalación.

Actualizar desde la raíz en PowerShell:

```powershell
$env:GITNEXUS_ANALYZER_IDENTITY_CACHE_DIR = "C:/Users/nicol/.gitnexus/identity-cache"
$env:GITNEXUS_MEMORY = "off"
$env:GITNEXUS_LBUG_EXTENSION_INSTALL = "auto"
$env:NODE_OPTIONS = "--max-old-space-size=4096"
gitnexus analyze --index-only --workers 2
```

La resolución de llamadas es parcial. Una relación ausente no prueba que el código esté sin uso; comprobar también las referencias en fuentes, manejadores registrados y pruebas.

## Mapa raster de prueba

`tool/render_offline_map.py` genera las imágenes a partir del dataset OSM local.
`services/raster_map.dart` lee su índice y entrega imágenes a FlutterMap.
`widgets/offline_map_layer.dart` presenta esa capa tanto conectado como sin datos.
El recorrido y los colectivos se dibujan encima. El paquete se incluye en la APK;
la descarga/actualización separada todavía queda pendiente. Zoom nativo 10–16.
