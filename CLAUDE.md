# Control de Visitas — Celex

Sistema de control de acceso de visitantes para Celex (Distribuidor Autorizado Telcel,
Región 5: Jalisco / Michoacán / Nayarit / Colima). Reemplaza el registro en papel en
recepción/caseta por un flujo digital con QR, foto y código de salida.

## Estado actual del proyecto

- ✅ **Mockup funcional** (`web/index.html`) — HTML/CSS/JS puro, sin build step.
  Cubre: login de empleado (WishPOS), registro de visita, generación de QR real
  (`qrcode.js`), lectura de QR real por cámara (`jsQR`), validación de apellido
  paterno, captura de foto del visitante, etiqueta de acceso con código de salida
  de 6 dígitos, registro de salida vía teclado numérico (PIN pad), reportes por
  rango de fechas con export a CSV, y un teclado en pantalla arrastrable/
  redimensionable para las pantallas de caseta (sin teclado/mouse físico).
- ✅ **Modelo de datos SQL Server** (`db/cv-modelo-datos.sql`) — borrador de tablas
  y stored procedures, pendiente de revisar con el DBA antes de correr en el
  servidor real.
- ✅ **Checklist de despliegue en modo kiosco** (`docs/checklist-modo-kiosco.md`)
  — certificado HTTPS interno, Windows Assigned Access, flags de Chrome, etc.
- ✅ **Ambiente beta local** — SQL Server Express corriendo en esta computadora
  (instancia default `MSSQLSERVER`, no `SQLEXPRESS`), base de datos
  `ControlVisitas_Celex` ya creada con el script de `db/cv-modelo-datos.sql`.
- ✅ **Scaffold de la API** (`api/`) — proyecto ASP.NET Core Web API (net8.0,
  controladores), con la cadena de conexión en `appsettings.Development.json`
  (Trusted Connection a `localhost`/`ControlVisitas_Celex`) y un endpoint de
  prueba `GET /api/areas` que ya lee de SQL Server real. Sirve como plantilla
  para los endpoints reales (registrar visita, validar acceso, etc.).
- ✅ **Columna `FechaVisita`** agregada a `CV_Visitas`, `sp_CV_Visitas_Registrar`
  (parámetro `@FechaVisita`), `sp_CV_Visitas_ValidarAcceso` (nuevo resultado
  `FECHA_NO_COINCIDE` si se escanea en un día distinto al registrado) y
  `sp_CV_Visitas_Reporte`. Probado con `sqlcmd` contra la base local: rechaza
  el acceso en fecha distinta y deja pasar en la fecha correcta.
- ✅ **Autenticación real contra WishPOS** (`POST /api/auth/login`) — el login
  de empleado y el de caseta/kiosko ya solo piden contraseña (sin usuario). La
  API la convierte a **SHA-512** (no MD5, ver nota abajo) y llama a
  `celexpos.celex.com/prod/WSWish.asmx/mtdActiva11` con `Proceso: System_LOGIN`,
  la IP real del cliente como `Origin`, y un `UUID` nuevo por intento. Probado
  end-to-end contra el servidor real (caso de acceso denegado).
- ⬜ **Pendiente:** el resto de endpoints de la API contra los demás stored
  procedures, envío de correo real (Graph API / M365), subir la foto capturada
  a disco/blob en vez de mantenerla solo en memoria.

## Decisiones de diseño ya tomadas (no las reabras sin razón)

- El QR codifica un **UUID real**, generado y leído con librerías reales
  (`qrcode.js` / `jsQR`), no es un placeholder visual.
- El **código de salida** es un número aleatorio de 6 dígitos, único solo entre
  visitas *activas del mismo día* (no globalmente único para siempre) — así se
  puede reciclar al día siguiente. Se genera al momento del acceso (no del
  registro), y se muestra en la etiqueta para que el visitante lo conserve.
- El registro de salida usa un **teclado numérico tipo PIN** dedicado en pantalla,
  no el teclado QWERTY genérico — es más simple de usar en un kiosko touch.
- Antes de cerrar la salida se muestra una pantalla de confirmación ("¿Eres tú?"
  con foto + nombre) para evitar cerrar el acceso de la persona equivocada por
  un error de tecleo.
- Una visita **no puede iniciarse (accesarse) en una fecha distinta a su
  `fechaVisita` registrada** — si al escanear el QR la fecha de hoy no
  coincide, se rechaza el acceso con mensaje al usuario en vez de dejarlo
  pasar a validación. Esta regla debe replicarse en el SP/endpoint real de
  "registrar acceso" cuando exista la API.
- **Login solo con contraseña, validado contra WishPOS** (`system_LOGIN` de
  `celexpos.celex.com`) — no se pide usuario, en ambas pantallas (empleado y
  caseta). ⚠️ El equipo de negocio describió el hash como "MD5", pero al
  verificarlo contra el ejemplo real que dieron (`203` → hash de 128
  caracteres), es **SHA-512**, no MD5 (que da 32 caracteres). Ver
  `api/Servicios/WishPosAuthService.cs`. Esa llamada la hace la API, nunca el
  navegador (evita CORS contra un dominio externo y evita que el cliente
  construya la URL con el hash de la contraseña). `Error_Codigo: 0` en la
  respuesta = éxito; cualquier otro valor = acceso denegado, con
  `Error_Mensaje` como texto a mostrar. El menú/permisos (`Accesos`,
  `MiEspacio`) que regresa WishPOS no se usa aquí, solo `Usuario` y `Nombre`.
