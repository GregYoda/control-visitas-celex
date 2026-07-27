/* =============================================================================
   MIGRACION -- Etiqueta: tipo "Entrevista"  (Control de Visitas, Celex)
   Refresca sp_CV_Visitas_ValidarAcceso para que devuelva EsEntrevista, y asi
   la etiqueta imprimible pueda mostrar "Entrevista" cuando aplique.
   Idempotente (CREATE OR ALTER). Correr con:  sqlcmd -S SERVIDOR -d ControlVisitas_Celex -f i:65001 -i este.sql
   ============================================================================= */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
/* -----------------------------------------------------------------------------
   sp_CV_Visitas_ValidarAcceso
   Paso 2: la caseta recibió el código de acceso de 6 dígitos y el visitante
   tecleó su apellido paterno. Si coincide, marca el acceso y genera el código
   de salida. La foto se guarda después, en un paso aparte
   (sp_CV_Visitas_ActualizarFoto vía POST /api/visitas/{id}/foto).
   Resultado posible: OK | NO_ENCONTRADO | YA_UTILIZADO | CANCELADA |
                      FECHA_NO_COINCIDE | APELLIDO_NO_COINCIDE
   ----------------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.sp_CV_Visitas_ValidarAcceso
    @CodigoAcceso       CHAR(6),
    @ApellidoTecleado   NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @ID BIGINT, @ApellidoReal NVARCHAR(100), @Status NVARCHAR(20), @FechaVisita DATE;

    -- CodigoAcceso solo es único por FechaVisita (se recicla en otras
    -- fechas), así que puede haber más de una fila con el mismo código en
    -- fechas distintas. Se prefiere la fila de HOY si existe; si no, se usa
    -- cualquier otra para poder informar "tu visita es para el [fecha]".
    SELECT TOP (1) @ID = ID, @ApellidoReal = ApellidoPaterno, @Status = Status, @FechaVisita = FechaVisita
    FROM dbo.CV_Visitas
    WHERE CodigoAcceso = @CodigoAcceso
    ORDER BY CASE WHEN FechaVisita = CAST(GETDATE() AS DATE) THEN 0 ELSE 1 END, FechaVisita ASC;

    IF @ID IS NULL
    BEGIN
        SELECT N'NO_ENCONTRADO' AS Resultado;
        RETURN;
    END

    IF @Status = N'Accesado'
    BEGIN
        SELECT N'YA_UTILIZADO' AS Resultado;
        RETURN;
    END

    IF @Status = N'Cancelada'
    BEGIN
        SELECT N'CANCELADA' AS Resultado;
        RETURN;
    END

    -- Una visita solo puede accesarse el día para el que fue registrada.
    IF @FechaVisita <> CAST(GETDATE() AS DATE)
    BEGIN
        SELECT N'FECHA_NO_COINCIDE' AS Resultado, @FechaVisita AS FechaVisita;
        RETURN;
    END

    IF dbo.fn_CV_QuitarAcentos(LTRIM(RTRIM(@ApellidoTecleado))) = dbo.fn_CV_QuitarAcentos(@ApellidoReal)
    BEGIN
        DECLARE @Codigo CHAR(6);

        -- Genera un código de 6 dígitos único entre las visitas que siguen
        -- "dentro" y cuyo código todavía es válido para salir (acceso en las
        -- últimas 48 h). La ventana coincide con la de sp_CV_Visitas_BuscarPorCodigoSalida
        -- para que nunca haya dos visitas activas con el mismo código.
        -- Nota de producción: bajo concurrencia alta convendría envolver esto
        -- en un retry con manejo de violación de índice; para el volumen
        -- típico de una caseta esto es suficiente.
        WHILE 1 = 1
        BEGIN
            SET @Codigo = RIGHT('000000' + CAST(ABS(CHECKSUM(NEWID())) % 1000000 AS VARCHAR(6)), 6);
            IF NOT EXISTS (
                SELECT 1 FROM dbo.CV_Visitas
                WHERE CodigoSalida = @Codigo AND FechaSalida = '1900-01-01'
                  AND FechaAcceso >= DATEADD(HOUR, -48, GETDATE())
            ) BREAK;
        END

        UPDATE dbo.CV_Visitas
           SET Status = N'Accesado',
               FechaAcceso = GETDATE(),
               CodigoSalida = @Codigo,
               ID_Fecha_Modificacion = GETDATE()
         WHERE ID = @ID;

        INSERT INTO dbo.CV_Intentos_Acceso (ID_Visita, ApellidoTecleado, Resultado)
        VALUES (@ID, @ApellidoTecleado, N'Exitoso');

        SELECT N'OK' AS Resultado, v.ID, v.Nombre, v.ApellidoPaterno, v.ApellidoMaterno,
               v.Empresa, v.Motivo, v.Observaciones, v.EsVIP, v.EsEntrevista, v.Anfitrion, a.Nombre AS Area, v.FechaVisita,
               v.CodigoSalida, v.FechaAcceso
        FROM dbo.CV_Visitas v
        JOIN dbo.CV_Areas a ON a.ID = v.ID_Area
        WHERE v.ID = @ID;
    END
    ELSE
    BEGIN
        INSERT INTO dbo.CV_Intentos_Acceso (ID_Visita, ApellidoTecleado, Resultado)
        VALUES (@ID, @ApellidoTecleado, N'Fallido');

        SELECT N'APELLIDO_NO_COINCIDE' AS Resultado;
    END
END
GO
