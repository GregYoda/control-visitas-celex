/* =============================================================================
   CONTROL DE VISITAS - MODELO DE DATOS (SQL Server)
   Celex - Módulo de Control de Visitas
   =============================================================================
   Convenciones seguidas (mismo patrón que Yoda_Cat_Ladas y el resto del stack):
     - Catálogos separados de las tablas transaccionales.
     - Columna UUID para llaves externas (identificador interno; el acceso
       real se valida con CodigoAcceso, no con UUID -- ver más abajo).
     - ID_Fecha_Modificacion para auditoría de cambios.
     - SPs con prefijo sp_CV_ (Control de Visitas) para no mezclarse con Yoda_*.
     - Sin columnas NULL: todas las columnas son NOT NULL con un valor
       "vacío" por defecto según su tipo -- NVARCHAR/CHAR usan '', INT usa 0,
       DATE/DATETIME usa '1900-01-01 00:00:00' (mismo centinela que ya se
       usaba en ID_Fecha_Modificacion). Los SPs comparan contra ese centinela
       en vez de usar IS NULL / IS NOT NULL. La capa de API sí traduce ese
       centinela de vuelta a null en las respuestas JSON, para no romper la
       semántica de "todavía no aplica" que espera el frontend.

   Este script es un primer borrador para revisar juntos antes de correrlo
   contra el servidor real. Ajusta nombres de esquema / collation si no
   coinciden con lo que ya usan en Yoda_CelexPos.
   ============================================================================= */

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* -----------------------------------------------------------------------------
   0) FUNCIÓN AUXILIAR: quitar acentos para comparar apellidos sin distinguir
      mayúsculas/acentos (mismo criterio que ya usas en la normalización de
      direcciones). Requiere SQL Server 2017+ por TRANSLATE.
      >>> Si ya tienes una función de este tipo, reutilízala y omite este bloque.
   ----------------------------------------------------------------------------- */
CREATE FUNCTION dbo.fn_CV_QuitarAcentos (@Texto NVARCHAR(200))
RETURNS NVARCHAR(200)
AS
BEGIN
    RETURN UPPER(TRANSLATE(@Texto, N'áéíóúÁÉÍÓÚñÑ', N'aeiouAEIOUnN'));
END
GO

/* -----------------------------------------------------------------------------
   1) CATÁLOGO DE ÁREAS / DEPARTAMENTOS QUE PUEDEN RECIBIR VISITAS
   ----------------------------------------------------------------------------- */
CREATE TABLE dbo.CV_Areas (
    ID          INT IDENTITY(1,1)   NOT NULL,
    Nombre      NVARCHAR(100)       NOT NULL,
    Activo      BIT                 NOT NULL DEFAULT (1),
    UUID        UNIQUEIDENTIFIER    NOT NULL DEFAULT (NEWID()),
    CONSTRAINT PK_CV_Areas PRIMARY KEY CLUSTERED (ID)
);
GO

INSERT INTO dbo.CV_Areas (Nombre) VALUES
 (N'Dirección General'), (N'Sistemas / TI'), (N'Finanzas'), (N'Recursos Humanos'),
 (N'Comercial'), (N'Almacén / Logística'), (N'Contraloría Interna'), (N'Otro');
GO

/* -----------------------------------------------------------------------------
   2) TABLA PRINCIPAL: registro de la visita + acceso + salida
      (una fila cubre todo el ciclo de vida, igual que en el mockup)
   ----------------------------------------------------------------------------- */
