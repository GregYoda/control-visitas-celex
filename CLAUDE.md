# Control de Visitas — Celex

Sistema de control de acceso de visitantes para Celex (Distribuidor Autorizado Telcel,
Región 5: Jalisco / Michoacán / Nayarit / Colima). Reemplaza el registro en papel en
recepción/caseta por un flujo digital con código de acceso, foto y código de salida.

## Estado actual del proyecto

- ✅ **Mockup funcional** (`web/index.html`) — HTML/CSS/JS puro, sin build step.
  Cubre: login de empleado (WishPOS), registro de visita con generación de un
  **código de acceso de 6 dígitos** (ya no QR, ver "Decisiones de diseño"),
  validación de apellido paterno, captura de foto del visitante, etiqueta de
  acceso con código de salida de 6 dígitos, registro de salida vía teclado
  numérico (PIN pad), reportes por rango de fechas con export a CSV, y un
  teclado en pantalla arrastrable/redimensionable para las pantallas de
  caseta que tienen campos de texto (sin teclado/mouse físico).
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
- ✅ **Mis visitas conectado a la API real** — listar (`GET /api/visitas/mias`)
  y editar (`PUT /api/visitas/{id}`, nuevo SP `sp_CV_Visitas_Actualizar`) ya no
  dependen del arreglo local en memoria; edición bloqueada server-side una vez
  que la visita ya fue accesada.
- ✅ **`ID_Usuario` de WishPOS guardado en `CV_Visitas`** — el `Usuario_ID`
  numérico que regresa el login (`POST /api/auth/login`) viaja en
  `session.usuarioId` y se manda como `idUsuario` al registrar una visita.
- ✅ **Esquema sin columnas NULL** — todas las columnas de `CV_Visitas` son
  `NOT NULL` con un valor "vacío" por tipo (`''` para texto, `0` para
  numéricos, `'1900-01-01 00:00:00'` para fechas, mismo centinela que ya
  usaba `ID_Fecha_Modificacion`). Los SPs comparan contra ese centinela en
  vez de `IS NULL`; la API traduce el centinela de vuelta a `null` en el
  JSON para no afectar al frontend (ver `NullSiVacia` en
  `VisitasRepositorio.cs`). Probado end-to-end (registrar → validar acceso →
  salida → reporte) confirmando que el JSON sigue mostrando `null` donde
  corresponde.
- ✅ **QR reemplazado por código de acceso de 6 dígitos** — la webcam +
  `jsQR` resultó poco confiable (enfoque/resolución de laptops comunes); se
  reemplazó por el mismo patrón ya probado del código de salida: un PIN pad
  dedicado. Se quitaron `qrcode.js`/`jsQR` del mockup. Ver "Decisiones de
  diseño" abajo para el detalle de unicidad del código.
- ✅ **Foto guardada en disco** (`POST /api/visitas/{id}/foto`) — ya no vive
  solo como `data:` URL en memoria. `FotoService.cs` la escribe en la ruta
  configurable (`CV_Configuracion.RutaFotos`, default
  `C:\Control de Visitas\Fotos`) con el nombre `<PrefijoFoto>` + ID de
  `CV_Visitas` con ceros a la izquierda a `<DigitosFoto>` dígitos (ej.
  `CV0000000001.jpg` con los defaults `CV`/`10`) y actualiza
  `CV_Visitas.FotoRuta`. No bloquea el flujo del kiosko si falla (la etiqueta
  en pantalla ya tiene la foto de todas formas).
- ✅ **Pantalla de Configuración** — nueva tabla `CV_Configuracion`
  (clave/valor) editable desde `screen-configuracion`: `RutaFotos`,
  `PrefijoFoto` y `DigitosFoto` (los 3 parámetros del nombrado de fotos, todos
  editables — ninguno quedó fijo en el código). Solo se muestra si el login
  de WishPOS incluye el permiso `Pantalla_Identidad = "CV.200.00"` (se busca
  recursivo en `Accesos`/`SubModule` y en `MiEspacio` — ver
  `WishPosAuthService.TieneAcceso`). Pensada para agregar más parámetros ahí
  mismo a futuro.
- ✅ **Campo `Observaciones`** en `CV_Visitas` (opcional, `NVARCHAR(500)`) —
  comentarios libres que quien registra puede dejar para que vigilancia los
  considere al recibir la visita. Se captura en el registro y en la edición
  (`Mis visitas`). **No se muestra en la etiqueta de acceso** (decisión
  explícita: ahí no debe ir); viaja en la respuesta de validación, en
  Reportes y en Mis Visitas para consultarse por esos medios.
