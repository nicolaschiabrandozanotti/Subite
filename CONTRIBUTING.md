# Contribuir a Subite

¡Gracias por querer mejorar Subite! Las ideas, los errores reproducibles y las sugerencias de experiencia de uso son bienvenidos.

## Flujo de trabajo

Subite utiliza un **GitFlow ligero**:

| Rama | Propósito |
| --- | --- |
| `main` | Código estable y versiones publicadas. |
| `develop` | Integración de cambios aprobados para la próxima versión. |
| `feat/<descripcion>` | Funcionalidades nuevas. |
| `fix/<descripcion>` | Correcciones de errores. |
| `docs/<descripcion>` | Documentación, recursos visuales y guías. |

Las ramas de trabajo **nacen de `develop`** y regresan a **`develop` por Pull Request**. No se crean ramas permanentes llamadas literalmente `feat`, `fix` o `docs`, porque bloquearían nombres como `feat/alertas`.

### Pasos habituales

```bash
git fetch origin
git switch develop
git pull --ff-only origin develop
git switch -c feat/descripcion-corta
# Realizá los cambios y verificalos localmente.
git add .
git commit -m "feat: breve descripcion"
git push -u origin feat/descripcion-corta
```

Abrí un PR hacia `develop` y describí lo que cambiaste, cómo lo verificaste y qué puede afectar. Cuando se apruebe e integre, eliminá la rama temporal.

### Publicación de versiones

1. Integrar y validar los cambios en `develop`.
2. Abrir un PR de `develop` hacia `main`.
3. Tras fusionarlo, publicar un tag desde `main` como `v1.0.5`.
4. Las correcciones urgentes pueden salir de `main` en `fix/urgente-descripcion`: fusionar a `main` y luego incorporar el arreglo también a `develop`.

No realizar pushes directos a `main` ni `develop` como práctica de trabajo. Las revisiones y los controles de CI deben completarse antes de cada merge.

## Convenciones de commits

Utilizá mensajes cortos, por ejemplo:

- `feat: agregar una pantalla`
- `fix: corregir calculo de llegada`
- `docs: actualizar el README`
- `refactor: simplificar un servicio`
- `test: cubrir un caso limite`
- `chore: actualizar herramientas`

## Verificación

El repositorio incluye comprobaciones automáticas para Pull Requests a `develop` y `main`:

```bash
cd server_go
go test ./...
```

```bash
cd bondi_app
flutter pub get
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
```

Las pruebas automáticas no sustituyen las pruebas en dispositivos reales, especialmente para GPS, notificaciones o llegadas de proveedores externos.

## Ideas, reportes y aportes de código

- Para ideas o errores, abrí un [Issue](https://github.com/nicolaschiabrandozanotti/Subite/issues/new).
- La [licencia](LICENSE) de Subite permite determinados usos **no comerciales**, pero no habilita la explotación comercial por terceros.
- **Antes de enviar contribuciones de código**, contactá al autor para acordar expresamente los derechos y condiciones de incorporación. Enviar una idea o un PR no transfiere automáticamente derechos de autor ni concede al titular una licencia comercial sobre aportes ajenos.
- No incluyas claves, datos personales, imágenes o material de terceros sin autorización.
