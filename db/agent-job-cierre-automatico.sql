/* =============================================================================
   CIERRE AUTOMATICO DE VISITAS -- COMO AGENDARLO
   (Control de Visitas, Celex)

   El SP dbo.sp_CV_Visitas_CierreAutomatico esta pensado para dispararse desde un
   agente que corre CADA MINUTO. El propio SP decide si actua:
     - Solo actua cuando la hora actual (HH:mm) coincide con la configurada en
       CV_Configuracion.HoraCierreAutomatico (editable desde Configuracion).
     - Como maximo UNA VEZ AL DIA (se apoya en CierreAutomaticoUltimaFecha).
     - Al cerrar, encola en WM_Correo un aviso con el total (y la lista) dirigido
       a CV_Configuracion.CorreosCierreAutomatico. Sin destinatarios = sin correo.
   En cualquier otro minuto retorna sin hacer nada, asi que es seguro llamarlo
   cada minuto.

   REQUISITO: aplicar antes la migracion
     db/migraciones/2026-07-28-cierre-automatico-visitas.sql
   (crea la columna, las llaves de config y el SP).

   ---------------------------------------------------------------------------
   OPCION A (recomendada) -- Ya tienes un Job/agente que corre cada minuto:
   agrega un PASO (step) de tipo T-SQL, base ControlVisitas_Celex, con:

       SET QUOTED_IDENTIFIER ON; SET ANSI_NULLS ON;
       EXEC dbo.sp_CV_Visitas_CierreAutomatico;

   (El mismo Job que ya revisa WM_Correo cada minuto sirve; solo agrega el paso.)

   La hora del cierre NO se define aqui: se cambia desde la pantalla de
   Configuracion (campo "Hora del cierre automatico").

   ---------------------------------------------------------------------------
   OPCION B -- Crear un Job dedicado que corra cada minuto (si se prefiere uno
   aparte). Requiere SQL Server Agent (no existe en SQL Express). Idempotente:
   borra el Job si ya existe y lo recrea. Ajustar @owner/@server si aplica.
   ============================================================================= */

USE [msdb];
GO

DECLARE @jobName   SYSNAME = N'CV - Cierre automatico de visitas (cada minuto)';
DECLARE @schedName SYSNAME = N'CV - Cada minuto';
DECLARE @dbName    SYSNAME = N'ControlVisitas_Celex';
DECLARE @owner     SYSNAME = SUSER_SNAME();
DECLARE @server    SYSNAME = CAST(SERVERPROPERTY('ServerName') AS SYSNAME);

IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = @jobName)
    EXEC msdb.dbo.sp_delete_job @job_name = @jobName, @delete_unused_schedule = 1;

DECLARE @jobId BINARY(16);
EXEC msdb.dbo.sp_add_job
     @job_name    = @jobName,
     @enabled     = 1,
     @description = N'Corre cada minuto; el SP cierra las visitas "Dentro" solo a la hora configurada (CV_Configuracion.HoraCierreAutomatico) y una vez al dia.',
     @owner_login_name = @owner,
     @job_id      = @jobId OUTPUT;

EXEC msdb.dbo.sp_add_jobstep
     @job_id       = @jobId,
     @step_name    = N'Ejecutar sp_CV_Visitas_CierreAutomatico',
     @subsystem    = N'TSQL',
     @database_name= @dbName,
     @command      = N'SET QUOTED_IDENTIFIER ON; SET ANSI_NULLS ON; EXEC dbo.sp_CV_Visitas_CierreAutomatico;',
     @on_success_action = 1,
     @on_fail_action    = 2;

/* Horario: cada 1 minuto, todo el dia, todos los dias */
EXEC msdb.dbo.sp_add_schedule
     @schedule_name        = @schedName,
     @enabled              = 1,
     @freq_type            = 4,       -- diario
     @freq_interval        = 1,       -- cada 1 dia
     @freq_subday_type     = 4,       -- cada N minutos
     @freq_subday_interval = 1,       -- 1 minuto
     @active_start_time    = 000000,  -- 00:00:00
     @active_end_time      = 235959;  -- 23:59:59

EXEC msdb.dbo.sp_attach_schedule @job_id = @jobId, @schedule_name = @schedName;
EXEC msdb.dbo.sp_add_jobserver   @job_id = @jobId, @server_name   = @server;
GO

PRINT 'Job "CV - Cierre automatico de visitas (cada minuto)" creado. La hora del cierre se configura en la pantalla Configuracion.';
GO