CREATE TABLE dbo.CV_Visitas (
    ID                      BIGINT IDENTITY(1,1)    NOT NULL,
    UUID                    UNIQUEIDENTIFIER        NOT NULL DEFAULT (NEWID()),  -- identificador interno; ya no se usa para el acceso (ver CodigoAcceso)
    CodigoAcceso            CHAR(6)         NOT NULL DEFAULT (''),  -- 6 dígitos que el visitante teclea en la caseta para entrar; único por FechaVisita

    Nombre                  NVARCHAR(100)   NOT NULL,
    ApellidoPaterno         NVARCHAR(100)   NOT NULL,
    ApellidoMaterno         NVARCHAR(100)   NOT NULL,
    Correo                  NVARCHAR(150)   NOT NULL,
    Empresa                 NVARCHAR(150)   NOT NULL,
    ID_Area                 INT             NOT NULL,
    Motivo                  NVARCHAR(300)   NOT NULL,
    Anfitrion               NVARCHAR(100)   NOT NULL,   -- usuario WishPOS de la persona visitada
    RegistradoPor           NVARCHAR(100)   NOT NULL,   -- usuario WishPOS que capturó el registro
    ID_Usuario              INT             NOT NULL DEFAULT (0),  -- Usuario_ID (WishPOS) de quien capturó el registro
    FechaVisita             DATE            NOT NULL,   -- día para el que se agendó; el acceso solo se permite ese día

    TraeAuto                BIT             NOT NULL DEFAULT (0),
    Marca                   NVARCHAR(50)    NOT NULL DEFAULT (''),
    Modelo                  NVARCHAR(50)    NOT NULL DEFAULT (''),
    Placas                  NVARCHAR(20)    NOT NULL DEFAULT (''),

    Status                  NVARCHAR(20)    NOT NULL DEFAULT (N'Pendiente'),  -- Pendiente | Accesado
    FechaRegistro           DATETIME        NOT NULL DEFAULT (GETDATE()),
    FechaAcceso             DATETIME        NOT NULL DEFAULT ('1900-01-01 00:00:00'),
    FotoRuta                NVARCHAR(260)   NOT NULL DEFAULT (''),  -- ruta en disco/blob storage de la foto de la caseta

    CodigoSalida            CHAR(6)         NOT NULL DEFAULT (''),  -- 6 dígitos, único entre visitas "dentro" el mismo día
    FechaSalida             DATETIME        NOT NULL DEFAULT ('1900-01-01 00:00:00'),

    ID_Fecha_Modificacion   DATETIME        NOT NULL DEFAULT ('1900-01-01 00:00:00'),

    CONSTRAINT PK_CV_Visitas PRIMARY KEY CLUSTERED (ID),
    CONSTRAINT FK_CV_Visitas_Area FOREIGN KEY (ID_Area) REFERENCES dbo.CV_Areas(ID),
    CONSTRAINT CK_CV_Visitas_Status CHECK (Status IN (N'Pendiente', N'Accesado')),
    CONSTRAINT CK_CV_Visitas_Auto CHECK (
        (TraeAuto = 0) OR (TraeAuto = 1 AND Marca <> '' AND Modelo <> '' AND Placas <> '')
    )
);
GO

-- El UUID debe ser único (defensivo; NEWID() ya lo garantiza en la práctica)
CREATE UNIQUE INDEX UX_CV_Visitas_UUID ON dbo.CV_Visitas(UUID);
GO

-- Acelera la búsqueda del código de acceso al entrar a la caseta
CREATE INDEX IX_CV_Visitas_CodigoAcceso ON dbo.CV_Visitas(CodigoAcceso, FechaVisita);
GO

-- Acelera "¿este código de salida corresponde a alguien que sigue dentro?"
-- (sin FechaSalida real: se usa el centinela '1900-01-01' en vez de NULL, ver
-- convención de "sin nulos" al inicio del archivo)
CREATE INDEX IX_CV_Visitas_CodigoSalida_Activo
    ON dbo.CV_Visitas(CodigoSalida, FechaAcceso)
    WHERE FechaSalida = '1900-01-01' AND CodigoSalida <> '';
GO

-- Acelera los reportes por rango de fechas
CREATE INDEX IX_CV_Visitas_FechaRegistro ON dbo.CV_Visitas(FechaRegistro);
GO

/* -----------------------------------------------------------------------------
   3) BITÁCORA DE INTENTOS DE VALIDACIÓN (seguridad: apellidos correctos/fallidos)
   ----------------------------------------------------------------------------- */
CREATE TABLE dbo.CV_Intentos_Acceso (
    ID                  BIGINT IDENTITY(1,1)    NOT NULL,
    ID_Visita           BIGINT                  NOT NULL,
    Fecha               DATETIME                NOT NULL DEFAULT (GETDATE()),
    ApellidoTecleado    NVARCHAR(100)           NOT NULL,
    Resultado           NVARCHAR(20)            NOT NULL,  -- Exitoso | Fallido
    CONSTRAINT PK_CV_Intentos_Acceso PRIMARY KEY CLUSTERED (ID),
    CONSTRAINT FK_CV_Intentos_Visita FOREIGN KEY (ID_Visita) REFERENCES dbo.CV_Visitas(ID)
);
GO

