/* =============================================================================
   MIGRACION -- CIERRE AUTOMATICO DE VISITAS 'DENTRO' (Control de Visitas, Celex)
   - Agrega CV_Visitas.CierreAutomatico (BIT) para marcar las salidas que puso
     el cierre nocturno (no el visitante en caseta).
   - Agrega sp_CV_Visitas_CierreAutomatico: registra la salida de TODAS las
     visitas 'Dentro' (accesadas y sin salida) con la hora de ejecucion.
   - Refresca Reporte y MisVisitas para mostrar el estado 'Cierre automatico'.
   Idempotente: CREATE OR ALTER y la columna se agrega solo si falta.
   El agendado (Job de SQL Server Agent 21:00) se crea aparte:
     db/agent-job-cierre-automatico.sql
   >>> Correr con codepage UTF-8:
       sqlcmd -S SERVIDOR -d ControlVisitas_Celex -f i:65001 -i este-archivo.sql
   ============================================================================= */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* 1) Columna CierreAutomatico ------------------------------------------------ */
IF COL_LENGTH(N'dbo.CV_Visitas','CierreAutomatico') IS NULL
    ALTER TABLE dbo.CV_Visitas ADD CierreAutomatico BIT NOT NULL CONSTRAINT DF_CV_Visitas_CierreAutomatico DEFAULT (0);
GO

/* 2) Llaves de configuracion del cierre automatico (insertar si faltan) ------ */
IF NOT EXISTS (SELECT 1 FROM dbo.CV_Configuracion WHERE Clave = N'HoraCierreAutomatico')
    INSERT INTO dbo.CV_Configuracion (Clave, Valor) VALUES (N'HoraCierreAutomatico', N'21:00');
IF NOT EXISTS (SELECT 1 FROM dbo.CV_Configuracion WHERE Clave = N'CorreosCierreAutomatico')
    INSERT INTO dbo.CV_Configuracion (Clave, Valor) VALUES (N'CorreosCierreAutomatico', N'');
IF NOT EXISTS (SELECT 1 FROM dbo.CV_Configuracion WHERE Clave = N'CierreAutomaticoUltimaFecha')
    INSERT INTO dbo.CV_Configuracion (Clave, Valor) VALUES (N'CierreAutomaticoUltimaFecha', N'1900-01-01');
GO

