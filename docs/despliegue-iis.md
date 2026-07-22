# Despliegue en IIS + SQL Server (producción)

Guía para publicar **Control de Visitas** en un servidor Windows con IIS y
SQL Server. El frontend se sirve **desde el mismo sitio que la API**
(mismo-origen: sin CORS, el front usa rutas relativas).

> Requiere revisión del DBA para la parte de base de datos y de TI para el
> servidor. Los pasos marcados con ⚠️ son decisiones/permisos que no deben
> omitirse.

---

## 0) Prerrequisitos en el servidor

- **Windows Server con IIS** habilitado.
- **.NET 8 Hosting Bundle** (ASP.NET Core Module / ANCM) instalado
  *después* de IIS. Descarga: "ASP.NET Core Runtime 8.x - Hosting Bundle".
  Verificar con `dotnet --info` o reiniciar IIS (`net stop was /y && net start w3svc`).
- Acceso al **SQL Server** productivo (mismo servidor u otro alcanzable).
- El servidor debe poder alcanzar **`celexpos.celex.com`** (login WishPOS).

---

## 1) Base de datos (con el DBA) ⚠️

1. Crear la base (o que el DBA la cree). El script incluye `CREATE`/uso de
   `ControlVisitas_Celex`; ajustar al estándar del DBA.
2. Correr `db/cv-modelo-datos.sql` **forzando el codepage UTF-8**, si no los
   acentos se guardan corruptos:
   ```
   sqlcmd -S SERVIDOR -d ControlVisitas_Celex -f i:65001 -i cv-modelo-datos.sql
   ```
3. ⚠️ **`WM_Correo` NO se crea**: ya existe en la base de WishPOS. El script
   crea un **SYNONYM** `dbo.WM_Correo` que apunta a esa tabla
   (`CREATE SYNONYM dbo.WM_Correo FOR WISH.dbo.WM_Correo`). En el servidor
   real, **reapuntar el synonym** al nombre real de la base de WishPOS si
   difiere de `WISH`, y otorgar al login de la app permiso de **INSERT** sobre
   esa tabla (acceso cross-database). Así `sp_CV_Visitas_Registrar` inserta en
   `dbo.WM_Correo` sin acoplarse al nombre físico de la base.
4. Confirmar que el **SQL Server Agent Job** que envía `WM_Correo`
   (`Enviar='Si'`, `Enviado='No'`) está activo — es quien manda el correo de
   confirmación al visitante.

---

## 2) Publicar la API

Desde la carpeta `api/` (en la máquina de build):

```
dotnet publish -c Release -o C:\publish\control-visitas
```

Esto genera:
- El `web.config` para IIS (ANCM) automáticamente.
- `wwwroot/index.html` (el frontend, copiado desde `web/index.html` por el
  target del `.csproj`).

Copiar el contenido de `C:\publish\control-visitas` al servidor, p. ej.
`C:\inetpub\control-visitas`.

---

## 3) Cadena de conexión (en el servidor) ⚠️

`appsettings.Production.json` **no** se sube a git. En el servidor, junto al
resto de archivos publicados, crear `appsettings.Production.json` a partir de
`appsettings.Production.example.json` y ajustar la cadena:

- **Opción A — Autenticación de Windows**: `Trusted_Connection=True`. Requiere
  dar de alta la **identidad del App Pool** (ver paso 4) como login en SQL con
  permisos sobre `ControlVisitas_Celex` (ejecutar los SP + leer/escribir las
  tablas `CV_*`) **y** permiso de INSERT sobre `WM_Correo` en la base de WishPOS
  (a la que apunta el synonym).
- **Opción B — Usuario/contraseña de SQL**: `User Id=...;Password=...;` con un
  login dedicado y los mismos permisos.

`ASPNETCORE_ENVIRONMENT` debe ser `Production` (IIS lo pone así por defecto vía
el `web.config`; si no, agregarlo como variable de entorno del App Pool).

---

## 4) Sitio en IIS

1. **Application Pool** nuevo, p. ej. `ControlVisitas`:
   - **.NET CLR version: "No Managed Code"** (ANCM hospeda el runtime).
   - Identidad: `ApplicationPoolIdentity` (o una cuenta de servicio dedicada
     si se usa autenticación de Windows contra SQL).
2. **Sitio web** (o aplicación) apuntando a la carpeta publicada
   (`C:\inetpub\control-visitas`), usando ese App Pool.
3. **Bindings**: configurar **HTTPS** con un certificado (interno de la
   empresa sirve). ⚠️ HTTPS es **obligatorio**: la captura de foto en la
   caseta usa la cámara del navegador, que solo funciona en contexto seguro
   (https) o en localhost.
4. **Permisos de carpeta** ⚠️:
   - La identidad del App Pool necesita **lectura** sobre la carpeta de la app.
   - Necesita **lectura/escritura** sobre la carpeta de fotos configurada en
     `CV_Configuracion.RutaFotos` (por defecto `C:\Control de Visitas\Fotos`).
     Crear esa carpeta y dar permiso a la identidad del App Pool (o
     `IIS AppPool\ControlVisitas`).

---

## 5) Configuración post-despliegue

Entrar al sistema con un usuario que tenga el permiso de Configuración
(pantalla WishPOS `CV.200.00`) y, en **Configuración**:

- Ajustar **RutaFotos** / **PrefijoFoto** / **DigitosFoto** si aplica.
- Dar de alta en **"Usuarios que pueden marcar visitas VIP"** los `Usuario_ID`
  (los que aparecen al iniciar sesión) que deban ver el checkbox VIP.

> Cambiar la lista VIP surte efecto la próxima vez que esos usuarios
> **inicien sesión** (se resuelve en el login).

---

## 6) Verificación (humo)

1. Abrir `https://SERVIDOR/` → debe cargar la pantalla de login.
2. Iniciar sesión con una contraseña real de WishPOS.
3. Registrar una visita → generar código de acceso → confirmar que llega el
   **correo** al visitante (lo envía el Job de `WM_Correo`).
4. En la caseta: teclear el código + apellido → foto → etiqueta con código de
   salida.
5. Registrar salida con el código de salida.
6. Revisar **Reportes** y **Mis Visitas**.

---

## 7) Actualizaciones futuras

Para publicar una nueva versión: repetir el paso 2 (`dotnet publish`) y copiar
al servidor (detener el sitio o el App Pool durante la copia para liberar el
`.dll`). La base solo se toca si el script cambió (coordinar con el DBA;
los `CREATE PROCEDURE` deben volverse `CREATE OR ALTER` o eliminarse antes de
recrear, según prefiera el DBA).

---

## Notas

- **Kiosko/caseta**: seguir `docs/checklist-modo-kiosco.md` para el equipo
  físico (Assigned Access, flags de Chrome, certificado).
- **CORS**: no se necesita en este esquema (mismo-origen). La política
  `MockupDev` solo se activa en entorno de Desarrollo.
- **Correo**: no requiere Azure/Graph ni secretos — se encola en `WM_Correo` y
  lo envía el Job existente de SQL Server.
