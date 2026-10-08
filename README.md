# Subite

App para viajar en colectivo en Córdoba, Argentina. Cliente móvil en Flutter/Dart y backend en Go.

Permite elegir inicio y destino, comparar líneas y paradas, consultar las llegadas y posiciones disponibles, guardar viajes, activar avisos y registrar gastos manualmente. Los viajes guardados conservan últimas posiciones para mostrar estimaciones sin datos; no son ubicaciones en vivo ni incluyen una descarga del mapa de calles.

## Desarrollo

Necesitás Flutter con el SDK de Android y Go 1.23 o posterior.

Backend:

```sh
cd server_go
go run .
```

Escucha en el puerto 3001. Los datos de transporte dependen del servicio externo y pueden no estar disponibles para todas las líneas.

Para publicar el backend con HTTPS y conectar la APK, ver [DEPLOYMENT.md](DEPLOYMENT.md).

App:

```sh
cd bondi_app
flutter pub get
flutter run --dart-define=BONDI_API_URL=http://IP_DE_TU_PC:3001/api
```

El teléfono debe poder acceder al backend. Para probar HTTP local en Android, ajustá el dominio permitido en `bondi_app/android/app/src/main/res/xml/network_security_config.xml`. Para una distribución pública hace falta un backend accesible por HTTPS.

## Verificación y compilación

```sh
cd server_go
go test ./...
```

```sh
cd bondi_app
flutter test
flutter build apk --release --dart-define=BONDI_API_URL=https://TU_SERVIDOR/api
```

La APK se genera en `bondi_app/build/app/outputs/flutter-apk/app-release.apk`. Las compilaciones y dependencias descargadas no se incluyen en Git. El proyecto usa actualmente firma de desarrollo; configurar la firma de publicación antes de distribuir una versión definitiva en Google Play.

El nombre visible es Subite. El identificador Android existente se mantiene durante estas pruebas para conservar la compatibilidad de actualización.

Proyecto independiente, sin afiliación con la Municipalidad de Córdoba ni los operadores de transporte.
