# Bondi Cba — Flutter + Go

La app activa está en `lib/screens/journey_screen.dart`. El mapa, el buscador, las preferencias y los lugares guardados están escritos en Dart. El prototipo React anterior es independiente.

## Probar

- En Windows: abrir `ABRIR_APP_FLUTTER.bat` desde la raíz del proyecto.
- En Android: instalar `build/app/outputs/flutter-apk/app-debug.apk`.
- Backend existente: `bondi_server.exe`, compilado desde `server_go/main.go`, puerto 3001.
- La app usa la dirección LAN configurada en `lib/services/api_service.dart`. El teléfono debe poder alcanzar esa dirección. Para otro servidor, compilar con `--dart-define=BONDI_API_URL=https://servidor/api`.

## Estado

Implementado: búsqueda de lugares y direcciones con sugerencias Photon/OpenStreetMap, abreviaturas, paradas y lugares guardados, selección de origen/destino en el mapa, ubicación bajo permiso, preferencias de línea y parada, lugares persistentes y marcadores, recorrido de una línea, posiciones de colectivos con distinción de estimaciones, selección de un colectivo o visualización de todos.

Viajes directos A→B: consulta las rutas del catálogo, proyecta las paradas sobre la geometría orientada y busca subida antes de bajada, hasta 800 m de distancia en línea recta por extremo. Muestra opciones ordenadas por caminata y permite elegir una parada específica dentro de una línea. No calcula transbordos ni caminatas por calles. Trazas con cruces, bucles o geometría incorrecta requieren validación adicional con datos reales. No confirma que un colectivo concreto todavía pueda recogerte: faltan próximas llegadas, tiempo de caminata y alertas por llegada. Cerrar el buscador detiene nuevas consultas; los recorridos fallidos se informan como cobertura parcial.

Validación: `flutter analyze lib/main.dart lib/screens/journey_screen.dart`, `flutter test`, `flutter build apk --debug`, ejecución nativa Windows.

La búsqueda remota usa /api/places del backend Go, restringe resultados a Córdoba y alrededores y utiliza caché de 15 minutos. La app espera 500 ms entre escritura y consulta y descarta respuestas anteriores. La cobertura depende de OpenStreetMap. UTN FRC tiene un resultado local con dirección de su sitio oficial y coordenadas de Wikidata Q5854479.


## Aviso de bajada
Desde Alertas se elige el destino o una parada del recorrido y un radio de 150, 300 o 500 m. Al activarlo pide ubicación y, en Android, permiso de notificaciones. Emite un aviso único tras dos posiciones recientes y precisas dentro del radio. Puede cancelarse; cambiar destino cancela el seguimiento anterior. No reconstruye avisos al reiniciar la app.
Android utiliza seguimiento con notificación persistente y notificación de bajada con sonido/vibración. El sistema puede detener el proceso; no hay garantía tras cerrar o forzar la detención de la app. Windows muestra el aviso y solicita sonido dentro de la app. No se han verificado GPS, permisos ni notificaciones en hardware Android; se validaron la lógica y las compilaciones.



## Viaje sin datos
Después de elegir un viaje directo, Preparar viaje sin datos guarda origen, destino, línea, sentido, geometría y paradas. Abrir viaje sin datos restaura ese paquete incluso después de reiniciar. En este modo no se solicitan teselas ni posiciones al servidor; se actualiza la estimación local cada 30 segundos. Volver a consultar online sale de este modo.
No se descargan mapas de calles: se muestra la geometría sobre fondo simple. Los snapshots de colectivos son los de la última consulta exitosa y pueden no existir. Nunca se presentan como GPS en vivo. La extrapolación usa velocidad fija y no conoce tránsito: después de 10 minutos conserva la posición original, mostrando la antigüedad. El umbral es conservador de producto, no una garantía de precisión. Los avisos de bajada usan GPS local y deben activarse manualmente; no se reactivan al restaurar. Pendientes: mapas autorizados para descarga, velocidades basadas en historial y mediciones de consumo/rendimiento en Android de gama baja.

## Flujo A → B en pantalla principal
Al completar ambos puntos se consultan secuencialmente los recorridos. Se elige la parada de subida con menor distancia al origen entre recorridos directos válidos; luego se buscan todas las líneas compatibles que comparten ese código de parada. No se agrupan paradas distintas por proximidad, para evitar mezclar lados de la calle. Elegir una línea muestra las paradas ordenadas por progreso sobre su geometría hasta la bajada. Los horarios y dist_parada se obtienen de /api/arrivals → proximos_arribos, consultado cada 20 segundos; errores y lista vacía se distinguen. Cobertura parcial se informa. Falta validar llegadas con servicio en circulación; no se garantiza alcanzar un colectivo según tiempo de caminata.

