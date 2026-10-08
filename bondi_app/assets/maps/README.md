# Mapa local de Córdoba

Datos © OpenStreetMap contributors, bajo ODbL 1.0:
https://www.openstreetmap.org/copyright
https://opendatacommons.org/licenses/odbl/1-0/

Este dataset tiene su propia licencia, independiente de la licencia del código.
Cubre latitudes -31.55 a -31.25 y longitudes -64.35 a -64.05.
Contiene calles, parques y cursos de agua; no incluye edificios ni imágenes satelitales.
Actualización: ejecutar `python bondi_app/tool/download_offline_map.py` y reconstruir la APK.
Se consulta Overpass una vez durante la preparación, nunca desde el teléfono.
No se descargan tiles del servidor público de OpenStreetMap.

## Paquete de imágenes

`python bondi_app/tool/render_offline_map.py` genera `cordoba.tiles` (PNG concatenados)
y `cordoba.tiles.json` (índice de offsets, límites, zoom, fecha, licencia y SHA-256).
Requiere Python, Pillow y Arial de Windows. No realiza consultas de red.
Las imágenes son de 512 px para cuadros de mapa de 256 px, zoom nativo 10–16.
A mayor zoom se amplían las imágenes existentes; no se agregan detalles.
La cobertura es la del dataset anterior; fuera de ella no hay mapa local.

El mapa se incluye en esta APK de prueba y se usa conectado y sin datos con
el mismo estilo. La descarga separada por Wi-Fi todavía no está implementada.
Se conserva el dataset fuente para regenerarlo; la app ya no dibuja sus calles.
