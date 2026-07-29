# Bitácora de cambios — Control de Visitas (Celex)

Registro de los cambios del sistema, del más reciente al más antiguo. Se
actualiza en cada commit/push. Cada entrada indica al final, entre paréntesis,
quién solicitó el cambio.

---

## 2026-07-29
- **Validación de campos con FluentValidation (v0.27)**: se agregó una capa de validación por campo en la API (registrar y editar visita), como fuente única de verdad de las reglas. Cada regla vive en un validador (`api/Validaciones/*Validator.cs`), es fácil de mantener/ampliar y devuelve un **400 con mensaje por campo en español** (ej. correo con formato inválido, largos máximos, área requerida, y datos de vehículo obligatorios solo si trae auto). Un filtro (`FluentValidationFilter`) ejecuta el validador automáticamente antes de cada acción. El frontend (app y demo) ahora **muestra el mensaje puntual** que devuelve la API y valida el correo también del lado del cliente para UX inmediata. Verificado por HTTP (correo inválido y vehículo incompleto → 400 con el campo; válido → 200) y en navegador. (G. Ramírez)

## 2026-07-28
- **Cierre automático de visitas "Dentro" (v0.26)**: proceso que registra la salida de todas las visitas que quedaron accesadas y sin salida (incluye rezagadas de días anteriores). El SP `sp_CV_Visitas_CierreAutomatico` pone `FechaSalida` con la hora real de ejecución y marca la nueva columna `CV_Visitas.CierreAutomatico=1` para distinguirlas de una salida registrada por el visitante (en Reportes/Mis Visitas se muestran como **"Cierre automático"**). Además:
  - **Envía un correo** con el total de visitas cerradas (y la lista de quiénes) a los destinatarios configurados; se encola en `WM_Correo` (lo manda el Job existente).
  - En **Configuración** se agregaron dos campos: **Hora del cierre automático** y **Correos para el aviso** (varios separados por `;`; vacío = no envía).
  - Está pensado para **un agente que corre cada minuto**: el SP solo actúa cuando la hora actual coincide con la configurada y **una sola vez al día** (control interno `CierreAutomaticoUltimaFecha`); en cualquier otro minuto no hace nada. Tiene `@Forzar=1` para ejecución manual. Basta con agregar `EXEC dbo.sp_CV_Visitas_CierreAutomatico;` como paso al agente que ya revisa `WM_Correo` cada minuto (ver `db/agent-job-cierre-automatico.sql`).
  Migración `db/migraciones/2026-07-28-cierre-automatico-visitas.sql` (columna + llaves de config + SP). Aplicado en la app y en el demo. Verificado por SQL (cierra, marca, idempotente, respeta la hora, encola el correo con el conteo) y en el navegador (campos de Configuración cargan y guardan). (G. Ramírez)
- **Hora de visita, códigos en Mis Visitas, reenviar correo, área en el correo y retroalimentación visual (v0.25)**: cinco mejoras al flujo de visitas:
  1. **Hora de visita**: nuevo campo de hora (junto a la fecha) al registrar y editar; es informativa (no restringe el acceso, que sigue permitido todo el día) y se muestra en Mis Visitas, Reportes (y su CSV) y en el correo. Se agregó la columna `CV_Visitas.HoraVisita` (NULL en visitas previas).
  2. **Códigos en Mis Visitas**: la tabla ahora muestra el **Código de ingreso** y el **Código de salida** (este último aparece cuando el visitante ya ingresó).
  3. **Reenviar correo desde la edición**: botón "✉️ Enviar correo con los cambios" que se habilita al guardar; reenvía al visitante el correo de confirmación con los datos actualizados (nuevo endpoint `POST /api/visitas/{id}/reenviar-correo` y SP; el HTML del correo se unificó en un SP compartido `sp_CV_Visitas_EncolarCorreo`).
  4. **Retroalimentación visual**: mensajes flotantes (toast) de éxito/error y estado "procesando" (spinner) en todas las acciones que escriben datos (registrar, guardar, cancelar, reenviar, validar acceso, registrar salida y asistencia).
  5. **Área en el correo**: el correo ahora indica, además de la persona que se visita, el **área que visita**.
  Migración idempotente `db/migraciones/2026-07-28-hora-area-correo-codigos.sql`. Aplicado en la app y en el demo de capacitación. Verificado por SQL, por HTTP y en el navegador. (G. Ramírez)
