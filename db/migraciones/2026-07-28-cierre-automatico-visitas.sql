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

/* -----------------------------------------------------------------------------
   sp_CV_Visitas_CierreAutomatico
   Cierre nocturno (lo dispara el Job de SQL Server Agent a las 21:00): registra
   la salida de TODAS las visitas que quedaron "Dentro" (accesadas y sin salida),
   incluyendo rezagadas de días anteriores. Marca CierreAutomatico = 1 para
   distinguirlas de una salida registrada por el visitante en la caseta.
   Es idempotente: al correr de nuevo solo afecta a las que sigan abiertas.
   Devuelve cuántas cerró (queda en el historial del Job).
   ----------------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.sp_CV_Visitas_CierreAutomatico
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.CV_Visitas
       SET FechaSalida = GETDATE(),
           CierreAutomatico = 1,
           ID_Fecha_Modificacion = GETDATE()
     WHERE Status = N'Accesado' AND FechaSalida = '1900-01-01';

    SELECT @@ROWCOUNT AS Cerradas;
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