- El teclado en pantalla (QWERTY, arrastrable/redimensionable) solo debe
  aparecer en las pantallas del lado de **caseta/kiosko** (login de caseta,
  home, escaneo, validación, foto, badge, código de salida, confirmación,
  salida registrada) — nunca en las pantallas de empleado, que sí tienen
  teclado/mouse reales.
- Estilo visual: se sigue el look de WishPOS existente (topbar azul con degradado,
  sidebar gris-azulado con íconos, tarjetas con círculo morado, ola teal al
  fondo) — no se debe rediseñar sin que el usuario lo pida explícitamente.

## Convenciones SQL (mismo patrón que el resto del stack de Celex)

- Prefijo de tablas/SPs de este módulo: `CV_` (Control de Visitas), para no
  mezclarse con las tablas `Yoda_*` del bot de sincronización WishPoS↔Telcel.
- Columna `UUID` (uniqueidentifier, default `NEWID()`) en tablas que necesitan
  un identificador externo/público (igual que en `Yoda_Cat_Ladas`).
  En `CV_Visitas`, ese `UUID` es justo el valor que se codifica en el QR.
  el patrón `ID_Fecha_Modificacion` (default `'1900-01-01 00:00:00'`) se usa
  para auditoría de cambios, igual que en el resto de las tablas de Celex.
- INSERTs de catálogos siguen el patrón `SELECT` sin `FROM` cuando aplica.
- Comparación de apellidos: quitar acentos + mayúsculas antes de comparar
  (mismo criterio que la normalización de direcciones ya existente — si ya
  hay una función para esto, reutilizarla en vez de `fn_CV_QuitarAcentos`).
- **Ojo al correr el script con `sqlcmd`:** el archivo está en UTF-8 sin BOM;
  si se corre con `sqlcmd -i cv-modelo-datos.sql` a secas, los literales
  `N'...'` con acentos se guardan corruptos (mojibake, ej. `AlmacÃ©n`). Hay que
  forzar el codepage de entrada: `sqlcmd -f i:65001 -i cv-modelo-datos.sql`.
  Avisar de esto al DBA cuando corra el script en el servidor productivo.

## Estructura del repo

```
control-visitas-celex/
├── web/    → frontend (hoy: mockup HTML autocontenido; mañana: app real conectada a la API)
├── api/    → API en ASP.NET Core (net8.0) que expone los stored procedures como REST
├── db/     → modelo de datos SQL Server (tablas + stored procedures)
└── docs/   → checklist de despliegue del kiosko y cualquier otra documentación
```

## Siguientes pasos (backlog sugerido)

1. ✅ Stack de la API: **.NET (ASP.NET Core)** — se eligió sobre Node/Express
   por su integración nativa con IIS (módulo ANCM), ya que el plan de
   despliegue es desarrollar en esta computadora (con SQL Server Express
   local) y después mover a un servidor IIS + SQL Server productivos. Ya hay
   scaffold en `api/` con un endpoint de prueba funcionando end-to-end.
2. ✅ `FechaVisita` agregada a `CV_Visitas` y a los SPs de registrar/validar
   acceso/reporte (ver "Estado actual" arriba).
3. ✅ Endpoints reales de la API sobre todos los stored procedures: registrar
   visita, validar acceso, buscar/confirmar salida, reporte, listar áreas.
   Probados end-to-end contra SQL Server real.
4. ✅ Autenticación contra WishPOS resuelta: `system_LOGIN` vía
   `POST /api/auth/login` (ver "Estado actual" y "Decisiones de diseño"
   arriba). No hizo falta AD/LDAP — WishPOS ya expone el login por contraseña.
5. Reemplazar el estado en memoria de `web/index.html` por llamadas reales a
   la API:
   - ✅ Registrar visita (`generarQR`, con áreas cargadas de `GET /api/areas`).
   - ✅ Login (`doLogin` / `doKioskLogin` ya llaman a `POST /api/auth/login`;
     ambas pantallas solo piden contraseña).
   - ✅ Validar acceso / escaneo de QR en kiosko (`onQRDetected` +
     `submitValidate` ya llaman a `POST /api/visitas/validar-acceso`; los 5
     resultados posibles —OK, NO_ENCONTRADO, YA_UTILIZADO, FECHA_NO_COINCIDE,
     APELLIDO_NO_COINCIDE— se probaron end-to-end desde la página real).
   - ✅ Registro de salida (`submitSalidaCodigo` + `confirmarSalida` ya llaman
     a `GET /api/visitas/salida/{codigo}` y
     `POST /api/visitas/salida/{id}/confirmar`; `pendingSalidaVisitId` ahora
     es el ID numérico de `CV_Visitas`, no el UUID del QR).
   - ✅ Reportes (`generarReporte` llama a `GET /api/reportes`; el CSV
     (`exportarCSV`) ahora exporta exactamente lo último generado en pantalla,
     ya no ignora el rango de fechas como antes).
6. Subir la foto capturada a disco/blob storage (hoy vive como data URL en
   memoria) y guardar la ruta en `CV_Visitas.FotoRuta`.
7. Integrar envío de correo real vía Graph API (mismo patrón que Circulares Telcel).
8. Seguir `docs/checklist-modo-kiosco.md` para el despliegue en la caseta.

## Idioma y tono

Todo el copy de la interfaz, comentarios de código y commits deben ir en
español (México), consistente con el resto del proyecto.
