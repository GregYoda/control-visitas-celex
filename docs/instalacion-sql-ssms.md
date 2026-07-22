# Instalación de la base de datos en producción (SQL Server Management Studio)

Pasos para instalar el modelo de datos de **Control de Visitas** en el
SQL Server productivo usando **SSMS**. Script: `db/cv-modelo-datos.sql`.

> El script crea funciones, tablas (catálogos + transaccionales), índices, la
> configuración, un **SYNONYM** a `WM_Correo` (base de WishPOS) y todos los
> stored procedures. **No** crea la base de datos ni la tabla `WM_Correo`.

---

## 1. Requisitos

- SSMS conectado a la **instancia productiva** con un usuario con permisos
  (sysadmin o db_owner de la base destino).
- **SQL Server 2017 o superior** (el script usa `TRANSLATE`).
- La base de **WishPOS** (donde vive `WM_Correo`) ya existente y accesible en
  la misma instancia.

## 2. Crear la base de datos

El script no la crea. Primero:

```sql
CREATE DATABASE ControlVisitas_Celex;   -- o el nombre del estándar del DBA
GO
```

(o clic derecho en *Databases → New Database…*). Si se usa otro nombre, hay que
ajustar la cadena de conexión de la app (`appsettings.Production.json`).

## 3. ⚠️ Abrir el script con codificación UTF-8 (evita acentos corruptos)

El archivo está en UTF-8 sin BOM; si SSMS lo abre como ANSI, los acentos se
guardan mal (`Almacén` → `AlmacÃ©n`).

- **Archivo → Abrir → Archivo…**
- En el diálogo, junto al botón **Abrir**, clic en la **flecha ▾ → "Abrir con…"**
- Elegir **"Editor de consultas SQL con codificación"** → **Unicode (UTF-8 sin
  firma)** → Aceptar.

## 4. Seleccionar la base correcta

En el desplegable **"Available Databases"** de la barra, elegir
**`ControlVisitas_Celex`** (o agregar `USE ControlVisitas_Celex; GO` al inicio).

## 5. ⚠️ Ajustar el SYNONYM de WM_Correo

Buscar en el script:

```sql
CREATE SYNONYM dbo.WM_Correo FOR WISH.dbo.WM_Correo;
```

Cambiar **`WISH`** por el nombre **real** de la base de WishPOS en producción
si difiere. El script **no** crea la tabla `WM_Correo`; solo el synonym que
apunta a la tabla existente.

## 6. Ejecutar

**F5**. Debe terminar con *"Commands completed successfully"* (verás algunos
`(8 rows affected)` / `(5 rows affected)` de los catálogos).

## 7. Verificaciones post-instalación

```sql
-- Áreas con acentos correctos (si ves "AlmacÃ©n", reabrir con UTF-8 y recorrer)
SELECT * FROM dbo.CV_Areas;

-- Configuración (5 claves)
SELECT * FROM dbo.CV_Configuracion;   -- RutaFotos, PrefijoFoto, DigitosFoto, UsuariosVIP, UsuariosKiosko

-- El synonym apunta a la base correcta
SELECT name, base_object_name FROM sys.synonyms;

-- Prueba de lectura cross-database (no debe dar error)
SELECT TOP 1 * FROM dbo.WM_Correo;

-- Procedimientos creados (deben aparecer los sp_CV_*)
SELECT name FROM sys.procedures ORDER BY name;
```

## 8. Permisos del usuario de la app

El login con que se conecta la API necesita, sobre `ControlVisitas_Celex`:
ejecutar los `sp_CV_*` y CRUD en las tablas `CV_*`; y sobre la base de WishPOS:
**INSERT** en `WM_Correo` (cross-database).

### Opción A — Autenticación de Windows (cuenta del App Pool de IIS)

```sql
USE ControlVisitas_Celex;
CREATE USER [dominio\CuentaAppPool] FOR LOGIN [dominio\CuentaAppPool];
ALTER ROLE db_datareader ADD MEMBER [dominio\CuentaAppPool];
ALTER ROLE db_datawriter ADD MEMBER [dominio\CuentaAppPool];
GRANT EXECUTE TO [dominio\CuentaAppPool];   -- para los SP

USE WISH;   -- la base real de WishPOS
CREATE USER [dominio\CuentaAppPool] FOR LOGIN [dominio\CuentaAppPool];
GRANT INSERT ON dbo.WM_Correo TO [dominio\CuentaAppPool];
```

### Opción B — Usuario/contraseña de SQL (login dedicado)

Requiere que la instancia tenga habilitada la **autenticación mixta** (*Server
Properties → Security → SQL Server and Windows Authentication mode*; si se
cambia, reiniciar el servicio de SQL Server).

```sql
-- 1) LOGIN a nivel de servidor
USE master;
GO
CREATE LOGIN cv_app
    WITH PASSWORD = 'CAMBIA_ESTA_CLAVE_Fuerte!2026',
         CHECK_POLICY = ON;
GO

-- 2) Permisos en la base del sistema
USE ControlVisitas_Celex;
GO
CREATE USER cv_app FOR LOGIN cv_app;
ALTER ROLE db_datareader ADD MEMBER cv_app;   -- SELECT en las tablas CV_*
ALTER ROLE db_datawriter ADD MEMBER cv_app;   -- INSERT/UPDATE/DELETE en CV_*
GRANT EXECUTE TO cv_app;                       -- ejecutar los sp_CV_*
GO

-- 3) Permiso de INSERT en WM_Correo (base de WishPOS)
USE WISH;   -- nombre REAL de la base de WishPOS
GO
CREATE USER cv_app FOR LOGIN cv_app;
GRANT INSERT ON dbo.WM_Correo TO cv_app;
GO
```

Cadena de conexión (`appsettings.Production.json`) para la Opción B:

```
Server=SERVIDOR\INSTANCIA;Database=ControlVisitas_Celex;User Id=cv_app;Password=...;TrustServerCertificate=True;
```

> El paso 3 (INSERT en `WM_Correo`) es necesario en ambas opciones **aunque** el
> insert ocurra dentro de `sp_CV_Visitas_Registrar`: al pasar por el synonym a
> otra base, SQL Server evalúa el permiso como el usuario en la base destino.
> Ajustar `cv_app`, la contraseña y el nombre `WISH` a los reales.

## 9. Confirmar el envío de correo

Verificar que el **Job de SQL Server Agent** que procesa `WM_Correo` (envía los
`Enviar='Si'` / `Enviado='No'`) esté activo — es lo que manda el correo al
visitante con su código de acceso.

---

## Nota: actualizaciones futuras

Este script usa `CREATE PROCEDURE/FUNCTION/TABLE`, así que en una base que **ya
existe** fallará con *"already exists"*. Para la **primera** instalación no hay
problema. Para reinstalar/actualizar hay que borrar los objetos primero o usar
una versión con `CREATE OR ALTER` (procedimientos/funciones) e `IF NOT EXISTS`
(tablas) — pedirla si se necesita despliegue incremental.
