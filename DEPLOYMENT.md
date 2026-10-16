# Backend de Subite

El servidor puede ejecutarse como binario Go o contenedor en cualquier proveedor. No necesita una base de datos ni disco persistente. El proveedor debe ofrecer HTTPS y poder consultar los servicios externos por Internet.

## Configuración

- `PORT`: puerto de escucha; por defecto 3001. El contenedor usa 8080. Escucha en todas las interfaces.
- `TRUSTED_PROXY_CIDRS`: rangos CIDR separados por comas de los proxies que realmente pueden conectarse al backend. Sin configurar, se usa la IP de la conexión y se ignora `X-Forwarded-For`. Con proxies configurados, se recorre esa cabecera desde la derecha hasta la primera IP no confiable. No usar `0.0.0.0/0`, `::/0` ni confiar indiscriminadamente en redes privadas. Configurar y verificar toda la cadena del proveedor antes de publicar detrás de Render u otro proxy: de lo contrario los usuarios pueden compartir la cuota del proxy. No copiar rangos de ejemplo a producción. Restringir el acceso directo al origen cuando corresponda.
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

## Protección de la API

Por instancia: hasta 600 peticiones por minuto por IP (las IPv6 comparten cuota por /64), 30 búsquedas por minuto por IP, 12 peticiones simultáneas por IP y 64 en total. Además, por IP hay hasta seis peticiones de recorridos, tres de llegadas, tres de colectivos y dos de búsquedas simultáneas. El planificador normal usa tres cargas de recorridos. Las cuotas se comparten en redes con NAT; ajustar con evidencia de uso real si limita a usuarios legítimos. Se responde 429 con `Retry-After` al superar cuotas; el health check queda disponible. El registro de cuotas admite hasta 4096 clientes y no guarda sus IP en disco. Los límites son locales a cada proceso: mantener una instancia inicialmente; no son una protección completa contra ataques distribuidos.

Las peticiones admitidas tienen un contexto de 30 segundos; las esperas de catálogo, recorrido, búsqueda, colectivos y sesión respetan su cancelación. Colectivos comparte cargas y caché por ruta/empresa durante 15 segundos, con un máximo de 8 MiB. Búsquedas comparte cargas iguales y guarda hasta 4 MiB durante 15 minutos. Los recorridos se aceptan únicamente si la combinación línea/ruta/empresa existe en el catálogo vigente. Los errores al cliente no incluyen los errores internos del transporte.

Antes de desplegar, verificar la cadena de proxies y probar que dos clientes tienen cuotas independientes y que una cabecera reenviada inventada no cambia la identidad efectiva. No habilitar logs de URL completa, query strings, cuerpos de búsqueda o coordenadas personales. El código Go no registra esos datos; los access logs y su retención deben revisarse en el proveedor. Los servicios externos tienen sus propias políticas. No se ha cambiado la configuración de ninguna cuenta de hosting mediante estos cambios locales.

`/api/health` informa también la revisión recibida en `RENDER_GIT_COMMIT`. Las respuestas admitidas incluyen `X-RateLimit-Remaining` y `X-RateLimit-Reset` para comprobar cuotas sin exponer IPs ni enviar consultas al proveedor. En Render Free, el origen no recibe conexiones de la red privada; la confianza en proxies internos debe limitarse al entorno de ese servicio y completarse con los [rangos oficiales de Cloudflare](https://www.cloudflare.com/ips/). Verificar la cadena con peticiones de bajo costo desde dos redes antes de dar el despliegue por validado.