- ✅ **Correo de confirmación al visitante — vía SQL Server, no Graph API.**
  Se decidió NO enviar desde la app: ya existe en el servidor productivo un
  mecanismo operando (SQL Server Agent Job cada minuto → revisa la tabla
  `WM_Correo` → `sp_send_dbmail` para lo que tenga `Enviar='Si'` y
  `Enviado='No'`). Esto evita meter un App Registration de Azure AD nuevo
  y todo el manejo de Client Secret que eso implicaba.
  `sp_CV_Visitas_Registrar` construye el asunto/HTML (código de acceso,
  datos del vehículo si `TraeAuto`, sin mencionar el código de salida) e
  inserta un renglón en `WM_Correo` con `TipoDocumento='Visita'`,
  `ID_UUID` = UUID de la visita, `Enviado='No'`, `Enviar='Si'`,
  `EnviadoFechaHr='1900-01-01 00:00:00'` (centinela), `IDFecha` = fecha de
  creación. El texto libre (Nombre, Empresa, Motivo, Observaciones) se
  sanea con `fn_CV_EscaparHtml` antes de meterlo al HTML (evita inyección).
  Importante: el HTML se construye en `NVARCHAR` con literales `N''` y se
  convierte a `VARCHAR` (tipo real de `WM_Correo`) hasta el final —
  concatenar literales sin `N''` corrompe los acentos al pasar por
  SQL Server. **`WM_Correo` ya existe en producción**; el `CREATE TABLE`
  en el script es solo para el entorno local de pruebas — al desplegar,
  apuntar a la tabla real y no correr ese bloque ahí.
- ✅ **Fotos servidas por la API, no por ruta de disco.** `CV_Visitas.FotoRuta`
  guarda una ruta de Windows (ej. `C:\Control de Visitas\Fotos\CV...jpg`), que
  un navegador no puede usar como `<img src>`. Se agregó
  `GET /api/visitas/{id}/foto` (`FotoService.ObtenerRutaFisicaAsync` recalcula
  la ruta con los valores *actuales* de `RutaFotos`/`PrefijoFoto`/`DigitosFoto`,
  no depende del `FotoRuta` guardado). La API ya no le manda la ruta cruda al
  frontend: `SalidaInfo`, `ReporteFila` y `MiVisita` cambiaron su campo
  `FotoRuta` por `TieneFoto` (booleano); el frontend arma la URL como
  `${API_BASE_URL}/api/visitas/{id}/foto`. Se evaluó servir las fotos
  directamente desde IIS (carpeta/virtual directory), pero se descartó: rompe
  la configurabilidad de `RutaFotos` (habría que reconfigurar IIS cada vez que
  cambie) y expone las fotos sin control de acceso. Corregido en
  `screen-salida-confirm`, Reportes y Mis Visitas — antes de este cambio esas
  tres pantallas nunca mostraban la foto real, solo el ícono de placeholder
  (la etiqueta de acceso justo después de tomar la foto sí funcionaba, porque
  usa el `data:` URL en memoria de la misma sesión, no `FotoRuta`).
- ✅ **Teclado en pantalla quitado de "etiqueta de acceso" y "salida
  registrada"** (`screen-badge`, `screen-salida-done`) — ninguna de las dos
  tiene un `<input>` de texto real, el botón no hacía nada ahí. `kioskScreens`
  en `showScreen()` ahora solo incluye `screen-validate`.
- ✅ **Cancelar visita desde "Mis visitas".** Nuevo estado `Status = 'Cancelada'`
  en `CV_Visitas` (antes solo `Pendiente`/`Accesado`) y SP
  `sp_CV_Visitas_Cancelar` — solo permite cancelar mientras sigue
  `Pendiente` (una vez que ya se usó el código de acceso, no tiene sentido
  cancelar; para eso está el flujo de salida). `sp_CV_Visitas_ValidarAcceso`
  rechaza el código con el nuevo resultado `CANCELADA` si la visita fue
  cancelada. `Estado` en Reportes/Mis Visitas ahora puede mostrar
  "Cancelada" (pill roja nueva). Endpoint `POST /api/visitas/{id}/cancelar`,
  botón "Cancelar esta visita" en la pantalla de edición (con confirmación),
  separado del botón "Volver sin guardar" (antes decía "Cancelar", ambiguo
  con la nueva acción).
