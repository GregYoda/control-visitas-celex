/* =============================================================================
   MIGRACION -- HORA DE VISITA + AREA/HORA EN CORREO + CODIGOS EN MIS VISITAS
   (Control de Visitas, Celex)
   - Agrega la columna CV_Visitas.HoraVisita (TIME, informativa; NULL en visitas
     previas a esta version).
   - Extrae el correo de confirmacion a un SP compartido
     (sp_CV_Visitas_EncolarCorreo) que ahora incluye Hora y Area que visita, y
     agrega sp_CV_Visitas_ReenviarCorreo para el boton de la edicion.
   - Refresca Registrar/Actualizar (nuevo parametro @HoraVisita), MisVisitas
     (devuelve HoraVisita, CodigoAcceso y CodigoSalida) y Reporte (HoraVisita).
   Idempotente: usa CREATE OR ALTER y agrega la columna solo si falta.
   >>> Correr con codepage UTF-8:
       sqlcmd -S SERVIDOR -d ControlVisitas_Celex -f i:65001 -i este-archivo.sql
   ============================================================================= */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* 1) Columna HoraVisita ------------------------------------------------------ */
IF COL_LENGTH(N'dbo.CV_Visitas','HoraVisita') IS NULL
    ALTER TABLE dbo.CV_Visitas ADD HoraVisita TIME(0) NULL;
GO

