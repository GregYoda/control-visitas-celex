# Bitácora de cambios — Control de Visitas (Celex)

Registro de los cambios del sistema, del más reciente al más antiguo. Se
actualiza en cada commit/push.

---

## 2026-07-23
- **Empresa opcional**: el campo Empresa ya no es obligatorio al registrar o editar una visita.
- **Visita tipo Entrevista** (para Reclutamiento): en Configuración se define la lista de usuarios reclutadores y los valores por defecto (Empresa, Área, Motivo, Fecha = día siguiente/semana siguiente, Persona a quien visita). A esos usuarios les aparece un check "Visita tipo Entrevista" al registrar que prellena esos campos (editables).
- **Fotos organizadas en carpetas** `RutaFotos/Año/Mes/Tipo/` (ej. `...\2026\07\Entrevista\` o `...\2026\07\Visita\`).
- **Corrección**: el registro devolvía un folio equivocado (el del correo en cola en lugar del de la visita); no afectaba el uso.
- **Demo de capacitación v0.15**: refleja lo anterior; nueva contraseña `4000` = perfil Reclutamiento; el demo muestra su número de versión en el login.

## 2026-07-22
- **Salida hasta 48 h**: el registro de salida se permite hasta 48 horas después del acceso (antes solo el mismo día).
- **Modo terminal de caseta**: usuarios configurados entran directo al kiosko al iniciar sesión; al salir del kiosko se cierra la sesión.
- **Pantalla completa en el kiosko**: al entrar al kiosko el navegador pasa a pantalla completa y se mantiene así (solo el teclado físico la desactiva).
- **Teclado numérico en el login**: botón a la derecha que muestra un teclado numérico para escribir la contraseña en la terminal táctil.
- **Correo (WM_Correo) apunta a la base de WishPOS** mediante un SYNONYM (sin duplicar la tabla).
- **Documentación de despliegue**: guía de instalación SQL vía SSMS (con variante de usuario SQL) y nota sobre usar carpeta de red (UNC) para las fotos.

## 2026-07-21
- **Visitas VIP**: check "Visita VIP" visible solo para usuarios autorizados (configurable); se muestra en la etiqueta de acceso, Mis Visitas y Reportes.
- **Preparación de despliegue en IIS**: el frontend se sirve desde la propia API (mismo origen); guía de despliegue y borrador de correo para TI/DBA.
- **Manual de uso** del sistema (Markdown, PDF y HTML).
- Demo de capacitación con VIP y contraseñas de acceso.

## 2026-07-20
- **Versión demo autónoma** para capacitación (funciona sin API ni base de datos, con datos de ejemplo).
- **Infografía** del sistema en PDF para presentar a usuarios clave.

## 2026-07-19
- Cancelar una visita desde "Mis visitas" (mientras siga pendiente).
- Se quitó el teclado en pantalla de las pantallas donde no aplicaba.

## 2026-07-18
- Las fotos de visitantes se sirven a través de la API (no por ruta de disco), para que se vean en Mis Visitas y Reportes.

## 2026-07-17
- **Foto del visitante** guardada en disco y **pantalla de Configuración** (ruta, prefijo y dígitos del nombre de archivo).
- Campo **Observaciones** para vigilancia en el registro.
- **Correo de confirmación** al visitante encolado en `WM_Correo` (lo envía el proceso existente de SQL Server).
- La pantalla de Configuración se controla con el permiso WishPOS `CV.200.00`.

## 2026-07-16
- **Inicio de sesión real contra WishPOS** (solo contraseña).
- Mis Visitas conectado a la API (listar y editar); se guarda el ID de usuario del login.
- Se reemplazó el **QR por un código de acceso de 6 dígitos** (más confiable en la caseta).
- Esquema de base sin columnas nulas.

## 2026-07-15
- **API en ASP.NET Core** con los endpoints reales; el mockup se conectó a la API (registro, validación de acceso, salida y reportes).
- Se rechaza el acceso si la fecha no coincide con la fecha de visita.

## 2026-07-14
- Versión inicial: mockup de Control de Visitas, modelo de datos SQL y checklist de kiosko.
- Pantalla **Mis visitas** con edición por usuario; **fecha de visita** en registro, reportes y etiqueta.