- ✅ **Visita VIP (marcable solo por usuarios autorizados).** Nueva columna
  `CV_Visitas.EsVIP BIT NOT NULL DEFAULT(0)`. En la pantalla de registro (y
  en la edición) aparece un checkbox "⭐ Marcar como visita VIP", **pero solo
  se muestra a los usuarios autorizados**. La autorización se administra en la
  pantalla de Configuración con la nueva clave `CV_Configuracion.UsuariosVIP`
  = lista de `Usuario_ID` (el que devuelve el login de WishPOS) separados por
  coma (ej. `100,205`); vacío = nadie. El login (`AuthController`) calcula un
  nuevo booleano `puedeVIP` comparando el `Usuario_ID` contra esa lista y lo
  regresa en `LoginResponse` (igual patrón que `puedeConfigurar`); el frontend
  gatea el checkbox con `session.puedeVIP`. Defensa: el front solo manda
  `esVip=true` si `puedeVIP`, y al editar una visita un usuario sin permiso
  **conserva** el valor VIP existente en vez de borrarlo. Se muestra como
  "⭐ VISITA VIP" en la etiqueta de acceso (donde la caseta recibe) y como
  etiqueta ⭐ VIP en Mis Visitas y Reportes (además de una columna VIP en el
  CSV). SPs Registrar/Actualizar reciben `@EsVIP`; ValidarAcceso/MisVisitas/
  Reporte lo devuelven.
  El demo de capacitación (`web/demo-capacitacion.html`) ya incluye VIP en su
  backend simulado: el usuario `demo` (Usuario_ID 100) está en `UsuariosVIP`
  por defecto para poder mostrar el checkbox, y la visita semilla "María"
  viene marcada VIP.
- ⬜ **Pendiente:** despliegue en IIS + SQL Server productivo.

## Decisiones de diseño ya tomadas (no las reabras sin razón)

- El acceso se valida con un **código de acceso de 6 dígitos** (`CodigoAcceso`),
  no con un QR — la webcam de laptops comunes no enfoca bien a corta
  distancia y `jsQR` fallaba seguido en pruebas reales. El código se genera
  en `sp_CV_Visitas_Registrar` (no en el acceso, a diferencia del código de
  salida) y es único solo entre visitas de la **misma `FechaVisita`** (se
  puede reciclar en otras fechas — mismo criterio que `CodigoSalida`, solo
  que ahí el ámbito es "mismo día" en vez de "misma FechaVisita"). Como el
  mismo código puede repetirse en fechas distintas, `sp_CV_Visitas_ValidarAcceso`
  busca primero la fila de **hoy**; si no existe, toma cualquier otra fila
  con ese código solo para poder informar "tu visita es para el [fecha]"
  (`FECHA_NO_COINCIDE`) — nunca otorga acceso con una fila que no sea de hoy.
  El campo `UUID` de `CV_Visitas` ya no se usa para el acceso, queda solo
  como identificador interno.
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
  `fechaVisita` registrada** — si al ingresar el código de acceso la fecha de
  hoy no coincide, se rechaza el acceso con mensaje al usuario en vez de
  dejarlo pasar a validación (`FECHA_NO_COINCIDE`, ver arriba).
- **Login solo con contraseña, validado contra WishPOS** (`system_LOGIN` de
  `celexpos.celex.com`) — no se pide usuario. ⚠️ El equipo de negocio
  describió el hash como "MD5", pero al verificarlo contra el ejemplo real
  que dieron (`203` → hash de 128 caracteres), es **SHA-512**, no MD5 (que da
  32 caracteres). Ver `api/Servicios/WishPosAuthService.cs`. Esa llamada la
  hace la API, nunca el navegador (evita CORS contra un dominio externo y
  evita que el cliente construya la URL con el hash de la contraseña).
  `Error_Codigo: 0` en la respuesta = éxito; cualquier otro valor = acceso
  denegado, con `Error_Mensaje` como texto a mostrar. El menú/permisos
  (`Accesos`, `MiEspacio`) que regresa WishPOS no se usa aquí, solo `Usuario`
  y `Nombre`.
- **El kiosko/caseta ya NO tiene su propio login** — "Entrar al kiosko" va
  directo a `screen-kiosk-home` reutilizando la sesión del empleado que ya
  inició sesión en el módulo. Se quitó `screen-kiosk-login` y
  `doKioskLogin()`/`doKioskLogout()` por completo (existieron brevemente
  cuando el login de caseta era independiente). Como contraparte, el botón
  **"‹ Salir del kiosko" ahora hace `doLogout()`** (cierra sesión del sistema
  por completo, no solo regresa al menú) — al no haber un login propio del
  kiosko que separe "sesión de caseta" de "sesión de empleado", salir del
  kiosko debe cerrar la sesión para no dejar la cuenta del empleado abierta
  en el equipo de la caseta.
- El teclado en pantalla (QWERTY, arrastrable/redimensionable) solo debe
  aparecer en las pantallas del lado de **caseta/kiosko** que tengan un campo
  de texto real. Hoy esa es únicamente **validación** (apellido paterno) —
  ninguna otra pantalla de caseta (home, foto, etiqueta de acceso, código de
  acceso/salida, confirmar/registrar salida, salida registrada) tiene un
  `<input>` de texto al que el teclado QWERTY pueda escribirle; las de
  código usan su propio PIN pad numérico compartido (ver `pinModo` en el
  JS). Nunca debe aparecer en las pantallas de empleado, que sí tienen
  teclado/mouse reales. Ver el arreglo `kioskScreens` en `showScreen()`.