/* -----------------------------------------------------------------------------
   sp_CV_Visitas_CierreAutomatico
   Cierre nocturno de visitas que quedaron "Dentro" (accesadas y sin salida),
   incluyendo rezagadas de días anteriores. Marca CierreAutomatico = 1 para
   distinguirlas de una salida registrada por el visitante en la caseta.

   Diseñado para dispararse desde un agente que corre CADA MINUTO: solo ACTÚA
   cuando la hora actual (HH:mm) coincide con CV_Configuracion.HoraCierreAutomatico,
   y como máximo UNA VEZ AL DÍA (se apoya en CierreAutomaticoUltimaFecha). En
   cualquier otro minuto retorna sin hacer nada.

   Al ejecutar, además encola en WM_Correo un aviso con cuántas visitas cerró
   (y la lista) dirigido a CV_Configuracion.CorreosCierreAutomatico (separados
   por ; o ,). Si no hay destinatarios configurados, no envía correo.

   @Forzar = 1 omite las validaciones de hora y de "una vez al día" (para
   ejecutar el cierre manualmente / pruebas). Devuelve cuántas cerró.
   ----------------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.sp_CV_Visitas_CierreAutomatico
    @Forzar BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @HoraCfg   NVARCHAR(10)  = (SELECT Valor FROM dbo.CV_Configuracion WHERE Clave = N'HoraCierreAutomatico');
    DECLARE @Correos   NVARCHAR(500) = (SELECT Valor FROM dbo.CV_Configuracion WHERE Clave = N'CorreosCierreAutomatico');
    DECLARE @UltFecha  NVARCHAR(20)  = (SELECT Valor FROM dbo.CV_Configuracion WHERE Clave = N'CierreAutomaticoUltimaFecha');
    DECLARE @AhoraHHMM NVARCHAR(5)   = FORMAT(GETDATE(), 'HH:mm');
    DECLARE @HoyISO    NVARCHAR(10)  = CONVERT(NVARCHAR(10), CAST(GETDATE() AS DATE), 23);  -- yyyy-MM-dd

    SET @HoraCfg = ISNULL(NULLIF(LTRIM(RTRIM(@HoraCfg)), N''), N'21:00');

    -- Si no se fuerza: actuar solo en el minuto configurado y una vez por día.
    IF @Forzar = 0
    BEGIN
        IF @AhoraHHMM <> LEFT(@HoraCfg, 5) RETURN;          -- no es la hora: salir silencioso
        IF ISNULL(@UltFecha, N'') = @HoyISO RETURN;         -- ya se ejecutó hoy
    END

    -- Cerrar todas las visitas "Dentro" y capturar cuáles se cerraron.
    -- (OUTPUT no admite subconsultas, así que se guarda ID_Area y se une a
    --  CV_Areas al armar el correo.)
    DECLARE @Cerradas TABLE (ID BIGINT, Nombre NVARCHAR(320), ID_Area INT, FechaAcceso DATETIME);

    UPDATE v
       SET v.FechaSalida = GETDATE(),
           v.CierreAutomatico = 1,
           v.ID_Fecha_Modificacion = GETDATE()
    OUTPUT inserted.ID,
           inserted.Nombre + N' ' + inserted.ApellidoPaterno + N' ' + inserted.ApellidoMaterno,
           inserted.ID_Area,
           inserted.FechaAcceso
      INTO @Cerradas
      FROM dbo.CV_Visitas v
     WHERE v.Status = N'Accesado' AND v.FechaSalida = '1900-01-01';

    DECLARE @N INT = (SELECT COUNT(*) FROM @Cerradas);

    -- Registrar que ya corrió hoy (para el modo agente cada minuto).
    UPDATE dbo.CV_Configuracion SET Valor = @HoyISO, ID_Fecha_Modificacion = GETDATE()
     WHERE Clave = N'CierreAutomaticoUltimaFecha';
    IF @@ROWCOUNT = 0
        INSERT INTO dbo.CV_Configuracion (Clave, Valor, ID_Fecha_Modificacion)
        VALUES (N'CierreAutomaticoUltimaFecha', @HoyISO, GETDATE());

    -- Aviso por correo (si hay destinatarios). dbo.WM_Correo lo envía el Job
    -- existente; los destinatarios van separados por ; (se normaliza , -> ;).
    SET @Correos = REPLACE(ISNULL(@Correos, N''), N',', N';');
    IF LTRIM(RTRIM(@Correos)) <> N''
    BEGIN
        DECLARE @Filas NVARCHAR(MAX) = N'';
        SELECT @Filas = @Filas +
            N'<tr><td style="padding:4px 12px 4px 0;">' + dbo.fn_CV_EscaparHtml(c.Nombre) + N'</td>' +
            N'<td style="padding:4px 12px 4px 0;">' + dbo.fn_CV_EscaparHtml(ISNULL(a.Nombre, N'')) + N'</td>' +
            N'<td style="padding:4px 0;">' + FORMAT(c.FechaAcceso, 'dd/MM/yyyy HH:mm') + N'</td></tr>'
        FROM @Cerradas c
        LEFT JOIN dbo.CV_Areas a ON a.ID = c.ID_Area;

        DECLARE @Tabla NVARCHAR(MAX) = CASE WHEN @N = 0 THEN N''
            ELSE N'<table style="border-collapse:collapse;font-size:14px;margin-top:10px;">' +
                 N'<tr style="color:#555555;text-align:left;"><th style="padding:4px 12px 4px 0;">Visitante</th><th style="padding:4px 12px 4px 0;">Área</th><th style="padding:4px 0;">Acceso</th></tr>' +
                 @Filas + N'</table>' END;

        DECLARE @HTML NVARCHAR(MAX) =
            N'<div style="font-family:Helvetica,Arial,sans-serif;color:#333333;font-size:15px;line-height:1.5;">' +
            N'<p style="font-weight:700;color:#002f87;">Cierre automático de visitas — Celex</p>' +
            N'<p>El ' + FORMAT(GETDATE(), 'dd/MM/yyyy') + N' a las ' + FORMAT(GETDATE(), 'HH:mm') +
            N' se cerraron <b>' + CAST(@N AS NVARCHAR(10)) + N'</b> visita(s) que quedaron <b>Dentro</b> (sin registrar salida).</p>' +
            @Tabla +
            N'<p style="color:#888888;font-size:12px;margin-top:16px;">Mensaje automático del sistema Control de Visitas.</p></div>';

        INSERT INTO dbo.WM_Correo
            (Asunto, Correos, Enviado, EnviadoFechaHr, Enviar, HTML, Usuario_ID, ID_UUID, IDFecha, TipoDocumento)
        VALUES
            (N'Cierre automático de visitas (' + CAST(@N AS NVARCHAR(10)) + N') — Celex',
             @Correos, 'No', '1900-01-01 00:00:00', 'Si', @HTML, 0,
             CAST(NEWID() AS VARCHAR(128)), GETDATE(), 'CierreAutomatico');
    END

    SELECT @N AS Cerradas;
END
GO

/* -----------------------------------------------------------------------------
   sp_CV_Visitas_Reporte
   Reporte / bitácora por rango de fechas para los administradores.
   ----------------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.sp_CV_Visitas_Reporte
    @FechaInicio DATE,
    @FechaFin    DATE
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        v.ID, v.Nombre, v.ApellidoPaterno, v.ApellidoMaterno, v.Empresa,
        a.Nombre AS Area, v.Anfitrion, v.Motivo, v.Observaciones, v.EsVIP,
        CASE
            WHEN v.Status = N'Cancelada'       THEN N'Cancelada'
            WHEN v.Status = N'Pendiente'       THEN N'Pendiente'
            WHEN v.FechaSalida = '1900-01-01'  THEN N'Dentro'
            WHEN v.CierreAutomatico = 1        THEN N'Cierre automático'
            ELSE N'Salida registrada'
        END AS Estado,
        v.FechaVisita, v.HoraVisita, v.FechaRegistro, v.FechaAcceso, v.CodigoAcceso, v.CodigoSalida, v.FechaSalida,
        CASE WHEN v.FechaSalida = '1900-01-01' THEN NULL
             ELSE DATEDIFF(MINUTE, v.FechaAcceso, v.FechaSalida) END AS MinutosEstancia,
        v.FotoRuta
    FROM dbo.CV_Visitas v
    JOIN dbo.CV_Areas a ON a.ID = v.ID_Area
    WHERE v.FechaRegistro >= @FechaInicio
      AND v.FechaRegistro <  DATEADD(DAY, 1, @FechaFin)
    ORDER BY v.FechaRegistro DESC;
END
GO

/* -----------------------------------------------------------------------------
   sp_CV_Visitas_MisVisitas
   Pantalla "Mis visitas": lista lo que un usuario de WishPOS registró,
   para poder editarlo mientras siga "Pendiente".
   ----------------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.sp_CV_Visitas_MisVisitas
    @RegistradoPor NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        v.ID, v.UUID, v.Nombre, v.ApellidoPaterno, v.ApellidoMaterno, v.Correo, v.Empresa,
        v.ID_Area, a.Nombre AS Area, v.Motivo, v.Observaciones, v.EsVIP, v.Anfitrion, v.FechaVisita, v.HoraVisita,
        v.TraeAuto, v.Marca, v.Modelo, v.Placas,
        v.CodigoAcceso, v.CodigoSalida,
        CASE
            WHEN v.Status = N'Cancelada'       THEN N'Cancelada'
            WHEN v.Status = N'Pendiente'       THEN N'Pendiente'
            WHEN v.FechaSalida = '1900-01-01'  THEN N'Dentro'
            WHEN v.CierreAutomatico = 1        THEN N'Cierre automático'
            ELSE N'Salida registrada'
        END AS Estado,
        v.Status, v.FechaRegistro, v.FechaAcceso, v.FotoRuta
    FROM dbo.CV_Visitas v
    JOIN dbo.CV_Areas a ON a.ID = v.ID_Area
    WHERE v.RegistradoPor = @RegistradoPor
    ORDER BY v.FechaRegistro DESC;
END
GO

