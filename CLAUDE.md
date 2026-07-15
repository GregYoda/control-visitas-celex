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
- ⬜ **Pendiente:** capa de API que conecte el frontend a los stored procedures,
  autenticación real contra WishPOS, envío de correo real (Graph API / M365),
  subir la foto capturada a disco/blob en vez de mantenerla solo en memoria.

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

## Estructura del repo

```
control-visitas-celex/
├── web/    → frontend (hoy: mockup HTML autocontenido; mañana: app real conectada a la API)
├── db/     → modelo de datos SQL Server (tablas + stored procedures)
└── docs/   → checklist de despliegue del kiosko y cualquier otra documentación
```

## Siguientes pasos (backlog sugerido)

1. Definir stack de la API (Node/Express o .NET) que exponga los stored
   procedures de `db/cv-modelo-datos.sql` como endpoints REST.
2. Resolver autenticación contra WishPOS (¿hay tabla/API de usuarios expuesta,
   o hay que integrar AD/LDAP?) — este es el punto que más puede mover el
   calendario, ver conversación previa.
3. Reemplazar el estado en memoria de `web/index.html` por llamadas reales a
   la API (login, registrar visita, validar acceso, registrar salida, reporte).
4. Subir la foto capturada a disco/blob storage (hoy vive como data URL en
   memoria) y guardar la ruta en `CV_Visitas.FotoRuta`.
5. Integrar envío de correo real vía Graph API (mismo patrón que Circulares Telcel).
6. Seguir `docs/checklist-modo-kiosco.md` para el despliegue en la caseta.

## Idioma y tono

Todo el copy de la interfaz, comentarios de código y commits deben ir en
español (México), consistente con el resto del proyecto.
