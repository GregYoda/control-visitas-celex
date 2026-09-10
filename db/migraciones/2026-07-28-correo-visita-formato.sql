/* =============================================================================
   MIGRACION -- FORMATO DEL CORREO DE CONFIRMACION (Control de Visitas, Celex)
   Rehace el correo de confirmacion de visitas/entrevistas con el formato tipo
   Celular Express (encabezado con logos, azul Telcel #002f87 y pie de soporte
   con sistemas@celex.com). Los textos cambian segun sea Visita o Entrevista.
   Solo refresca el SP sp_CV_Visitas_Registrar con CREATE OR ALTER; es
   idempotente y no toca datos ni esquema.
   >>> Correr con codepage UTF-8:
       sqlcmd -S SERVIDOR -d ControlVisitas_Celex -f i:65001 -i este-archivo.sql
   ============================================================================= */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
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
         Anfitrion, RegistradoPor, ID_Usuario, FechaVisita, TraeAuto, Marca, Modelo, Placas)
    VALUES
        (@NuevoUUID, @CodigoAcceso, @Nombre, @ApellidoPaterno, @ApellidoMaterno, @Correo, @Empresa, @ID_Area, @Motivo, @Observaciones, @EsVIP, @EsEntrevista,
         @Anfitrion, @RegistradoPor, @ID_Usuario, @FechaVisita, @TraeAuto, @Marca, @Modelo, @Placas);

    -- Capturar el ID de la visita AQUÍ, antes del INSERT a WM_Correo. Si se
    -- deja el SCOPE_IDENTITY() para el final, devolvería el ID de WM_Correo
    -- (el último insert del scope), no el de la visita.
    DECLARE @NuevoId BIGINT = SCOPE_IDENTITY();

    -- Correo de confirmación al visitante: se encola en WM_Correo, el
    -- SQL Server Agent Job existente lo envía (revisa cada minuto).
    -- Nota: se construye en NVARCHAR y se convierte a VARCHAR (tipo real de
    -- WM_Correo) hasta el final -- concatenar literales sin N'' aquí
    -- corrompe los acentos al pasar por el driver de sqlcmd/ODBC.
    -- Textos que cambian según sea Visita o Entrevista.
    DECLARE @EsVisita BIT = CASE WHEN @EsEntrevista = 1 THEN 0 ELSE 1 END;
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

    DECLARE @FilaEmpresa NVARCHAR(MAX) = CASE WHEN @Empresa <> N''
        THEN N'<tr><td style="' + @LS + N'">Empresa:</td><td style="' + @VS + N'">' + dbo.fn_CV_EscaparHtml(@Empresa) + N'</td></tr>' ELSE N'' END;
    DECLARE @FilaVehiculo NVARCHAR(MAX) = CASE WHEN @TraeAuto = 1
        THEN N'<tr><td style="' + @LS + N'">Vehículo:</td><td style="' + @VS + N'">' + dbo.fn_CV_EscaparHtml(@Marca + N' ' + @Modelo) + N' &middot; ' + dbo.fn_CV_EscaparHtml(@Placas) + N'</td></tr>' ELSE N'' END;

    DECLARE @Logo1 NVARCHAR(300) = N'https://cdn.shopify.com/s/files/1/0877/3052/files/LogoCelularExpress.png?v=1688569794';
    DECLARE @Logo2 NVARCHAR(300) = N'https://cdn.shopify.com/s/files/1/0877/3052/files/LogoDistribuidorAutorizado.png?v=1688569794';

    -- Correo con formato tipo Celular Express (encabezado con logos, azul Telcel
    -- #002f87 y pie de soporte). Se construye en NVARCHAR con literales N'' y se
    -- convierte a VARCHAR al insertar (concatenar sin N'' corrompe los acentos).
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
        @FilaEmpresa +
        N'<tr><td style="' + @LS + N'">Persona que visita:</td><td style="' + @VS + N'">' + dbo.fn_CV_EscaparHtml(@Anfitrion) + N'</td></tr>' +
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
         CAST(@NuevoUUID AS VARCHAR(128)), GETDATE(), @TipoDoc);

    SELECT @NuevoId AS ID, @NuevoUUID AS UUID, @CodigoAcceso AS CodigoAcceso;
END
GO
