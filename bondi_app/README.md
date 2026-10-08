# Subite — APK Flutter

Aplicación de colectivos de Córdoba. Las responsabilidades y reglas de mantenimiento están en [ARCHITECTURE.md](../ARCHITECTURE.md).

## Ejecutar y verificar

Desde esta carpeta:

```powershell
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
flutter run
flutter build apk --release --no-pub
```

La APK queda en `build/app/outputs/flutter-apk/app-release.apk`. El backend predeterminado está definido en `lib/services/api_service.dart`. Para usar otro:

```powershell
flutter run --dart-define=BONDI_API_URL=https://servidor/api
```

Ejecutar el backend con `go run .` desde `../server_go/`. Compilar el paquete completo con `go build .`; el arranque HTTP está en `runtime.go`.

## Viajes y búsqueda

La búsqueda combina paradas, lugares recientes/guardados y `/api/places`. Las direcciones con altura sin verificar requieren confirmar un punto en el mapa. El catálogo se consulta con concurrencia acotada y las respuestas de búsquedas anteriores se descartan.

Los viajes directos respetan el sentido de la geometría y permiten hasta 800 m de caminata en línea recta por extremo. Las alternativas se comparan con las llegadas y el tiempo supuesto para alcanzar la parada. No se calculan transbordos ni caminatas por calles.

Las posiciones provienen de coordenadas de `/api/arrivals`. Las llegadas se filtran por línea y recorrido y sus posiciones además por empresa. Una etiqueta de demora no se interpreta como hora de llegada; el horario ajustado tiene prioridad sobre la hora de salida.

## Sin datos

Elegir un viaje guarda extremos, empresa, línea, sentido, geometría y paradas. Con conexión se actualizan las posiciones disponibles. Una respuesta vacía conserva la última referencia útil. El guardado admite el formato anterior y sobrevive al reinicio.

La APK incluye calles, parques y cursos de agua de Córdoba bajo ODbL, con atribución OpenStreetMap: [licencia y actualización del dataset](assets/maps/README.md). El mapa local no necesita red.

Sin conexión se calcula el avance cada 30 segundos desde la posición y hora originales, suponiendo 18 km/h hasta el final del recorrido. No conoce tránsito, detenciones ni vueltas posteriores; siempre se presenta como estimación. Las consultas del viaje se suspenden en segundo plano; al reabrir se recalcula el tiempo transcurrido.

## Avisos

El aviso de bajada usa ubicación local, requiere dos posiciones recientes y precisas dentro del radio elegido y emite un aviso único. Android pide permisos y muestra una notificación durante el seguimiento. El sistema puede detener el proceso.

El aviso de llegada consulta horarios mientras la app está abierta y conectada y puede filtrar un interno. Cambiar el viaje o entrar sin datos lo cancela; no convierte posiciones estimadas en llegadas confirmadas.

La lógica, los widgets y la compilación se verifican localmente. Permisos, GPS, notificaciones y rendimiento requieren comprobación adicional en un teléfono Android.
