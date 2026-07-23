/* =============================================================================
   MIGRACIÓN ACUMULADA -- Control de Visitas (Celex)
   Lleva una base YA INSTALADA a la versión actual, sin recrearla.
   Es idempotente: se puede correr varias veces sin daño (agrega lo que falte
   y refresca funciones/SPs con CREATE OR ALTER).
   >>> Correr con codepage UTF-8:  sqlcmd -S SERVIDOR -d ControlVisitas_Celex -f i:65001 -i este-archivo.sql
   >>> Ajustar el nombre de la base de WishPOS en el SYNONYM (paso 5) si no es WISH.
   ============================================================================= */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* 1) Columnas agregadas a lo largo del proyecto (solo si faltan) --------------- */
IF COL_LENGTH('dbo.CV_Visitas','FechaVisita') IS NULL
    ALTER TABLE dbo.CV_Visitas ADD FechaVisita DATE NOT NULL CONSTRAINT DF_CV_Visitas_FechaVisita DEFAULT ('1900-01-01');
GO
IF COL_LENGTH('dbo.CV_Visitas','ID_Usuario') IS NULL
    ALTER TABLE dbo.CV_Visitas ADD ID_Usuario INT NOT NULL CONSTRAINT DF_CV_Visitas_ID_Usuario DEFAULT (0);
GO
IF COL_LENGTH('dbo.CV_Visitas','Observaciones') IS NULL
    ALTER TABLE dbo.CV_Visitas ADD Observaciones NVARCHAR(500) NOT NULL CONSTRAINT DF_CV_Visitas_Observaciones DEFAULT ('');
GO
IF COL_LENGTH('dbo.CV_Visitas','EsVIP') IS NULL
    ALTER TABLE dbo.CV_Visitas ADD EsVIP BIT NOT NULL CONSTRAINT DF_CV_Visitas_EsVIP DEFAULT (0);
GO
IF COL_LENGTH('dbo.CV_Visitas','EsEntrevista') IS NULL
    ALTER TABLE dbo.CV_Visitas ADD EsEntrevista BIT NOT NULL CONSTRAINT DF_CV_Visitas_EsEntrevista DEFAULT (0);
GO

/* 2) Empresa opcional: agregar DEFAULT('') si no tiene uno -------------------- */
IF NOT EXISTS (
    SELECT 1 FROM sys.default_constraints dc
    WHERE dc.parent_object_id = OBJECT_ID('dbo.CV_Visitas')
      AND COL_NAME(dc.parent_object_id, dc.parent_column_id) = 'Empresa')
    ALTER TABLE dbo.CV_Visitas ADD CONSTRAINT DF_CV_Visitas_Empresa DEFAULT ('') FOR Empresa;
GO

/* 3) Estado 'Cancelada' permitido en el CHECK de Status ---------------------- */
IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_CV_Visitas_Status')
    ALTER TABLE dbo.CV_Visitas DROP CONSTRAINT CK_CV_Visitas_Status;
GO
ALTER TABLE dbo.CV_Visitas ADD CONSTRAINT CK_CV_Visitas_Status
    CHECK (Status IN (N'Pendiente', N'Accesado', N'Cancelada'));
GO

