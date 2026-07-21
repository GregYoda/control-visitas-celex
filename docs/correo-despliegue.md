Para: [Equipo de TI / Infraestructura], [DBA]
CC: [interesados]
Asunto: Despliegue a producción — Sistema Control de Visitas (IIS + SQL Server)

Hola:

Solicito su apoyo para desplegar en producción el sistema **Control de Visitas**
(registro de visitantes con código de acceso, foto en caseta, código de salida
y reportes). Ya está probado en el ambiente local y listo para publicar. El
frontend se sirve desde la misma aplicación (mismo sitio que la API), así que
solo se publica una app en IIS.

El repositorio incluye una guía técnica más extensa en `docs/despliegue-iis.md`;
abajo el resumen con los puntos que no se deben omitir.

──────────────────────────────────────────────
PARTE 1 — BASE DE DATOS (DBA)
──────────────────────────────────────────────

1. Base de datos: `ControlVisitas_Celex` (o el nombre que definan; avísenme para
   ajustar la cadena de conexión). Script: `db/cv-modelo-datos.sql`.

2. ⚠️ Correr el script FORZANDO codepage UTF-8; de lo contrario los acentos se
   guardan corruptos (ej. "Almacén" → "AlmacÃ©n"):

       sqlcmd -S [SERVIDOR_SQL] -d ControlVisitas_Celex -f i:65001 -i cv-modelo-datos.sql

3. ⚠️ NO crear la tabla `WM_Correo`. Ya existe en producción (es la cola de
   correos que ya usan otros procesos). En el script hay un bloque
   `CREATE TABLE dbo.WM_Correo` que es SOLO para el ambiente local de pruebas:
   por favor omitirlo/eliminarlo antes de correr en el servidor real. El sistema
   inserta en esa tabla existente para enviar el correo de confirmación al
   visitante (vía el Job de SQL Server Agent que ya la procesa).

4. Confirmar que el Job de SQL Server Agent que envía `WM_Correo`
   (los registros con `Enviar='SI'` y `Enviado='NO'`) esté activo. De él depende
   que al visitante le llegue su código de acceso por correo.

5. ⚠️ Acceso de la aplicación a la base. Según cómo prefieran:
   - Opción A (recomendada): autenticación de Windows. Dar de alta la identidad
     del Application Pool de IIS (ej. `IIS AppPool\ControlVisitas`) como login en
     SQL, con permiso para EJECUTAR los stored procedures `sp_CV_*` y
     leer/escribir las tablas `CV_*` y `WM_Correo`.
   - Opción B: crear un login de SQL (usuario/contraseña) dedicado con esos
     mismos permisos; nosotros lo ponemos en la cadena de conexión.

6. Revisión: agradecería que revisen el script antes de correrlo (nombres de
   esquema, collation, índices) para que quede alineado con sus estándares.

──────────────────────────────────────────────
PARTE 2 — SERVIDOR / IIS (TI)
──────────────────────────────────────────────

1. Prerrequisitos en el servidor:
   - IIS habilitado.
   - ⚠️ Instalar el ".NET 8 Hosting Bundle" (ASP.NET Core Module) DESPUÉS de
     IIS, y reiniciar IIS. Es lo que permite hospedar la app .NET en IIS.

2. Publicación: nosotros entregamos el paquete ya compilado (resultado de
   `dotnet publish -c Release`), que incluye el `web.config` y el frontend. Solo
   hay que copiarlo a una carpeta del servidor (ej. `C:\inetpub\control-visitas`).

3. Sitio en IIS:
   - Application Pool nuevo con ⚠️ ".NET CLR version: No Managed Code".
   - Sitio/aplicación apuntando a la carpeta publicada, usando ese App Pool.
   - ⚠️ Binding HTTPS con certificado (interno de la empresa sirve). HTTPS es
     OBLIGATORIO: la toma de foto en la caseta usa la cámara del navegador, que
     solo funciona en sitios seguros (https).

4. ⚠️ Permisos de carpeta para la identidad del App Pool:
   - Lectura sobre la carpeta de la aplicación.
   - Lectura/escritura sobre la carpeta donde se guardan las fotos de los
     visitantes (por defecto `C:\Control de Visitas\Fotos`; es configurable
     desde el sistema). Crear esa carpeta y otorgar el permiso.

5. Cadena de conexión: se configura en el servidor en un archivo
   `appsettings.Production.json` (no viaja en el código). Hay una plantilla
   (`appsettings.Production.example.json`); coordinamos el valor según la
   Opción A o B del punto 5 de la Parte 1.

6. Conectividad de salida: el servidor debe poder alcanzar
   `celexpos.celex.com` (el login del sistema valida contra WishPOS).

──────────────────────────────────────────────
LO QUE NECESITAMOS DE USTEDES
──────────────────────────────────────────────

- DBA: nombre/instancia del SQL Server, confirmación de la base creada, el
  esquema de acceso elegido (A o B) y confirmación del Job de `WM_Correo`.
- TI: nombre del servidor y la URL/host con que quedará publicado (para
  documentarlo), y el certificado HTTPS.

Con esos datos coordinamos la ventana para publicar y hacer la prueba de humo
(login, registro → código, acceso en caseta con foto, salida y reportes).

Quedo atento a cualquier duda.

Saludos,
[Nombre]
[Puesto / contacto]