/* -----------------------------------------------------------------------------
   sp_CV_Visitas_EncolarCorreo
   Arma el correo de confirmación (formato Celular Express) para una visita ya
   registrada y lo encola en WM_Correo. Fuente única de verdad del correo: lo
   usan tanto el registro (sp_CV_Visitas_Registrar) como el reenvío desde la
   edición (sp_CV_Visitas_ReenviarCorreo). Los textos cambian según sea Visita
   o Entrevista. No devuelve result set (para no interferir con el SELECT final
   del SP que lo invoca).

   Nota: el HTML se construye en NVARCHAR con literales N'' y se convierte a
   VARCHAR (tipo real de WM_Correo) al insertar; concatenar sin N'' corrompe los
   acentos al pasar por el driver de sqlcmd/ODBC.
   ----------------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.sp_CV_Visitas_EncolarCorreo
    @ID BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Nombre NVARCHAR(100), @ApellidoPaterno NVARCHAR(100), @ApellidoMaterno NVARCHAR(100),
            @Correo NVARCHAR(150), @Empresa NVARCHAR(150), @Motivo NVARCHAR(300), @Anfitrion NVARCHAR(100),
            @Area NVARCHAR(100), @FechaVisita DATE, @HoraVisita TIME(0),
            @TraeAuto BIT, @Marca NVARCHAR(50), @Modelo NVARCHAR(50), @Placas NVARCHAR(20),
            @EsEntrevista BIT, @CodigoAcceso CHAR(6), @UUID UNIQUEIDENTIFIER, @ID_Usuario INT;

    SELECT
        @Nombre = v.Nombre, @ApellidoPaterno = v.ApellidoPaterno, @ApellidoMaterno = v.ApellidoMaterno,
        @Correo = v.Correo, @Empresa = v.Empresa, @Motivo = v.Motivo, @Anfitrion = v.Anfitrion,
        @Area = a.Nombre, @FechaVisita = v.FechaVisita, @HoraVisita = v.HoraVisita,
        @TraeAuto = v.TraeAuto, @Marca = v.Marca, @Modelo = v.Modelo, @Placas = v.Placas,
        @EsEntrevista = v.EsEntrevista, @CodigoAcceso = v.CodigoAcceso, @UUID = v.UUID, @ID_Usuario = v.ID_Usuario
    FROM dbo.CV_Visitas v
    JOIN dbo.CV_Areas a ON a.ID = v.ID_Area
    WHERE v.ID = @ID;

    IF @@ROWCOUNT = 0 RETURN;   -- visita inexistente: nada que encolar

    DECLARE @TipoDoc  VARCHAR(20)  = CASE WHEN @EsEntrevista = 1 THEN 'Entrevista' ELSE 'Visita' END;
    DECLARE @Asunto   NVARCHAR(150) = CASE WHEN @EsEntrevista = 1 THEN N'Confirmación de tu entrevista en Celex' ELSE N'Confirmación de tu visita a Celex' END;
    DECLARE @Intro    NVARCHAR(600) = CASE WHEN @EsEntrevista = 1
        THEN N'Le confirmamos su entrevista en Celex con los siguientes datos. Presente el código de acceso en la recepción el día de su cita para agilizar su ingreso.'
        ELSE N'Le confirmamos su visita a Celex con los siguientes datos. Presente el código de acceso en la recepción el día de su visita para agilizar su ingreso.' END;
    DECLARE @LblFecha NVARCHAR(60) = CASE WHEN @EsEntrevista = 1 THEN N'Fecha de la entrevista' ELSE N'Fecha de la visita' END;
    DECLARE @Saludo   NVARCHAR(400) = dbo.fn_CV_EscaparHtml(@Nombre + N' ' + @ApellidoPaterno + N' ' + @ApellidoMaterno);

    -- Estilos reutilizados para las filas de datos (label / valor).
    DECLARE @LS NVARCHAR(200) = N'padding:5px 12px 5px 0;color:#555555;font-size:14px;vertical-align:top;white-space:nowrap;';
    DECLARE @VS NVARCHAR(200) = N'padding:5px 0;font-size:14px;font-weight:700;color:#002f87;';

    -- Fila de hora: solo si la visita tiene hora (las previas a esta versión son NULL).
    DECLARE @FilaHora NVARCHAR(MAX) = CASE WHEN @HoraVisita IS NOT NULL
        THEN N'<tr><td style="' + @LS + N'">Hora:</td><td style="' + @VS + N'">' + FORMAT(CAST(@HoraVisita AS DATETIME), 'HH:mm') + N'</td></tr>' ELSE N'' END;
    DECLARE @FilaEmpresa NVARCHAR(MAX) = CASE WHEN @Empresa <> N''
        THEN N'<tr><td style="' + @LS + N'">Empresa:</td><td style="' + @VS + N'">' + dbo.fn_CV_EscaparHtml(@Empresa) + N'</td></tr>' ELSE N'' END;
    DECLARE @FilaVehiculo NVARCHAR(MAX) = CASE WHEN @TraeAuto = 1
        THEN N'<tr><td style="' + @LS + N'">Vehículo:</td><td style="' + @VS + N'">' + dbo.fn_CV_EscaparHtml(@Marca + N' ' + @Modelo) + N' &middot; ' + dbo.fn_CV_EscaparHtml(@Placas) + N'</td></tr>' ELSE N'' END;

    DECLARE @Logo1 NVARCHAR(300) = N'https://cdn.shopify.com/s/files/1/0877/3052/files/LogoCelularExpress.png?v=1688569794';
    DECLARE @Logo2 NVARCHAR(300) = N'https://cdn.shopify.com/s/files/1/0877/3052/files/LogoDistribuidorAutorizado.png?v=1688569794';

    DECLARE @HTML NVARCHAR(MAX) =
        N'<!doctype html><html lang="es"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head>' +
        N'<body style="margin:0;padding:0;background:#ffffff;font-family:Helvetica,Arial,sans-serif;">' +
        N'<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#ffffff;"><tr><td align="center" style="padding:24px 0;">' +
        N'<table role="presentation" width="600" cellpadding="0" cellspacing="0" style="max-width:600px;width:100%;border:1px solid #e6e9f0;">' +
        -- Encabezado con los dos logos
        N'<tr><td style="padding:22px 26px 10px 26px;"><table role="presentation" width="100%"><tr>' +
        N'<td align="left" valign="middle"><img src="' + @Logo1 + N'" width="180" alt="Celular Express" style="display:block;max-width:180px;height:auto;border:0;"></td>' +
        N'<td align="right" valign="middle"><img src="' + @Logo2 + N'" width="130" alt="Distribuidor Autorizado Telcel" style="display:block;max-width:130px;height:auto;border:0;margin-left:auto;"></td>' +
        N'</tr></table></td></tr>' +
        N'<tr><td style="padding:0 26px;"><div style="border-top:2px solid #002f87;font-size:0;line-height:0;">&nbsp;</div></td></tr>' +
        -- Cuerpo
        N'<tr><td style="padding:22px 30px 30px 30px;color:#757575;font-size:16px;line-height:1.55;">' +
        N'<p style="font-weight:700;color:#002f87;margin:6px 0 12px 0;">Estimada(o): ' + @Saludo + N'</p>' +
        N'<p style="text-align:justify;margin:0 0 18px 0;">' + @Intro + N'</p>' +
        -- Caja del código de acceso
        N'<table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr><td align="center" style="padding:16px;background:#f2f6fc;border:1px dashed #002f87;">' +
        N'<div style="font-size:12px;color:#002f87;font-weight:700;letter-spacing:2px;">CÓDIGO DE ACCESO</div>' +
        N'<div style="font-size:34px;font-weight:700;letter-spacing:8px;color:#002f87;margin-top:4px;">' + @CodigoAcceso + N'</div>' +
        N'</td></tr></table>' +
        -- Datos
        N'<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin:18px 0 4px 0;">' +
        N'<tr><td style="' + @LS + N'">' + @LblFecha + N':</td><td style="' + @VS + N'">' + FORMAT(@FechaVisita, 'dd/MM/yyyy') + N'</td></tr>' +
        @FilaHora +
        @FilaEmpresa +
        N'<tr><td style="' + @LS + N'">Persona que visita:</td><td style="' + @VS + N'">' + dbo.fn_CV_EscaparHtml(@Anfitrion) + N'</td></tr>' +
        N'<tr><td style="' + @LS + N'">Área que visita:</td><td style="' + @VS + N'">' + dbo.fn_CV_EscaparHtml(@Area) + N'</td></tr>' +
        N'<tr><td style="' + @LS + N'">Motivo:</td><td style="' + @VS + N'">' + dbo.fn_CV_EscaparHtml(@Motivo) + N'</td></tr>' +
        @FilaVehiculo +
        N'</table>' +
        N'<p style="text-align:justify;margin:18px 0 0 0;">Gracias por su preferencia. ¡Le esperamos!</p>' +
        N'</td></tr></table></td></tr>' +
        -- Pie azul con soporte
        N'<tr><td align="center" style="background:#002f87;padding:34px 18px;">' +
        N'<table role="presentation" width="600" cellpadding="0" cellspacing="0" style="max-width:600px;"><tr>' +
        N'<td style="color:#ffffff;font-size:12px;line-height:1.6;text-align:center;font-family:Helvetica,Arial,sans-serif;">' +
        N'Si tiene algún problema para acceder o cualquier duda, no dude en contactarnos a través del correo<br>' +
        N'<a href="mailto:sistemas@celex.com" target="_blank" style="color:#ffffff;text-decoration:underline;">sistemas@celex.com</a><br>' +
        N'Estaremos más que dispuestos a asistirle.' +
        N'</td></tr></table></td></tr>' +
        N'</table></td></tr></table></body></html>';

    INSERT INTO dbo.WM_Correo
        (Asunto, Correos, Enviado, EnviadoFechaHr, Enviar, HTML, Usuario_ID, ID_UUID, IDFecha, TipoDocumento)
    VALUES
        (@Asunto, @Correo, 'No', '1900-01-01 00:00:00', 'Si', @HTML, @ID_Usuario,
         CAST(@UUID AS VARCHAR(128)), GETDATE(), @TipoDoc);
END
GO

/* -----------------------------------------------------------------------------
   sp_CV_Visitas_ReenviarCorreo
   Reencola el correo de confirmación de una visita existente (con sus datos
   actuales). Lo usa el botón "Enviar correo con los cambios" de la edición.
   ----------------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.sp_CV_Visitas_ReenviarCorreo
    @ID BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM dbo.CV_Visitas WHERE ID = @ID)
    BEGIN
        SELECT N'NO_ENCONTRADA' AS Resultado;
        RETURN;
    END
    EXEC dbo.sp_CV_Visitas_EncolarCorreo @ID = @ID;
    SELECT N'OK' AS Resultado;
END
GO

/* =============================================================================
   STORED PROCEDURES
   ============================================================================= */

