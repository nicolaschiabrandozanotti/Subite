# Rendimiento y viaje sin conexión

Revisión local: 7 de octubre de 2026.

## Cambios comprobados

- Se reutilizan las geometrías de líneas, paradas del viaje y posiciones ajustadas cuando sus datos no cambian.
- La comparación de llegadas reúne los resultados antes de ordenar y actualizar la pantalla, en lugar de reconstruirla por cada parada consultada. Como contrapartida, los resultados nuevos aparecen al terminar el lote.
- Se eliminan reconstrucciones del mapa por contadores de carga que no se muestran y por lecturas GPS de la alerta de bajada. El panel de alertas escucha directamente esos cambios.
- Las consultas periódicas del mapa y de la alerta de llegada se suspenden en segundo plano. Las solicitudes ya enviadas pueden terminar.
- El viaje preparado conserva recorrido, paradas, origen, destino, internos, coordenadas y hora de recepción de las ubicaciones. Admite los viajes guardados con el formato anterior.
- Al abrir el viaje sin datos, las posiciones se calculan a partir de ese mismo guardado, sin consultar ubicaciones nuevas.
- Las posiciones guardadas se muestran como aproximadas. El avance supuesto usa velocidad fija; a partir de diez minutos se conserva la última ubicación recibida. No permite conocer dónde está realmente el colectivo.
- El mapa de calles no se descarga. Para usar el modo sin datos hay que guardar el viaje mientras existe conexión.

Corrección 1.0.1: las llegadas con posiciones válidas guardan automáticamente el viaje A → B. Una consulta fallida abre ese guardado sólo si coinciden línea, sentido, paradas y ambos extremos del viaje actual. Las respuestas vacías no reemplazan automáticamente el guardado válido. La cámara incluye las posiciones guardadas al abrirlo. Un fallo de conexión puede tardar hasta el siguiente ciclo de consulta y su timeout en activar el modo aproximado.

## Validación

Las 35 pruebas de Flutter pasan, incluida persistencia de las ubicaciones, conservación de su antigüedad, límite de la estimación sin modificar el dato original y apertura del viaje sin datos con marcador de colectivo y sin TileLayer. El cambio automático después de cortar datos todavía requiere validación en teléfono.

La APK debe compilarse con `flutter build apk --release`. La compilación de desarrollo no sirve para comparar tamaño o fluidez.

## Tamaño de la APK universal

La revisión del archivo encontró las bibliotecas nativas de las tres arquitecturas sin comprimir como principal componente. Se quitó la fuente Cupertino sin uso y se activó `jniLibs.useLegacyPackaging = true`: [documentación de Android](https://developer.android.com/reference/tools/gradle-api/7.3/com/android/build/api/variant/JniLibsApkPackaging).

La compilación release pasa de 54,7 MB a 24,7 MB (aproximadamente 55 % menos). Conserva arm64-v8a, armeabi-v7a y x86_64, Android 7 o posterior. `aapt` confirma `extractNativeLibs=true`: Android extrae las bibliotecas de la arquitectura del dispositivo al instalar. La reducción corresponde a la descarga; no demuestra una reducción equivalente del almacenamiento instalado o RAM. También se comprobó en el ZIP que las bibliotecas están comprimidas.

## Medición pendiente en Android

No hay un teléfono conectado por ADB durante esta revisión. No se ha medido RAM, batería ni tiempos de cuadros en un dispositivo real.

En el mismo teléfono y recorrido, comparar una sesión con conexión de diez minutos (zoom, desplazamiento y selección de interno), cinco minutos en segundo plano y una sesión con el viaje preparado y Wi-Fi/datos apagados. Comprobar que el interno seleccionado se conserva, que el modo sin datos muestra la antigüedad y que no indica posiciones en vivo. Para medir cuadros se necesita una compilación de perfil conectada al teléfono; anotar cuadros lentos, memoria y tráfico antes de afirmar una mejora cuantitativa.
