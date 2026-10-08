# Backend de Subite

El servidor puede ejecutarse como binario Go o contenedor en cualquier proveedor. No necesita una base de datos ni disco persistente. El proveedor debe ofrecer HTTPS y poder consultar los servicios externos por Internet.

## Configuración

- `PORT`: puerto de escucha; por defecto 3001. El contenedor usa 8080. Escucha en todas las interfaces.
- Comprobación de salud: `GET /api/health`. No consulta al servicio de transporte.
- Compilación: desde `server_go`, `go build -trimpath -ldflags="-s -w" -o subite .`.
- Inicio: `./subite` (en Windows, `subite.exe`).
- Contenedor: desde la raíz, `docker build -t subite-backend .` y `docker run --rm -p 8080:8080 subite-backend`.

Usar una sola instancia inicialmente. Las llegadas se comparten durante 15 segundos por parada, con hasta 256 entradas y ocho consultas simultáneas al proveedor. Las consultas concurrentes a la misma parada comparten una petición. Si se supera el límite, responde 503 con `Retry-After: 2`. Los errores no se guardan como llegadas válidas. Estos límites no garantizan la capacidad de un proveedor concreto: depende de las paradas diferentes consultadas y del servicio de transporte.

Los tiempos de espera HTTP están limitados y el servidor permite hasta diez segundos para terminar peticiones cuando recibe SIGTERM. La caché se pierde al reiniciar y se reconstruye con las consultas. Revisar consumo de memoria, errores 5xx y latencia antes de ampliar usuarios.

El caché de llegadas ocupa hasta 8 MiB y el de recorridos hasta 16 MiB, además del límite de 256 entradas por caché. Los recorridos vencen a las 24 horas. Los catálogos se comprimen con gzip cuando el cliente lo acepta. Hay hasta 16 consultas simultáneas al servicio de transporte y ocho búsquedas de lugares; las peticiones repetidas de llegadas y recorridos comparten sus resultados.

En el celular se reutilizan conexiones HTTP, se comparten cargas simultáneas del mismo recorrido y se validan datos antes de persistirlos. Un catálogo de líneas guardado hace menos de 30 minutos carga localmente; los recorridos guardados se renuevan después de un día. Los datos vencidos pueden usarse como respaldo sin conexión. La primera carga sin catálogo permite hasta 65 segundos para el despertar del hosting gratuito; esto no garantiza que Render termine dentro de ese plazo.

## Conectar la APK

Una vez obtenido el dominio HTTPS, desde `bondi_app`:

```sh
flutter build apk --release --dart-define=BONDI_API_URL=https://TU_DOMINIO/api
```

Probar `/api/health`, una línea y sus llegadas desde el celular con Wi-Fi y con datos móviles antes de distribuir. Una APK que apunte a la IP local de la PC no funcionará fuera de esa red.

## Hosting

Koyeb ya exige un plan pago para nuevas cuentas: https://www.koyeb.com/blog/koyeb-is-joining-mistral-ai-to-build-the-future-of-ai-infrastructure

Render documenta una instancia gratuita que se suspende tras 15 minutos sin tráfico: https://render.com/docs/free. Sirve para pruebas si se acepta la demora al despertar. Verificar sus condiciones al crear el servicio. Configurar directorio raíz `server_go`, compilación `go build -trimpath -ldflags="-s -w" -o subite .`, inicio `./subite` y health check `/api/health`. HTTPS lo gestiona el proveedor.

El primer despliegue está disponible en `https://subite-backend.onrender.com`, pero estas mejoras locales requieren publicarse para llegar al servidor. La APK también requiere recompilarse para incorporar los cambios del cliente.
