/* =============================================================================
   JOB DE SQL SERVER AGENT -- CIERRE AUTOMATICO DE VISITAS 21:00
   (Control de Visitas, Celex)

   Crea (o recrea) un Job que cada dia a las 21:00 ejecuta
   dbo.sp_CV_Visitas_CierreAutomatico en la base ControlVisitas_Celex, el cual
   registra la salida de todas las visitas que quedaron "Dentro".

   REQUISITOS / NOTAS PARA EL DBA:
   - Requiere SQL Server con **SQL Server Agent** en ejecucion (NO funciona en
     SQL Server Express, que no incluye Agent). Es el mismo mecanismo que ya
     usa el Job de envio de correo (WM_Correo).
   - Ejecutar este script UNA vez en el servidor de produccion (idempotente:
     borra el Job si ya existe y lo vuelve a crear).
   - Ajustar @owner y @server_name segun el entorno si difieren.
   - Antes de correr esto, aplicar la migracion
     db/migraciones/2026-07-28-cierre-automatico-visitas.sql (crea la columna y
     el SP que este Job invoca).
   ============================================================================= */

USE [msdb];
GO

DECLARE @jobName   SYSNAME = N'CV - Cierre automatico de visitas 21:00';
DECLARE @schedName SYSNAME = N'CV - Diario 21:00';
DECLARE @dbName    SYSNAME = N'ControlVisitas_Celex';
DECLARE @owner     SYSNAME = SUSER_SNAME();          -- login dueño del Job (ajustar si se requiere una cuenta de servicio)
DECLARE @server    SYSNAME = CAST(SERVERPROPERTY('ServerName') AS SYSNAME);

/* 1) Si el Job ya existe, borrarlo (para poder recrearlo limpio) */
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = @jobName)
    EXEC msdb.dbo.sp_delete_job @job_name = @jobName, @delete_unused_schedule = 1;

/* 2) Crear el Job */
DECLARE @jobId BINARY(16);
EXEC msdb.dbo.sp_add_job
     @job_name    = @jobName,
     @enabled     = 1,
     @description = N'Registra la salida de las visitas que quedaron "Dentro" (accesadas y sin salida). Corre diario a las 21:00.',
     @owner_login_name = @owner,
     @job_id      = @jobId OUTPUT;

/* 3) Paso unico: ejecutar el SP en la base de la aplicacion */
EXEC msdb.dbo.sp_add_jobstep
     @job_id       = @jobId,
     @step_name    = N'Ejecutar sp_CV_Visitas_CierreAutomatico',
     @subsystem    = N'TSQL',
     @database_name= @dbName,
     @command      = N'SET QUOTED_IDENTIFIER ON; SET ANSI_NULLS ON; EXEC dbo.sp_CV_Visitas_CierreAutomatico;',
     @on_success_action = 1,   -- 1 = salir con exito
     @on_fail_action    = 2;   -- 2 = salir con error (queda en el historial)

/* 4) Horario: diario a las 21:00:00 */
EXEC msdb.dbo.sp_add_schedule
     @schedule_name    = @schedName,
     @enabled          = 1,
     @freq_type        = 4,        -- 4 = diario
     @freq_interval    = 1,        -- cada 1 dia
     @active_start_time = 210000;  -- 21:00:00 (formato HHMMSS)

EXEC msdb.dbo.sp_attach_schedule @job_id = @jobId, @schedule_name = @schedName;

/* 5) Registrar el Job en este servidor */
EXEC msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = @server;
GO

PRINT 'Job "CV - Cierre automatico de visitas 21:00" creado. Verificar en SQL Server Agent > Jobs.';
GO