/* -----------------------------------------------------------------------------
   sp_CV_Visitas_Registrar
   Paso 1 del flujo: el empleado captura la visita. Genera el código de
   acceso de 6 dígitos que el visitante va a teclear en la caseta.
   ----------------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.sp_CV_Visitas_Registrar
    @Nombre             NVARCHAR(100),
    @ApellidoPaterno    NVARCHAR(100),
    @ApellidoMaterno    NVARCHAR(100),
    @Correo             NVARCHAR(150),
    @Empresa            NVARCHAR(150)   = '',   -- opcional
    @ID_Area            INT,
    @Motivo             NVARCHAR(300),
    @Observaciones      NVARCHAR(500)   = '',
    @Anfitrion          NVARCHAR(100),
    @RegistradoPor      NVARCHAR(100),
    @ID_Usuario         INT             = 0,   -- Usuario_ID (WishPOS) de quien registra
    @FechaVisita        DATE,
    @HoraVisita         TIME(0)         = NULL,   -- hora agendada (informativa)
    @TraeAuto           BIT             = 0,
    @Marca              NVARCHAR(50)    = '',
    @Modelo             NVARCHAR(50)    = '',
    @Placas             NVARCHAR(20)    = '',
    @EsVIP              BIT             = 0,
    @EsEntrevista       BIT             = 0
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @NuevoUUID UNIQUEIDENTIFIER = NEWID();
    -- Defensivo: nunca guardar NULL aunque el llamador lo mande explícito.
    SET @ID_Usuario = ISNULL(@ID_Usuario, 0);
    SET @Empresa = ISNULL(@Empresa, '');
    SET @Observaciones = ISNULL(@Observaciones, '');
    SET @EsVIP = ISNULL(@EsVIP, 0);
    SET @EsEntrevista = ISNULL(@EsEntrevista, 0);
    SET @Marca  = ISNULL(@Marca, '');
    SET @Modelo = ISNULL(@Modelo, '');
    SET @Placas = ISNULL(@Placas, '');

    -- Código de acceso de 6 dígitos, único entre visitas registradas para
    -- la misma FechaVisita (se puede reciclar en otras fechas).
    DECLARE @CodigoAcceso CHAR(6);
    WHILE 1 = 1
    BEGIN
        SET @CodigoAcceso = RIGHT('000000' + CAST(ABS(CHECKSUM(NEWID())) % 1000000 AS VARCHAR(6)), 6);
        IF NOT EXISTS (
            SELECT 1 FROM dbo.CV_Visitas
            WHERE CodigoAcceso = @CodigoAcceso AND FechaVisita = @FechaVisita
        ) BREAK;
    END

    INSERT INTO dbo.CV_Visitas
        (UUID, CodigoAcceso, Nombre, ApellidoPaterno, ApellidoMaterno, Correo, Empresa, ID_Area, Motivo, Observaciones, EsVIP, EsEntrevista,
         Anfitrion, RegistradoPor, ID_Usuario, FechaVisita, HoraVisita, TraeAuto, Marca, Modelo, Placas)
    VALUES
        (@NuevoUUID, @CodigoAcceso, @Nombre, @ApellidoPaterno, @ApellidoMaterno, @Correo, @Empresa, @ID_Area, @Motivo, @Observaciones, @EsVIP, @EsEntrevista,
         @Anfitrion, @RegistradoPor, @ID_Usuario, @FechaVisita, @HoraVisita, @TraeAuto, @Marca, @Modelo, @Placas);

    -- Capturar el ID de la visita AQUÍ, antes de encolar el correo.
    DECLARE @NuevoId BIGINT = SCOPE_IDENTITY();

    -- Correo de confirmación al visitante: se arma y se encola en un SP
    -- compartido (misma plantilla para el registro y para el reenvío desde
    -- la edición). Ver dbo.sp_CV_Visitas_EncolarCorreo.
    EXEC dbo.sp_CV_Visitas_EncolarCorreo @ID = @NuevoId;

    SELECT @NuevoId AS ID, @NuevoUUID AS UUID, @CodigoAcceso AS CodigoAcceso;
END
GO

/* -----------------------------------------------------------------------------
   sp_CV_Visitas_Actualizar
   Edición desde "Mis visitas". Solo permitida mientras la visita sigue
   "Pendiente" (no se puede editar una vez que ya se usó el código de acceso).
   Resultado posible: OK | NO_ENCONTRADO | NO_EDITABLE
   ----------------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.sp_CV_Visitas_Actualizar
    @ID                 BIGINT,
    @Nombre             NVARCHAR(100),
    @ApellidoPaterno    NVARCHAR(100),
    @ApellidoMaterno    NVARCHAR(100),
    @Correo             NVARCHAR(150),
    @Empresa            NVARCHAR(150)   = '',   -- opcional
    @ID_Area            INT,
    @Motivo             NVARCHAR(300),
    @Observaciones      NVARCHAR(500)   = '',
    @Anfitrion          NVARCHAR(100),
    @FechaVisita        DATE,
    @HoraVisita         TIME(0)         = NULL,   -- hora agendada (informativa)
    @TraeAuto           BIT             = 0,
    @Marca              NVARCHAR(50)    = '',
    @Modelo             NVARCHAR(50)    = '',
    @Placas             NVARCHAR(20)    = '',
    @EsVIP              BIT             = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET @Empresa = ISNULL(@Empresa, '');
    SET @Observaciones = ISNULL(@Observaciones, '');
    SET @EsVIP = ISNULL(@EsVIP, 0);
    SET @Marca  = ISNULL(@Marca, '');
    SET @Modelo = ISNULL(@Modelo, '');
    SET @Placas = ISNULL(@Placas, '');
    DECLARE @Status NVARCHAR(20);
    SELECT @Status = Status FROM dbo.CV_Visitas WHERE ID = @ID;

    IF @Status IS NULL
    BEGIN
        SELECT N'NO_ENCONTRADO' AS Resultado;
        RETURN;
    END

    IF @Status <> N'Pendiente'
    BEGIN
        SELECT N'NO_EDITABLE' AS Resultado;
        RETURN;
    END

    UPDATE dbo.CV_Visitas
       SET Nombre = @Nombre, ApellidoPaterno = @ApellidoPaterno, ApellidoMaterno = @ApellidoMaterno,
           Correo = @Correo, Empresa = @Empresa, ID_Area = @ID_Area, Motivo = @Motivo,
           Observaciones = @Observaciones, EsVIP = @EsVIP,
           Anfitrion = @Anfitrion, FechaVisita = @FechaVisita, HoraVisita = @HoraVisita, TraeAuto = @TraeAuto,
           Marca = @Marca, Modelo = @Modelo, Placas = @Placas,
           ID_Fecha_Modificacion = GETDATE()
     WHERE ID = @ID;

    SELECT N'OK' AS Resultado;
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
            ELSE N'Salida registrada'
        END AS Estado,
        v.Status, v.FechaRegistro, v.FechaAcceso, v.FotoRuta
    FROM dbo.CV_Visitas v
    JOIN dbo.CV_Areas a ON a.ID = v.ID_Area
    WHERE v.RegistradoPor = @RegistradoPor
    ORDER BY v.FechaRegistro DESC;
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

