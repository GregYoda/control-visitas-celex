# Bitácora de cambios — Control de Visitas (Celex)

Registro de los cambios del sistema, del más reciente al más antiguo. Se
actualiza en cada commit/push. Cada entrada indica al final, entre paréntesis,
quién solicitó el cambio.

---

## 2026-07-23
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