/* 4) Claves de configuración (solo las que falten) --------------------------- */
IF NOT EXISTS (SELECT 1 FROM dbo.CV_Configuracion WHERE Clave=N'UsuariosVIP')          INSERT INTO dbo.CV_Configuracion (Clave,Valor) VALUES (N'UsuariosVIP', N'');
IF NOT EXISTS (SELECT 1 FROM dbo.CV_Configuracion WHERE Clave=N'UsuariosKiosko')       INSERT INTO dbo.CV_Configuracion (Clave,Valor) VALUES (N'UsuariosKiosko', N'');
IF NOT EXISTS (SELECT 1 FROM dbo.CV_Configuracion WHERE Clave=N'UsuariosReclutadores') INSERT INTO dbo.CV_Configuracion (Clave,Valor) VALUES (N'UsuariosReclutadores', N'');
IF NOT EXISTS (SELECT 1 FROM dbo.CV_Configuracion WHERE Clave=N'EntrevistaEmpresa')     INSERT INTO dbo.CV_Configuracion (Clave,Valor) VALUES (N'EntrevistaEmpresa', N'Entrevista');
IF NOT EXISTS (SELECT 1 FROM dbo.CV_Configuracion WHERE Clave=N'EntrevistaIdArea')      INSERT INTO dbo.CV_Configuracion (Clave,Valor) VALUES (N'EntrevistaIdArea', N'');
IF NOT EXISTS (SELECT 1 FROM dbo.CV_Configuracion WHERE Clave=N'EntrevistaMotivo')      INSERT INTO dbo.CV_Configuracion (Clave,Valor) VALUES (N'EntrevistaMotivo', N'Entrevista');
IF NOT EXISTS (SELECT 1 FROM dbo.CV_Configuracion WHERE Clave=N'EntrevistaFechaModo')   INSERT INTO dbo.CV_Configuracion (Clave,Valor) VALUES (N'EntrevistaFechaModo', N'dia');
IF NOT EXISTS (SELECT 1 FROM dbo.CV_Configuracion WHERE Clave=N'EntrevistaAnfitrion')   INSERT INTO dbo.CV_Configuracion (Clave,Valor) VALUES (N'EntrevistaAnfitrion', N'Recepción');
GO

/* 5) SYNONYM a WM_Correo (base de WishPOS). Ajustar 'WISH' al nombre real ----- */
IF OBJECT_ID('dbo.WM_Correo') IS NULL
    EXEC('CREATE SYNONYM dbo.WM_Correo FOR WISH.dbo.WM_Correo');
GO

/* =============================================================================
   6) Funciones y stored procedures -- se refrescan a la versión actual
      (CREATE OR ALTER; seguro correrlo aunque ya existan).
   ============================================================================= */

/* -----------------------------------------------------------------------------
   0) FUNCIÓN AUXILIAR: quitar acentos para comparar apellidos sin distinguir
      mayúsculas/acentos (mismo criterio que ya usas en la normalización de
      direcciones). Requiere SQL Server 2017+ por TRANSLATE.
      >>> Si ya tienes una función de este tipo, reutilízala y omite este bloque.
   ----------------------------------------------------------------------------- */
CREATE OR ALTER FUNCTION dbo.fn_CV_QuitarAcentos (@Texto NVARCHAR(200))
RETURNS NVARCHAR(200)
AS
BEGIN
    RETURN UPPER(TRANSLATE(@Texto, N'áéíóúÁÉÍÓÚñÑ', N'aeiouAEIOUnN'));
END
GO

/* -----------------------------------------------------------------------------
   0.1) FUNCIÓN AUXILIAR: escapar texto libre antes de meterlo en el HTML del
        correo de confirmación de visita (Nombre, Empresa, Motivo, etc. son
        capturados por el usuario y no deben poder inyectar markup).
   ----------------------------------------------------------------------------- */