## Direcciones y alturas sin verificar
/api/places combina Photon con Georef v2.0 para consultas que terminan en altura numérica, limitado a Córdoba Capital. Si Photon no encuentra la altura se consulta la calle sin número y conserva el barrio como referencia. Georef puede devolver direcciones sin coordenadas; se usa una referencia de calle cuando coincide o el centro de Córdoba únicamente para abrir el mapa. Nunca se presenta esa referencia como ubicación exacta. Georef documenta todas sus coordenadas como aproximadas, por lo que también se confirman manualmente. Las sugerencias requiresMap abren un selector sin pin inicial y no permiten Usar este punto hasta que el usuario toca el mapa. El punto confirmado se devuelve como manual, en búsquedas de inicio/destino y editor de guardados. Cancelar no modifica el viaje.
La cobertura de ambos proveedores puede ser parcial y no se garantiza la altura exacta. Fuente de semántica Georef: https://www.argentina.gob.ar/node/473623 . Tests verifican fallback de Nevado 1054 con ubicacion null y confirmación obligatoria del mapa.

## Aviso de próxima llegada
En Alertas, después de elegir viaje/línea, se seleccionan 5 o 10 minutos y se activa el aviso. Consulta /api/arrivals cada 20 s y filtra por línea, ruta y opcionalmente el interno seleccionado al activar. Usa hora_salida como horario estimado de Córdoba (UTC-3); rechaza formatos inválidos, horarios pasados y más de 80 minutos. Contempla cruce de medianoche inmediato. Dispara una sola vez al entrar en el umbral, incluso si al activarlo ya faltan menos minutos. No extrapola llegadas ante errores ni lista vacía. Cambiar recorrido/destino o entrar sin datos cancela el aviso. Requiere app abierta y conexión; no tiene servicio persistente para llegada en segundo plano. En Android solicita permiso y emite notificación; Windows usa aviso dentro de la app y sonido. Pendiente validación de hora_salida con servicio real y notificaciones en hardware Android.

## Corrección de catálogo de paradas (validación con servicio)
La traza ahora proviene de cmd=seleccionatraza (POST ruta, cliente_id, conf). La consulta anterior seleccionalinea devolvía solo indicaciones de extremos, no el catálogo completo. Se validaron 72 paradas en la ruta 211 de la 70. Coordenadas pueden ser strings o números; Go las normaliza. Caché Flutter v2 evita reutilizar las dos paradas anteriores. La consulta de llegadas en tres paradas devolvió internos que no aparecieron en consultacocheporruta; hasta resolver esa discrepancia, los marcadores de un viaje solo se muestran al coincidir coche, cliente, línea y ruta con próximas llegadas. Una lista de horarios puede existir sin posiciones asociadas. No se atribuyen posiciones a un interno por cercanía ni se garantiza precisión del GPS del proveedor. Se añadió tratamiento del estado explícito Llegando hasta 500 m para no perder un aviso por truncamiento de hora_salida al minuto.

## Búsqueda acotada del catálogo
Se consultan como máximo tres recorridos simultáneamente, con presupuesto de 45 s y timeout por consulta. El buscador informa progreso y permite cancelar. Al vencer el plazo informa cobertura parcial; no afirma que la parada sea la más cercana de rutas no consultadas. La lectura de caché durante planificación no dispara refrescos adicionales. Las paradas fuera de los radios de origen/destino se descartan antes de proyectarlas sobre la geometría. Pruebas cubren concurrencia, errores, cancelación y proveedor sin respuesta.

## Alias de búsqueda
Avenida, Av., Avda. y Calle al inicio son prefijos opcionales para comparar y consultar nombres. FAUD, FAUD UNC, facu de arquitectura y universidad de arquitectura ofrecen dos sedes locales; centro o ciudad universitaria restringen la opción. Direcciones contrastadas con publicaciones oficiales FAUD (https://faud.unc.edu.ar/wp-content/blogs.dir/3/files/sites/3/PE_DISENO_INDUSTRIAL.pdf) y coordenadas de edificios OSM 103537771 y 1073692572 obtenidas de Photon. Los POI no garantizan el punto exacto de entrada al edificio. UTN conserva sus alias anteriores.

## Panel, vista previa y tramos del viaje
El panel admite mouse y touch; la barra permite arrastrar o tocar para expandir/contraer. Antes de elegir línea se dibujan vistas previas de las líneas compatibles, recortadas entre subida y bajada. Con A/B, Líneas ofrece solo los viajes compatibles de la parada encontrada; el catálogo completo se usa únicamente al explorar sin A/B. Se dibujan conexiones punteadas A→subida y bajada→B, aproximadas en línea recta, sin navegación por calles. Los marcadores de subida/bajada tienen icono de parada/cole y los intermedios conservan el color de la línea. La ficha permite seleccionar el interno de una llegada; la alerta utiliza ese interno. Si no se puede asociar posición GPS se informa y no se dibuja otra unidad. Tests cubren arrastre real con mouse y recorte de ruta.

## Comparación entre líneas
La búsqueda conserva las rutas compatibles con su propia parada, en lugar de descartar todo salvo la parada más cercana global. Antes de elegir no se fija una subida única. Cada opción muestra línea/sentido, parada, caminata aproximada, bajada y llegadas de su código de parada. Se consultan hasta tres paradas simultáneamente y se ordenan primero las opciones con hora_salida futura que permita caminar a 1.2 m/s más un minuto de margen. Sin horario válido se conserva la opción con llegada sin confirmar y se ordena por caminata. Esto no mide frecuencia histórica ni garantiza alcanzar la unidad. Los tiempos y posiciones provienen de la parada de la opción elegida.