/* =============================================================================
   STORED PROCEDURES
   ============================================================================= */

/* -----------------------------------------------------------------------------
   sp_CV_Visitas_Registrar
   Paso 1 del flujo: el empleado captura la visita. Genera el código de
   acceso de 6 dígitos que el visitante va a teclear en la caseta.
   ----------------------------------------------------------------------------- */
CREATE PROCEDURE dbo.sp_CV_Visitas_Registrar
    @Nombre             NVARCHAR(100),
    @ApellidoPaterno    NVARCHAR(100),
    @ApellidoMaterno    NVARCHAR(100),
    @Correo             NVARCHAR(150),
    @Empresa            NVARCHAR(150),
    @ID_Area            INT,
    @Motivo             NVARCHAR(300),
    @Anfitrion          NVARCHAR(100),
    @RegistradoPor      NVARCHAR(100),
    @ID_Usuario         INT             = 0,   -- Usuario_ID (WishPOS) de quien registra
    @FechaVisita        DATE,
    @TraeAuto           BIT             = 0,
    @Marca              NVARCHAR(50)    = '',
    @Modelo             NVARCHAR(50)    = '',
    @Placas             NVARCHAR(20)    = ''
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @NuevoUUID UNIQUEIDENTIFIER = NEWID();
    -- Defensivo: nunca guardar NULL aunque el llamador lo mande explícito.
    SET @ID_Usuario = ISNULL(@ID_Usuario, 0);
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
        (UUID, CodigoAcceso, Nombre, ApellidoPaterno, ApellidoMaterno, Correo, Empresa, ID_Area, Motivo,
         Anfitrion, RegistradoPor, ID_Usuario, FechaVisita, TraeAuto, Marca, Modelo, Placas)
    VALUES
        (@NuevoUUID, @CodigoAcceso, @Nombre, @ApellidoPaterno, @ApellidoMaterno, @Correo, @Empresa, @ID_Area, @Motivo,
         @Anfitrion, @RegistradoPor, @ID_Usuario, @FechaVisita, @TraeAuto, @Marca, @Modelo, @Placas);

    SELECT SCOPE_IDENTITY() AS ID, @NuevoUUID AS UUID, @CodigoAcceso AS CodigoAcceso;
END
GO

/* -----------------------------------------------------------------------------
   sp_CV_Visitas_ValidarAcceso
   Paso 2: la caseta recibió el código de acceso de 6 dígitos y el visitante
   tecleó su apellido paterno. Si coincide, marca el acceso, guarda la foto y
   genera el código de salida.
   Resultado posible: OK | NO_ENCONTRADO | YA_UTILIZADO | FECHA_NO_COINCIDE |
                      APELLIDO_NO_COINCIDE
   ----------------------------------------------------------------------------- */
CREATE PROCEDURE dbo.sp_CV_Visitas_ValidarAcceso
    @CodigoAcceso       CHAR(6),
    @ApellidoTecleado   NVARCHAR(100),
    @FotoRuta           NVARCHAR(260)   = ''