- **Kiosko adaptado a pantallas de poco alto / touch 15" 1366×768 (v0.24)**: las pantallas del kiosko (Kiosko de accesos, Ingresa tu código de acceso, Registrar salida, Ingresa tu código de asistencia y sus subpantallas —validar, foto, panel del empleado) ahora **caben completas sin scroll ni cortar botones** en monitores de poco alto. Antes se desbordaban verticalmente (hasta ~895px de contenido contra 768 disponibles), dejando fuera el botón Cancelar. Se agregó un `@media (max-height: 820px)` que compacta espaciados, título, teclas del pad y el recuadro de la cámara **solo cuando el alto lo requiere**; en monitores grandes el kiosko conserva su tamaño cómodo. Verificado a 1366×768 (las 6 pantallas caben) y a 1920×1080 (sin cambios). Aplicado en app y demo. (G. Ramírez)
- **Corrección: no se podía guardar la edición de una visita en producción (405)**: bajo IIS, el módulo WebDAV interceptaba el verbo `PUT` (el que usa "guardar cambios" de una visita) y devolvía "405 Method Not Allowed" antes de llegar a la API; por eso fallaba solo la edición y no cancelar/registrar (que usan `POST`). En desarrollo con Kestrel no ocurría. Se agregó `api/web.config` base que desactiva WebDAV (`<remove name="WebDAVModule">` / `<remove name="WebDAV">`); al publicar, el SDK conserva esa exclusión e inyecta el handler `aspNetCore`. Tras desplegar (o aplicar el mismo cambio al `web.config` del servidor y `iisreset`), la edición vuelve a guardar. (G. Ramírez)
- **Correo de confirmación con imagen Celular Express (v0.23)**: el correo con el código de acceso se rediseñó con el formato institucional (encabezado con los logos de Celular Express y Distribuidor Autorizado Telcel, azul Telcel #002f87, código de acceso destacado en un recuadro y pie con soporte a `sistemas@celex.com`). Los textos se adaptan según el tipo: en **Visita** el asunto es "Confirmación de tu visita a Celex", dice "el día de su visita" y muestra Empresa y Vehículo cuando aplican; en **Entrevista** el asunto es "Confirmación de tu entrevista en Celex", dice "el día de su cita" y omite Empresa/Vehículo. Se agregó la migración `db/migraciones/2026-07-28-correo-visita-formato.sql` (refresca `sp_CV_Visitas_Registrar`, idempotente). Verificado renderizando ambos correos. (G. Ramírez)
- **Notas para el administrador en Configuración (v0.23)**: se agregó al final de la pantalla de Configuración una sección de referencia (no editable) que recuerda cómo funciona el acceso y detalles que rara vez cambian: permiso CV.200.00 para ver Configuración/Empleados, listas de usuarios (VIP / kiosko / reclutadores) y qué habilitan, que los cambios aplican al próximo login, los tres tipos de código, carga de empleados, fotos/correo y la impresión en kiosko. (G. Ramírez)
- **Logo Celex a color en la barra superior y como ícono de la pestaña (v0.23)**: el círculo con la "C" junto a "CELEX" (arriba a la izquierda) se reemplazó por el logo real de Celex a color, en todas las pantallas; y el mismo logo quedó como **favicon** (ícono de la pestaña del navegador). Nota: el ícono "ⓘ" de la barra de direcciones es del navegador (estado de seguridad del sitio) y no lo controla la página; en producción con HTTPS se muestra como candado. (G. Ramírez)
- **Diseño adaptable a móvil y escritorio (v0.23)**: la interfaz ahora se adapta al dispositivo. En pantallas chicas el formulario de registro pasa a una columna, los filtros de reportes se apilan a lo ancho, las tablas anchas hacen scroll horizontal dentro de su recuadro (sin romper la página), las tarjetas ocupan todo el ancho y se ajustan encabezados y márgenes. Verificado en móvil (390px) y escritorio, en app y demo. (G. Ramírez)
- **Home independiente (v0.22)**: tras iniciar sesión ahora se llega **directo a Control de Visitas**, con un encabezado limpio y bienvenida. Se quitó la pantalla intermedia estilo WishPOS (menú lateral y "Volver al menú"), pensada para cuando iba embebido. Aplicado en producción y en el demo de capacitación. (G. Ramírez)

## 2026-07-27
- **Demo de capacitación alineado a v0.21**: el demo autónomo ya incluye la etiqueta imprimible 3.5"×1.5" (con logo, código de salida, nombre y "Visita a:") y el tipo "Entrevista" cuando aplica; imprime en una sola página. Código de prueba de entrevista en la caseta: 555000. (G. Ramírez)
- **Etiqueta: tipo "Entrevista" (v0.21)**: la etiqueta ahora muestra "Entrevista" cuando la visita fue marcada como entrevista (y "Visita" en los demás casos). Se expuso `EsEntrevista` en la validación de acceso (SP, API y front). (G. Ramírez)
- **Etiqueta de acceso imprimible 3.5" × 1.5" (v0.20)**: el botón "Imprimir etiqueta" del kiosko ahora imprime una etiqueta del tamaño físico de la impresora térmica (3.5×1.5 pulgadas), en blanco y negro, con el logo Celex (emblema redondo) embebido, el código de salida grande, el tipo (Visita), la fecha/hora de acceso, el nombre del visitante y a quién visita (anfitrión · área). (G. Ramírez)
- **Manual de uso e infografía actualizados con imágenes**: el manual (`docs/manual-de-uso.*`) ahora cubre el módulo de asistencia (kiosko agrupado, registro de personal, reporte de asistencia y administración de empleados) e incluye capturas reales del sistema en cada sección. Se creó también una infografía de una hoja (`docs/infografia-control-visitas.*`) que resume los dos flujos —visitantes y asistencia— con imágenes. Ambos en HTML y PDF. (G. Ramírez)

## 2026-07-24
- **Script de migración de asistencia** (`db/migraciones/2026-07-24-asistencia.sql`): agrega a una base ya instalada las tablas y procedimientos del módulo de asistencia (empleados/mensajeros) de forma idempotente (crea lo que falte y refresca los SP; no inserta empleados de ejemplo). Probado en base limpia y sobre la base ya instalada, corriéndolo dos veces sin daño. (G. Ramírez)
- **Código de asistencia de 6 dígitos generado por el sistema (v0.19)**: el código del empleado ahora lo genera el sistema automáticamente (6 dígitos, aleatorio y único), ya no lo captura quien da de alta; al crear un empleado se muestra su código para comunicárselo, y el pad del kiosko pasó a 6 dígitos. Para cargar personal desde otro sistema se agregaron dos procedimientos en la base: `sp_CV_Empleados_Alta` (alta de uno, devuelve el código) y `sp_CV_Empleados_GenerarCodigosFaltantes` (inserta muchos con el código en blanco y luego los genera de golpe). (G. Ramírez)
- **Asistencia en el demo de capacitación (v0.18)**: el demo autónomo ya incluye todo el flujo de asistencia (kiosko con registro de entrada/comida/salida, reporte y administración de empleados) con datos de ejemplo, sin necesidad de API ni base de datos. El demo queda alineado con producción en v0.18. (G. Ramírez)
- **Administración de empleados (v0.18)**: nueva pantalla para dar de alta, editar y activar/inactivar al personal del padrón de asistencia (nombre, número de empleado, número de WishPOS, tipo y código de 4 dígitos), con validación de código duplicado. Disponible para los mismos usuarios que ven Configuración. Además, las respuestas de la API ya no se cachean en el navegador (evita ver datos viejos justo después de un cambio). Probado end-to-end. (G. Ramírez)
- **Reporte de asistencia (v0.17)**: nueva tarjeta en Control de Visitas que lista las marcas del personal por rango de fechas (entrada, salida a comer, regreso y salida) con exportación a CSV. Probado end-to-end. (G. Ramírez)
- **Registro de asistencia en el sistema real (v0.16)**: el kiosko ya integra el registro de asistencia contra la base y la API. Los botones del kiosko quedaron agrupados en Visitantes / Personal Celex para no confundir. Empleados: entrada con foto y luego salida a comer, regreso y salida (en orden, con salida anticipada); mensajeros: solo entrada. Probado end-to-end contra la API local. (G. Ramírez)
- **API de asistencia**: endpoints para buscar empleado por código, registrar movimiento (con validación de secuencia y guardado de la foto de entrada), reporte por rango de fechas, y listar/guardar empleados del padrón. Probado end-to-end contra la base local. (G. Ramírez)
- **Registro de asistencia de empleados (mockup)**: nuevo mockup funcional del kiosko con "Registro asistencia", separado visualmente de los botones de visitante (bloques Visitantes / Personal Celex). Flujo: código personal en pad numérico → validación contra el padrón de empleados → entrada con foto → panel de movimientos del empleado (comida y salida). Cámara emulada en el mockup. (G. Ramírez)
- **Base de datos de asistencia**: tablas `CV_Empleados` (padrón con número de empleado, número de WishPOS, tipo Empleado/Mensajero y código único) y `CV_Asistencia` (una fila por empleado por día con entrada, salida a comer, regreso y salida, más la foto de entrada), con sus stored procedures. Los mensajeros solo registran entrada; los empleados marcan la comida y la salida en orden, con salida anticipada permitida. Probado end-to-end contra la base local. (G. Ramírez)

## 2026-07-23
- **Número de versión en el sistema productivo**: el login de `web/index.html` muestra la versión ("Control de Visitas · v0.15") en el topbar, igual que la demo de capacitación; se sube en cada cambio. (G. Ramírez)
- **Script de migración de base de datos** (`db/migraciones/2026-07-23-migracion-acumulada.sql`): actualiza una base ya instalada a la versión actual sin recrearla (idempotente); agrega columnas/config/SYNONYM faltantes y refresca funciones y SPs. Probado sobre un baseline simulado y corriéndolo dos veces. (G. Ramírez)
- **Empresa opcional**: el campo Empresa ya no es obligatorio al registrar o editar una visita. (G. Ramírez)
- **Visita tipo Entrevista** (para Reclutamiento): en Configuración se define la lista de usuarios reclutadores y los valores por defecto (Empresa, Área, Motivo, Fecha = día siguiente/semana siguiente, Persona a quien visita). A esos usuarios les aparece un check "Visita tipo Entrevista" al registrar que prellena esos campos (editables). (G. Ramírez)
- **Fotos organizadas en carpetas** `RutaFotos/Año/Mes/Tipo/` (ej. `...\2026\07\Entrevista\` o `...\2026\07\Visita\`). (G. Ramírez)
- **Corrección**: el registro devolvía un folio equivocado (el del correo en cola en lugar del de la visita); no afectaba el uso. (G. Ramírez)
- **Demo de capacitación v0.15**: refleja lo anterior; nueva contraseña `4000` = perfil Reclutamiento; el demo muestra su número de versión en el login. (G. Ramírez)

## 2026-07-22
- **Salida hasta 48 h**: el registro de salida se permite hasta 48 horas después del acceso (antes solo el mismo día). (G. Ramírez)
- **Modo terminal de caseta**: usuarios configurados entran directo al kiosko al iniciar sesión; al salir del kiosko se cierra la sesión. (G. Ramírez)
- **Pantalla completa en el kiosko**: al entrar al kiosko el navegador pasa a pantalla completa y se mantiene así (solo el teclado físico la desactiva). (G. Ramírez)
- **Teclado numérico en el login**: botón a la derecha que muestra un teclado numérico para escribir la contraseña en la terminal táctil. (G. Ramírez)
- **Correo (WM_Correo) apunta a la base de WishPOS** mediante un SYNONYM (sin duplicar la tabla). (G. Ramírez)
- **Documentación de despliegue**: guía de instalación SQL vía SSMS (con variante de usuario SQL) y nota sobre usar carpeta de red (UNC) para las fotos. (G. Ramírez)

## 2026-07-21
- **Visitas VIP**: check "Visita VIP" visible solo para usuarios autorizados (configurable); se muestra en la etiqueta de acceso, Mis Visitas y Reportes. (G. Ramírez)
- **Preparación de despliegue en IIS**: el frontend se sirve desde la propia API (mismo origen); guía de despliegue y borrador de correo para TI/DBA. (G. Ramírez)
- **Manual de uso** del sistema (Markdown, PDF y HTML). (G. Ramírez)
- Demo de capacitación con VIP y contraseñas de acceso. (G. Ramírez)

## 2026-07-20
- **Versión demo autónoma** para capacitación (funciona sin API ni base de datos, con datos de ejemplo). (G. Ramírez)
- **Infografía** del sistema en PDF para presentar a usuarios clave. (G. Ramírez)

## 2026-07-19
- Cancelar una visita desde "Mis visitas" (mientras siga pendiente). (G. Ramírez)
- Se quitó el teclado en pantalla de las pantallas donde no aplicaba. (G. Ramírez)

## 2026-07-18
- Las fotos de visitantes se sirven a través de la API (no por ruta de disco), para que se vean en Mis Visitas y Reportes. (G. Ramírez)

## 2026-07-17
- **Foto del visitante** guardada en disco y **pantalla de Configuración** (ruta, prefijo y dígitos del nombre de archivo). (G. Ramírez)
- Campo **Observaciones** para vigilancia en el registro. (G. Ramírez)
- **Correo de confirmación** al visitante encolado en `WM_Correo` (lo envía el proceso existente de SQL Server). (G. Ramírez)
- La pantalla de Configuración se controla con el permiso WishPOS `CV.200.00`. (G. Ramírez)

## 2026-07-16
- **Inicio de sesión real contra WishPOS** (solo contraseña). (G. Ramírez)
- Mis Visitas conectado a la API (listar y editar); se guarda el ID de usuario del login. (G. Ramírez)
- Se reemplazó el **QR por un código de acceso de 6 dígitos** (más confiable en la caseta). (G. Ramírez)
- Esquema de base sin columnas nulas. (G. Ramírez)

## 2026-07-15
- **API en ASP.NET Core** con los endpoints reales; el mockup se conectó a la API (registro, validación de acceso, salida y reportes). (G. Ramírez)
- Se rechaza el acceso si la fecha no coincide con la fecha de visita. (G. Ramírez)

## 2026-07-14
- Versión inicial: mockup de Control de Visitas, modelo de datos SQL y checklist de kiosko. (G. Ramírez)
- Pantalla **Mis visitas** con edición por usuario; **fecha de visita** en registro, reportes y etiqueta. (G. Ramírez)