- Estilo visual: se sigue el look de WishPOS existente (topbar azul con degradado,
  sidebar gris-azulado con íconos, tarjetas con círculo morado, ola teal al
  fondo) — no se debe rediseñar sin que el usuario lo pida explícitamente.

## Convenciones SQL (mismo patrón que el resto del stack de Celex)

- Prefijo de tablas/SPs de este módulo: `CV_` (Control de Visitas), para no
  mezclarse con las tablas `Yoda_*` del bot de sincronización WishPoS↔Telcel.
- Columna `UUID` (uniqueidentifier, default `NEWID()`) en tablas que necesitan
  un identificador externo/público (igual que en `Yoda_Cat_Ladas`). En
  `CV_Visitas` ya no se usa para el acceso (ver `CodigoAcceso`), solo queda
  como identificador interno.
  el patrón `ID_Fecha_Modificacion` (default `'1900-01-01 00:00:00'`) se usa
  para auditoría de cambios, igual que en el resto de las tablas de Celex.
- INSERTs de catálogos siguen el patrón `SELECT` sin `FROM` cuando aplica.
- Comparación de apellidos: quitar acentos + mayúsculas antes de comparar
  (mismo criterio que la normalización de direcciones ya existente — si ya
  hay una función para esto, reutilizarla en vez de `fn_CV_QuitarAcentos`).
- **Ninguna columna acepta NULL.** Todas son `NOT NULL` con un valor "vacío"
  según su tipo: `''` para texto/`CHAR`, `0` para numéricos,
  `'1900-01-01 00:00:00'` para fechas (mismo centinela de siempre en
  `ID_Fecha_Modificacion`). Al agregar una columna nueva, seguir este patrón
  y comparar contra el centinela en los SPs en vez de `IS NULL`/`IS NOT NULL`.
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
   - ✅ Registrar visita (`generarCodigoAcceso`, con áreas cargadas de
     `GET /api/areas`).
   - ✅ Login (`doLogin` / `doKioskLogin` ya llaman a `POST /api/auth/login`;
     ambas pantallas solo piden contraseña).
   - ✅ Validar acceso en kiosko vía código de 6 dígitos (`submitAccesoCodigo`
     + `submitValidate` ya llaman a `POST /api/visitas/validar-acceso` con
     `codigoAcceso`; los 5 resultados posibles —OK, NO_ENCONTRADO,
     YA_UTILIZADO, FECHA_NO_COINCIDE, APELLIDO_NO_COINCIDE— se probaron
     end-to-end desde la página real).
   - ✅ Registro de salida (`submitSalidaCodigo` + `confirmarSalida` ya llaman
     a `GET /api/visitas/salida/{codigo}` y
     `POST /api/visitas/salida/{id}/confirmar`; `pendingSalidaVisitId` ahora
     es el ID numérico de `CV_Visitas`, no el UUID del QR).
   - ✅ Reportes (`generarReporte` llama a `GET /api/reportes`; el CSV
     (`exportarCSV`) ahora exporta exactamente lo último generado en pantalla,
     ya no ignora el rango de fechas como antes).
   - ✅ Mis visitas (`openMisVisitas` llama a `GET /api/visitas/mias`;
     `abrirEditar`/`guardarEdicion` llaman a `PUT /api/visitas/{id}`, con
     nuevo SP `sp_CV_Visitas_Actualizar` que solo permite editar mientras
     `Status = 'Pendiente'` — devuelve `NO_EDITABLE` si ya se accesó, aunque
     alguien intente saltarse el botón deshabilitado del front. `eArea`
     también se corrigió para cargar de `GET /api/areas` en vez de opciones
     fijas sin relación con el `ID_Area` real, igual que se hizo antes en
     `fArea`).
6. ✅ Foto guardada en disco (`POST /api/visitas/{id}/foto`, `FotoService.cs`)
   con ruta configurable desde la nueva pantalla de Configuración (ver
   "Estado actual" arriba).
7. ✅ Correo de confirmación al visitante encolado en `WM_Correo` desde
   `sp_CV_Visitas_Registrar` (ver "Estado actual" arriba) — lo envía el
   SQL Server Agent Job que ya opera en producción, sin Graph API.
8. Seguir `docs/checklist-modo-kiosco.md` para el despliegue en la caseta.

## Idioma y tono

Todo el copy de la interfaz, comentarios de código y commits deben ir en
español (México), consistente con el resto del proyecto.