CREATE OR ALTER FUNCTION dbo.fn_CV_EscaparHtml (@Texto NVARCHAR(500))
RETURNS NVARCHAR(1000)
AS
BEGIN
    RETURN REPLACE(REPLACE(REPLACE(ISNULL(@Texto, ''), N'&', N'&amp;'), N'<', N'&lt;'), N'>', N'&gt;');
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
    DECLARE @VehiculoHtml NVARCHAR(MAX) = N'';
    IF @TraeAuto = 1
    BEGIN
        SET @VehiculoHtml =
            N'<p>Como registraste que acudirás en automóvil, estos son los datos que proporcionaste:</p>' +
            N'<table style="margin-bottom:16px;">' +
            N'<tr><td style="padding:2px 12px 2px 0;color:#555;">Marca:</td><td><b>' + dbo.fn_CV_EscaparHtml(@Marca)  + N'</b></td></tr>' +
            N'<tr><td style="padding:2px 12px 2px 0;color:#555;">Modelo:</td><td><b>' + dbo.fn_CV_EscaparHtml(@Modelo) + N'</b></td></tr>' +
            N'<tr><td style="padding:2px 12px 2px 0;color:#555;">Placas:</td><td><b>' + dbo.fn_CV_EscaparHtml(@Placas) + N'</b></td></tr>' +
            N'</table>';
    END

    DECLARE @HTML NVARCHAR(MAX) =
        N'<p>Hola ' + dbo.fn_CV_EscaparHtml(@Nombre + N' ' + @ApellidoPaterno + N' ' + @ApellidoMaterno) + N',</p>' +
        N'<p>Confirmamos tu visita a Celex con los siguientes datos:</p>' +
        N'<table style="margin-bottom:16px;">' +
        N'<tr><td style="padding:2px 12px 2px 0;color:#555;">Fecha:</td><td><b>' + FORMAT(@FechaVisita, 'dd/MM/yyyy') + N'</b></td></tr>' +
        N'<tr><td style="padding:2px 12px 2px 0;color:#555;">Empresa:</td><td><b>' + dbo.fn_CV_EscaparHtml(@Empresa) + N'</b></td></tr>' +
        N'<tr><td style="padding:2px 12px 2px 0;color:#555;">Persona que visitas:</td><td><b>' + dbo.fn_CV_EscaparHtml(@Anfitrion) + N'</b></td></tr>' +
        N'<tr><td style="padding:2px 12px 2px 0;color:#555;">Motivo:</td><td><b>' + dbo.fn_CV_EscaparHtml(@Motivo) + N'</b></td></tr>' +
        N'</table>' +
        N'<p>Tu código de acceso es:</p>' +
        N'<p style="font-size:28px;font-weight:bold;letter-spacing:4px;">' + @CodigoAcceso + N'</p>' +
        N'<p>Preséntalo en la recepción el día de tu visita para agilizar tu ingreso.</p>' +
        @VehiculoHtml +
        N'<p>Te esperamos.</p>' +
        N'<p>Celex</p>';

    INSERT INTO dbo.WM_Correo
        (Asunto, Correos, Enviado, EnviadoFechaHr, Enviar, HTML, Usuario_ID, ID_UUID, IDFecha, TipoDocumento)
    VALUES
        (N'Confirmación de tu visita a Celex', @Correo, 'No', '1900-01-01 00:00:00', 'Si', @HTML, @ID_Usuario,
         CAST(@NuevoUUID AS VARCHAR(128)), GETDATE(), 'Visita');

    SELECT @NuevoId AS ID, @NuevoUUID AS UUID, @CodigoAcceso AS CodigoAcceso;
END
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
               v.Empresa, v.Motivo, v.Observaciones, v.EsVIP, v.Anfitrion, a.Nombre AS Area, v.FechaVisita,
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