AS
BEGIN
    SET NOCOUNT ON;
    SET @FotoRuta = ISNULL(@FotoRuta, '');
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

    -- Una visita solo puede accesarse el día para el que fue registrada.
    IF @FechaVisita <> CAST(GETDATE() AS DATE)
    BEGIN
        SELECT N'FECHA_NO_COINCIDE' AS Resultado, @FechaVisita AS FechaVisita;
        RETURN;
    END

    IF dbo.fn_CV_QuitarAcentos(LTRIM(RTRIM(@ApellidoTecleado))) = dbo.fn_CV_QuitarAcentos(@ApellidoReal)
    BEGIN
        DECLARE @Codigo CHAR(6);

        -- Genera un código de 6 dígitos único entre las visitas "dentro" hoy.
        -- Nota de producción: bajo concurrencia alta convendría envolver esto
        -- en un retry con manejo de violación de índice; para el volumen
        -- típico de una caseta esto es suficiente.
        WHILE 1 = 1
        BEGIN
            SET @Codigo = RIGHT('000000' + CAST(ABS(CHECKSUM(NEWID())) % 1000000 AS VARCHAR(6)), 6);
            IF NOT EXISTS (
                SELECT 1 FROM dbo.CV_Visitas
                WHERE CodigoSalida = @Codigo AND FechaSalida = '1900-01-01'
                  AND CAST(FechaAcceso AS DATE) = CAST(GETDATE() AS DATE)
            ) BREAK;
        END

        UPDATE dbo.CV_Visitas
           SET Status = N'Accesado',
               FechaAcceso = GETDATE(),
               CodigoSalida = @Codigo,
               FotoRuta = @FotoRuta,
               ID_Fecha_Modificacion = GETDATE()
         WHERE ID = @ID;

        INSERT INTO dbo.CV_Intentos_Acceso (ID_Visita, ApellidoTecleado, Resultado)
        VALUES (@ID, @ApellidoTecleado, N'Exitoso');

        SELECT N'OK' AS Resultado, v.ID, v.Nombre, v.ApellidoPaterno, v.ApellidoMaterno,
               v.Empresa, v.Motivo, v.Anfitrion, a.Nombre AS Area, v.FechaVisita,
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
   ----------------------------------------------------------------------------- */
CREATE PROCEDURE dbo.sp_CV_Visitas_BuscarPorCodigoSalida
    @Codigo CHAR(6)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT ID, Nombre, ApellidoPaterno, ApellidoMaterno, Empresa, Anfitrion, FechaAcceso, FotoRuta
    FROM dbo.CV_Visitas
    WHERE CodigoSalida = @Codigo
      AND Status = N'Accesado'
      AND FechaSalida = '1900-01-01'
      AND CAST(FechaAcceso AS DATE) = CAST(GETDATE() AS DATE);
END
GO

/* -----------------------------------------------------------------------------
   sp_CV_Visitas_ConfirmarSalida
   Paso 3b: el visitante confirmó "sí soy yo". Marca la salida definitiva.
   ----------------------------------------------------------------------------- */
CREATE PROCEDURE dbo.sp_CV_Visitas_ConfirmarSalida
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
CREATE PROCEDURE dbo.sp_CV_Visitas_Reporte
    @FechaInicio DATE,
    @FechaFin    DATE
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        v.ID, v.Nombre, v.ApellidoPaterno, v.ApellidoMaterno, v.Empresa,
        a.Nombre AS Area, v.Anfitrion, v.Motivo,
        CASE
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
CREATE PROCEDURE dbo.sp_CV_Visitas_MisVisitas
    @RegistradoPor NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        v.ID, v.UUID, v.Nombre, v.ApellidoPaterno, v.ApellidoMaterno, v.Correo, v.Empresa,
        v.ID_Area, a.Nombre AS Area, v.Motivo, v.Anfitrion, v.FechaVisita,
        v.TraeAuto, v.Marca, v.Modelo, v.Placas,
        CASE
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
CREATE PROCEDURE dbo.sp_CV_Visitas_Actualizar
    @ID                 BIGINT,
    @Nombre             NVARCHAR(100),
    @ApellidoPaterno    NVARCHAR(100),
    @ApellidoMaterno    NVARCHAR(100),
    @Correo             NVARCHAR(150),
    @Empresa            NVARCHAR(150),
    @ID_Area            INT,
    @Motivo             NVARCHAR(300),
    @Anfitrion          NVARCHAR(100),
    @FechaVisita        DATE,
    @TraeAuto           BIT             = 0,
    @Marca              NVARCHAR(50)    = '',
    @Modelo             NVARCHAR(50)    = '',
    @Placas             NVARCHAR(20)    = ''
AS
BEGIN
    SET NOCOUNT ON;
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
           Anfitrion = @Anfitrion, FechaVisita = @FechaVisita, TraeAuto = @TraeAuto,
           Marca = @Marca, Modelo = @Modelo, Placas = @Placas,
           ID_Fecha_Modificacion = GETDATE()
     WHERE ID = @ID;

    SELECT N'OK' AS Resultado;
END
GO
