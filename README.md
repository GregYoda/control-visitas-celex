# Control de Visitas — Celex

Sistema de control de acceso de visitantes (registro, código de acceso, foto,
código de salida y reportes) para reemplazar el registro en papel de
recepción/caseta.

## Contenido

- **`web/`** — Mockup funcional (HTML/CSS/JS, sin dependencias de build).
  Ábrelo directo en el navegador para probarlo. El acceso se valida con un
  código de acceso de 6 dígitos (PIN pad), no con QR/cámara.
- **`api/`** — API en ASP.NET Core (net8.0) que expone los stored procedures
  de `db/` como endpoints REST. Corre con `dotnet run` desde `api/`; usa la
  cadena de conexión de `appsettings.Development.json` (SQL Server local).
- **`db/`** — Modelo de datos SQL Server (tablas + stored procedures).
  Revisar con el DBA antes de correr en el servidor real.
- **`docs/`** — Checklist de despliegue en modo kiosco para el equipo de caseta.

## Contexto para Claude Code

Este repo incluye un `CLAUDE.md` con todo el contexto de decisiones de diseño,
convenciones y próximos pasos — Claude Code lo lee automáticamente al abrir
una sesión en esta carpeta.

## Siguiente paso

Ver la sección "Siguientes pasos" en `CLAUDE.md` para el backlog pendiente
(API, autenticación WishPOS, envío de correo, despliegue de caseta).