/* -----------------------------------------------------------------------------
   sp_CV_Visitas_BuscarPorCodigoSalida
   Paso 3a: el visitante teclea su código de 6 dígitos en el kiosko.
   Regresa los datos para la pantalla "¿Eres tú?" (sin marcar la salida todavía).
   La salida se permite hasta 48 horas después del registro de entrada
   (FechaAcceso); pasado ese plazo el código deja de ser válido.
   ----------------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.sp_CV_Visitas_BuscarPorCodigoSalida
    @Codigo CHAR(6)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT ID, Nombre, ApellidoPaterno, ApellidoMaterno, Empresa, Anfitrion, FechaAcceso, FotoRuta
    FROM dbo.CV_Visitas
    WHERE CodigoSalida = @Codigo
      AND Status = N'Accesado'
      AND FechaSalida = '1900-01-01'
      AND FechaAcceso >= DATEADD(HOUR, -48, GETDATE());
END
GO

/* -----------------------------------------------------------------------------
   sp_CV_Visitas_ConfirmarSalida
   Paso 3b: el visitante confirmó "sí soy yo". Marca la salida definitiva.
   ----------------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.sp_CV_Visitas_ConfirmarSalida
    @ID BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.CV_Visitas
       SET FechaSalida = GETDATE(),
           ID_Fecha_Modificacion = GETDATE()
     WHERE ID = @ID AND FechaSalida = '1900-01-01';

    SELECT Nombre, ApellidoPaterno, ApellidoMaterno, FechaAcceso, FechaSalida,
           DATEDIFF(MINUTE, FechaAcceso, FechaSalida) AS MinutosEstancia
    FROM dbo.CV_Visitas WHERE ID = @ID;
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
        v.FechaVisita, v.FechaRegistro, v.FechaAcceso, v.CodigoSalida, v.FechaSalida,
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
        v.ID_Area, a.Nombre AS Area, v.Motivo, v.Observaciones, v.EsVIP, v.Anfitrion, v.FechaVisita,
        v.TraeAuto, v.Marca, v.Modelo, v.Placas,
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
           Anfitrion = @Anfitrion, FechaVisita = @FechaVisita, TraeAuto = @TraeAuto,
           Marca = @Marca, Modelo = @Modelo, Placas = @Placas,
           ID_Fecha_Modificacion = GETDATE()
     WHERE ID = @ID;

    SELECT N'OK' AS Resultado;
END
GO

/* -----------------------------------------------------------------------------
   sp_CV_Visitas_Cancelar
   Cancela una visita desde "Mis visitas". Solo permitida mientras sigue
   "Pendiente" -- una vez que ya se usó el código de acceso, la visita ya
   entró y cancelarla no tendría sentido (para eso está el flujo de salida).
   Resultado posible: OK | NO_ENCONTRADO | NO_CANCELABLE
   ----------------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.sp_CV_Visitas_Cancelar
    @ID BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Status NVARCHAR(20);
    SELECT @Status = Status FROM dbo.CV_Visitas WHERE ID = @ID;

    IF @Status IS NULL
    BEGIN
        SELECT N'NO_ENCONTRADO' AS Resultado;
        RETURN;
    END

    IF @Status <> N'Pendiente'
    BEGIN
        SELECT N'NO_CANCELABLE' AS Resultado;
        RETURN;
    END

    UPDATE dbo.CV_Visitas
       SET Status = N'Cancelada',
           ID_Fecha_Modificacion = GETDATE()
     WHERE ID = @ID;

    SELECT N'OK' AS Resultado;
END
GO

/* -----------------------------------------------------------------------------
   sp_CV_Visitas_ActualizarFoto
   Guarda la ruta en disco de la foto ya escrita por la API (ver FotoService.cs).
   ----------------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.sp_CV_Visitas_ActualizarFoto
    @ID         BIGINT,
    @FotoRuta   NVARCHAR(260)
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.CV_Visitas
       SET FotoRuta = ISNULL(@FotoRuta, ''),
           ID_Fecha_Modificacion = GETDATE()
     WHERE ID = @ID;
END
GO

/* -----------------------------------------------------------------------------
   sp_CV_Visitas_ObtenerInfoFoto
   Datos que necesita FotoService para armar/localizar la ruta de la foto:
   la fecha de visita (define carpeta Año/Mes), si es Entrevista (define carpeta
   Tipo) y la ruta ya guardada (para servir la foto).
   ----------------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.sp_CV_Visitas_ObtenerInfoFoto
    @ID BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT FechaVisita, EsEntrevista, FotoRuta FROM dbo.CV_Visitas WHERE ID = @ID;
END
GO

/* -----------------------------------------------------------------------------
   sp_CV_Configuracion_Obtener / sp_CV_Configuracion_Actualizar
   Pantalla de Configuración (solo visible con el permiso CV.200.00).
   ----------------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.sp_CV_Configuracion_Obtener
AS
BEGIN
    SET NOCOUNT ON;
    SELECT Clave, Valor FROM dbo.CV_Configuracion ORDER BY Clave;
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_CV_Configuracion_Actualizar
    @Clave  NVARCHAR(100),
    @Valor  NVARCHAR(500)
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM dbo.CV_Configuracion WHERE Clave = @Clave)
        UPDATE dbo.CV_Configuracion
           SET Valor = @Valor, ID_Fecha_Modificacion = GETDATE()
         WHERE Clave = @Clave;
    ELSE
        INSERT INTO dbo.CV_Configuracion (Clave, Valor, ID_Fecha_Modificacion)
        VALUES (@Clave, @Valor, GETDATE());

    SELECT N'OK' AS Resultado;
END
GO
