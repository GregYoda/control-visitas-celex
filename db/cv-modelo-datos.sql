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
   0.1) FUNCIÓN AUXILIAR: escapar texto libre antes de meterlo en el HTML del
        correo de confirmación de visita (Nombre, Empresa, Motivo, etc. son
        capturados por el usuario y no deben poder inyectar markup).
   ----------------------------------------------------------------------------- */
CREATE FUNCTION dbo.fn_CV_EscaparHtml (@Texto NVARCHAR(500))
RETURNS NVARCHAR(1000)
AS
BEGIN
    RETURN REPLACE(REPLACE(REPLACE(ISNULL(@Texto, ''), N'&', N'&amp;'), N'<', N'&lt;'), N'>', N'&gt;');
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
    Empresa                 NVARCHAR(150)   NOT NULL DEFAULT (''),   -- opcional
    ID_Area                 INT             NOT NULL,
    Motivo                  NVARCHAR(300)   NOT NULL,
    Observaciones           NVARCHAR(500)   NOT NULL DEFAULT (''),  -- comentarios libres para que vigilancia los considere al recibir la visita
    EsVIP                   BIT             NOT NULL DEFAULT (0),   -- visita VIP; solo la marcan usuarios autorizados (ver CV_Configuracion.UsuariosVIP)
    EsEntrevista            BIT             NOT NULL DEFAULT (0),   -- visita tipo Entrevista (la marcan los reclutadores); define la carpeta Tipo de la foto
    Anfitrion               NVARCHAR(100)   NOT NULL,   -- usuario WishPOS de la persona visitada
    RegistradoPor           NVARCHAR(100)   NOT NULL,   -- usuario WishPOS que capturó el registro
    ID_Usuario              INT             NOT NULL DEFAULT (0),  -- Usuario_ID (WishPOS) de quien capturó el registro
    FechaVisita             DATE            NOT NULL,   -- día para el que se agendó; el acceso solo se permite ese día

    TraeAuto                BIT             NOT NULL DEFAULT (0),
    Marca                   NVARCHAR(50)    NOT NULL DEFAULT (''),
    Modelo                  NVARCHAR(50)    NOT NULL DEFAULT (''),
    Placas                  NVARCHAR(20)    NOT NULL DEFAULT (''),

    Status                  NVARCHAR(20)    NOT NULL DEFAULT (N'Pendiente'),  -- Pendiente | Accesado | Cancelada
    FechaRegistro           DATETIME        NOT NULL DEFAULT (GETDATE()),
    FechaAcceso             DATETIME        NOT NULL DEFAULT ('1900-01-01 00:00:00'),
    FotoRuta                NVARCHAR(260)   NOT NULL DEFAULT (''),  -- ruta en disco/blob storage de la foto de la caseta

    CodigoSalida            CHAR(6)         NOT NULL DEFAULT (''),  -- 6 dígitos, único entre visitas "dentro" el mismo día
    FechaSalida             DATETIME        NOT NULL DEFAULT ('1900-01-01 00:00:00'),

    ID_Fecha_Modificacion   DATETIME        NOT NULL DEFAULT ('1900-01-01 00:00:00'),

    CONSTRAINT PK_CV_Visitas PRIMARY KEY CLUSTERED (ID),
    CONSTRAINT FK_CV_Visitas_Area FOREIGN KEY (ID_Area) REFERENCES dbo.CV_Areas(ID),
    CONSTRAINT CK_CV_Visitas_Status CHECK (Status IN (N'Pendiente', N'Accesado', N'Cancelada')),
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

/* -----------------------------------------------------------------------------
   4) CONFIGURACIÓN: parámetros del sistema (clave/valor), editable desde la
      pantalla de Configuración (solo visible con el permiso CV.200.00 de
      WishPOS -- ver WishPosAuthService.cs).
   ----------------------------------------------------------------------------- */
CREATE TABLE dbo.CV_Configuracion (
    Clave                   NVARCHAR(100)   NOT NULL,
    Valor                   NVARCHAR(500)   NOT NULL DEFAULT (''),
    ID_Fecha_Modificacion   DATETIME        NOT NULL DEFAULT ('1900-01-01 00:00:00'),
    CONSTRAINT PK_CV_Configuracion PRIMARY KEY CLUSTERED (Clave)
);
GO

-- RutaFotos: carpeta donde se guardan las fotos de los visitantes.
-- PrefijoFoto + DigitosFoto: construyen el nombre de archivo como
-- <PrefijoFoto> + ID de CV_Visitas con ceros a la izquierda a <DigitosFoto>
-- dígitos (ej. CV0000000001.jpg con los valores por defecto).
-- UsuariosVIP: lista de Usuario_ID (WishPOS, el ID que devuelve el login)
-- separados por coma, que pueden marcar una visita como VIP (ej. '100,205').
-- Vacío = nadie puede marcar VIP.
-- UsuariosKiosko: lista de Usuario_ID (mismo formato) que, al iniciar sesión,
-- entran DIRECTO al kiosko de ingreso/salida (modo terminal de caseta) en vez
-- de al menú. Vacío = nadie entra directo al kiosko.
-- UsuariosReclutadores: lista de Usuario_ID (mismo formato) que ven el check
-- "Visita tipo Entrevista" al registrar. Vacío = nadie.
-- Entrevista*: valores por defecto que se prellenan al activar ese check.
-- Un valor vacío = ese campo NO se prellena. EntrevistaFechaModo: '' | 'dia'
-- (día siguiente, +1) | 'semana' (semana siguiente, +7). EntrevistaIdArea: ID
-- de CV_Areas (numérico) o vacío.
INSERT INTO dbo.CV_Configuracion (Clave, Valor) VALUES
 (N'RutaFotos', N'C:\Control de Visitas\Fotos'),
 (N'PrefijoFoto', N'CV'),
 (N'DigitosFoto', N'10'),
 (N'UsuariosVIP', N''),
 (N'UsuariosKiosko', N''),
 (N'UsuariosReclutadores', N''),
 (N'EntrevistaEmpresa', N'Entrevista'),
 (N'EntrevistaIdArea', N''),
 (N'EntrevistaMotivo', N'Entrevista'),
 (N'EntrevistaFechaModo', N'dia'),
 (N'EntrevistaAnfitrion', N'Recepción');
GO

/* -----------------------------------------------------------------------------
   4.5) ASISTENCIA DE EMPLEADOS Y MENSAJEROS (checador del kiosko)
      CV_Empleados: catálogo de personal que puede registrar asistencia.
      CV_Asistencia: una fila por empleado por día (estilo checador) con las
      cuatro marcas de hora. Los mensajeros solo usan Entrada; los empleados
      además marcan SalidaComer -> RegresoComida -> Salida (en ese orden, con
      salida anticipada permitida). Sin columnas NULL: las horas no marcadas
      quedan con el centinela '1900-01-01 00:00:00'.
   ----------------------------------------------------------------------------- */
CREATE TABLE dbo.CV_Empleados (
    ID                      INT IDENTITY(1,1)   NOT NULL,
    UUID                    UNIQUEIDENTIFIER    NOT NULL DEFAULT (NEWID()),
    NumeroEmpleado          NVARCHAR(20)        NOT NULL DEFAULT (''),   -- número de empleado interno
    NumeroWishPOS           NVARCHAR(20)        NOT NULL DEFAULT (''),   -- usuario/número en WishPOS ('' si no aplica, ej. mensajeros)
    NombreCompleto          NVARCHAR(150)       NOT NULL,
    Tipo                    NVARCHAR(20)        NOT NULL DEFAULT (N'Empleado'),  -- Empleado | Mensajero
    CodigoAcceso            CHAR(6)         NOT NULL DEFAULT (''),   -- 6 dígitos que el empleado teclea en el kiosko; lo GENERA el sistema (no se captura), único entre activos
    Activo                  BIT                 NOT NULL DEFAULT (1),
    FechaRegistro           DATETIME            NOT NULL DEFAULT (GETDATE()),
    ID_Fecha_Modificacion   DATETIME            NOT NULL DEFAULT ('1900-01-01 00:00:00'),
    CONSTRAINT PK_CV_Empleados PRIMARY KEY CLUSTERED (ID),
    CONSTRAINT CK_CV_Empleados_Tipo CHECK (Tipo IN (N'Empleado', N'Mensajero'))
);
GO

-- El código de acceso debe ser único entre empleados ACTIVOS (se puede reciclar
-- el código de uno dado de baja). Se excluye el código en blanco ('') del índice
-- para permitir la carga masiva: se insertan los renglones sin código y luego
-- se generan con sp_CV_Empleados_GenerarCodigosFaltantes (si '' contara, dos
-- renglones en blanco chocarían en el índice).
CREATE UNIQUE INDEX UX_CV_Empleados_Codigo ON dbo.CV_Empleados(CodigoAcceso) WHERE Activo = 1 AND CodigoAcceso <> '';
GO
CREATE UNIQUE INDEX UX_CV_Empleados_UUID ON dbo.CV_Empleados(UUID);
GO

CREATE TABLE dbo.CV_Asistencia (
    ID                      BIGINT IDENTITY(1,1)    NOT NULL,
    ID_Empleado             INT                     NOT NULL,
    Fecha                   DATE                    NOT NULL,   -- día de la jornada
    Entrada                 DATETIME                NOT NULL DEFAULT ('1900-01-01 00:00:00'),
    SalidaComer             DATETIME                NOT NULL DEFAULT ('1900-01-01 00:00:00'),
    RegresoComida           DATETIME                NOT NULL DEFAULT ('1900-01-01 00:00:00'),
    Salida                  DATETIME                NOT NULL DEFAULT ('1900-01-01 00:00:00'),
    FotoRuta                NVARCHAR(260)           NOT NULL DEFAULT (''),  -- foto tomada al registrar la entrada
    TipoEmpleado            NVARCHAR(20)            NOT NULL DEFAULT (N'Empleado'), -- copia del tipo al momento del registro (Empleado|Mensajero)
    ID_Fecha_Modificacion   DATETIME                NOT NULL DEFAULT ('1900-01-01 00:00:00'),
    CONSTRAINT PK_CV_Asistencia PRIMARY KEY CLUSTERED (ID),
    CONSTRAINT FK_CV_Asistencia_Empleado FOREIGN KEY (ID_Empleado) REFERENCES dbo.CV_Empleados(ID)
);
GO

-- Una sola fila por empleado por día
CREATE UNIQUE INDEX UX_CV_Asistencia_EmpFecha ON dbo.CV_Asistencia(ID_Empleado, Fecha);
GO
-- Acelera reportes por rango de fechas
CREATE INDEX IX_CV_Asistencia_Fecha ON dbo.CV_Asistencia(Fecha);
GO

-- Empleados de ejemplo para pruebas. El código es de 6 dígitos (en producción
-- lo genera el sistema; aquí se fijan valores conocidos para poder probar).
INSERT INTO dbo.CV_Empleados (NumeroEmpleado, NumeroWishPOS, NombreCompleto, Tipo, CodigoAcceso) VALUES
 (N'1024', N'305', N'María Fernanda López', N'Empleado',  N'483012'),
 (N'1055', N'312', N'Carlos Ramírez Soto',  N'Empleado',  N'729145'),
 (N'1099', N'340', N'Ana Torres Vega',      N'Empleado',  N'660433'),
 (N'2010', N'',    N'Jorge Méndez',         N'Mensajero', N'515078');
GO

/* -----------------------------------------------------------------------------
   5) WM_Correo: cola de correos que ya existe en otra base (la de WishPOS). El
      SQL Server Agent Job que ya opera la revisa cada minuto y envía con
      sp_send_dbmail lo que tenga Enviar='Si' y Enviado='No'.

      NO se crea la tabla aquí: se referencia con un SYNONYM local, para que
      sp_CV_Visitas_Registrar inserte en `dbo.WM_Correo` sin acoplarse al
      nombre físico de la base. Solo hay que reapuntar el SYNONYM por entorno.

      >>> Local (este equipo): la base replicada se llama WISH.
      >>> Producción: reapuntar el SYNONYM a la base real de WishPOS (ajustar el
          nombre si difiere) -- NO hay que crear ninguna tabla WM_Correo.
   ----------------------------------------------------------------------------- */
IF OBJECT_ID('dbo.WM_Correo', 'SN') IS NOT NULL DROP SYNONYM dbo.WM_Correo;
GO
CREATE SYNONYM dbo.WM_Correo FOR WISH.dbo.WM_Correo;
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
CREATE PROCEDURE dbo.sp_CV_Visitas_ValidarAcceso
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
      AND FechaAcceso >= DATEADD(HOUR, -48, GETDATE());
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
CREATE PROCEDURE dbo.sp_CV_Visitas_MisVisitas
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
CREATE PROCEDURE dbo.sp_CV_Visitas_Actualizar
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
CREATE PROCEDURE dbo.sp_CV_Visitas_Cancelar
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
CREATE PROCEDURE dbo.sp_CV_Visitas_ActualizarFoto
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
CREATE PROCEDURE dbo.sp_CV_Visitas_ObtenerInfoFoto
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
CREATE PROCEDURE dbo.sp_CV_Configuracion_Obtener
AS
BEGIN
    SET NOCOUNT ON;
    SELECT Clave, Valor FROM dbo.CV_Configuracion ORDER BY Clave;
END
GO

CREATE PROCEDURE dbo.sp_CV_Configuracion_Actualizar
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

/* =============================================================================
   STORED PROCEDURES -- ASISTENCIA DE EMPLEADOS
   ============================================================================= */

/* -----------------------------------------------------------------------------
   sp_CV_Empleados_Listar
   Catálogo de empleados para la pantalla de administración (a futuro).
   @SoloActivos = 1 -> solo activos; 0 -> todos.
   ----------------------------------------------------------------------------- */
CREATE PROCEDURE dbo.sp_CV_Empleados_Listar
    @SoloActivos BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    SELECT ID, NumeroEmpleado, NumeroWishPOS, NombreCompleto, Tipo, CodigoAcceso, Activo
      FROM dbo.CV_Empleados
     WHERE (@SoloActivos = 0 OR Activo = 1)
     ORDER BY NombreCompleto;
END
GO

/* -----------------------------------------------------------------------------
   sp_CV_Empleados_GenerarCodigo
   Devuelve (OUTPUT) un código de 6 dígitos aleatorio y único entre TODOS los
   empleados (activos e inactivos, para no reciclar nunca uno vivo). Mismo
   patrón que el código de acceso de las visitas. Se usa desde las altas.
   ----------------------------------------------------------------------------- */
CREATE PROCEDURE dbo.sp_CV_Empleados_GenerarCodigo
    @Codigo CHAR(6) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    WHILE 1 = 1
    BEGIN
        SET @Codigo = RIGHT('000000' + CAST(ABS(CHECKSUM(NEWID())) % 1000000 AS VARCHAR(6)), 6);
        IF NOT EXISTS (SELECT 1 FROM dbo.CV_Empleados WHERE CodigoAcceso = @Codigo) BREAK;
    END
END
GO

/* -----------------------------------------------------------------------------
   sp_CV_Empleados_Guardar
   Alta/edición (upsert). @ID = 0 -> alta; >0 -> edición. El código de acceso
   NO se recibe: en el alta lo genera el sistema (6 dígitos); en la edición se
   conserva el que ya tiene. Devuelve Resultado (OK | NO_ENCONTRADO), el ID y
   el CodigoAcceso resultante.
   ----------------------------------------------------------------------------- */
CREATE PROCEDURE dbo.sp_CV_Empleados_Guardar
    @ID              INT,
    @NumeroEmpleado  NVARCHAR(20),
    @NumeroWishPOS   NVARCHAR(20)   = '',
    @NombreCompleto  NVARCHAR(150),
    @Tipo            NVARCHAR(20),
    @Activo          BIT            = 1
AS
BEGIN
    SET NOCOUNT ON;

    IF @ID = 0
    BEGIN
        DECLARE @Codigo CHAR(6);
        EXEC dbo.sp_CV_Empleados_GenerarCodigo @Codigo = @Codigo OUTPUT;
        INSERT INTO dbo.CV_Empleados (NumeroEmpleado, NumeroWishPOS, NombreCompleto, Tipo, CodigoAcceso, Activo)
        VALUES (@NumeroEmpleado, @NumeroWishPOS, @NombreCompleto, @Tipo, @Codigo, @Activo);
        SELECT N'OK' AS Resultado, CAST(SCOPE_IDENTITY() AS INT) AS ID, @Codigo AS CodigoAcceso;
        RETURN;
    END

    IF NOT EXISTS (SELECT 1 FROM dbo.CV_Empleados WHERE ID = @ID)
    BEGIN
        SELECT N'NO_ENCONTRADO' AS Resultado, 0 AS ID, N'' AS CodigoAcceso;
        RETURN;
    END

    UPDATE dbo.CV_Empleados
       SET NumeroEmpleado = @NumeroEmpleado,
           NumeroWishPOS  = @NumeroWishPOS,
           NombreCompleto = @NombreCompleto,
           Tipo           = @Tipo,
           Activo         = @Activo,
           ID_Fecha_Modificacion = GETDATE()
     WHERE ID = @ID;

    SELECT N'OK' AS Resultado, @ID AS ID,
           (SELECT CodigoAcceso FROM dbo.CV_Empleados WHERE ID = @ID) AS CodigoAcceso;
END
GO

/* -----------------------------------------------------------------------------
   sp_CV_Empleados_Alta  (PARA CARGA MANUAL / DESDE OTRO SISTEMA)
   Alta de UN empleado generando el código automáticamente. Pensado para
   llamarlo directo desde SSMS o desde un script que traiga al personal de
   otro sistema. Devuelve el ID y el CodigoAcceso generado.
     EXEC dbo.sp_CV_Empleados_Alta @NumeroEmpleado=N'1200', @NombreCompleto=N'Juan Pérez';
     EXEC dbo.sp_CV_Empleados_Alta @NumeroEmpleado=N'1201', @NombreCompleto=N'Ana Ruiz', @Tipo=N'Mensajero', @NumeroWishPOS=N'350';
   ----------------------------------------------------------------------------- */
CREATE PROCEDURE dbo.sp_CV_Empleados_Alta
    @NumeroEmpleado  NVARCHAR(20),
    @NombreCompleto  NVARCHAR(150),
    @Tipo            NVARCHAR(20)   = N'Empleado',
    @NumeroWishPOS   NVARCHAR(20)   = ''
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Codigo CHAR(6);
    EXEC dbo.sp_CV_Empleados_GenerarCodigo @Codigo = @Codigo OUTPUT;
    INSERT INTO dbo.CV_Empleados (NumeroEmpleado, NumeroWishPOS, NombreCompleto, Tipo, CodigoAcceso, Activo)
    VALUES (@NumeroEmpleado, @NumeroWishPOS, @NombreCompleto, @Tipo, @Codigo, 1);
    SELECT CAST(SCOPE_IDENTITY() AS INT) AS ID, @Codigo AS CodigoAcceso;
END
GO

/* -----------------------------------------------------------------------------
   sp_CV_Empleados_GenerarCodigosFaltantes  (PARA CARGA MASIVA)
   Opción más simple para traer muchos empleados de otro sistema:
     1) Inserta los renglones dejando el código en blanco, p.ej.:
          INSERT INTO dbo.CV_Empleados (NumeroEmpleado, NumeroWishPOS, NombreCompleto, Tipo)
          SELECT NumEmp, NumWish, Nombre, Tipo FROM <origen>;   -- CodigoAcceso queda '' por DEFAULT
     2) Corre este SP una vez: asigna un código único de 6 dígitos a cada
        empleado ACTIVO que aún no tenga (CodigoAcceso = '').
   Devuelve el padrón activo con su código ya asignado.
   ----------------------------------------------------------------------------- */
CREATE PROCEDURE dbo.sp_CV_Empleados_GenerarCodigosFaltantes
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @ID INT, @Codigo CHAR(6);
    WHILE EXISTS (SELECT 1 FROM dbo.CV_Empleados WHERE Activo = 1 AND CodigoAcceso = '')
    BEGIN
        SELECT TOP 1 @ID = ID FROM dbo.CV_Empleados WHERE Activo = 1 AND CodigoAcceso = '' ORDER BY ID;
        EXEC dbo.sp_CV_Empleados_GenerarCodigo @Codigo = @Codigo OUTPUT;
        UPDATE dbo.CV_Empleados SET CodigoAcceso = @Codigo WHERE ID = @ID;
    END
    SELECT ID, NumeroEmpleado, NumeroWishPOS, NombreCompleto, Tipo, CodigoAcceso
      FROM dbo.CV_Empleados WHERE Activo = 1 ORDER BY ID;
END
GO

/* -----------------------------------------------------------------------------
   sp_CV_Asistencia_BuscarPorCodigo
   El kiosko teclea el código; este SP valida contra CV_Empleados y regresa,
   en una sola fila, el empleado y el estado de HOY (las cuatro marcas, con
   centinela donde aún no hay hora). La capa de API traduce el centinela a null.
   Resultado: OK | NO_ENCONTRADO.
   ----------------------------------------------------------------------------- */
CREATE PROCEDURE dbo.sp_CV_Asistencia_BuscarPorCodigo
    @CodigoAcceso NVARCHAR(10)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @IDEmp INT, @Tipo NVARCHAR(20), @Nombre NVARCHAR(150),
            @NumEmp NVARCHAR(20), @NumWish NVARCHAR(20);

    SELECT @IDEmp = ID, @Tipo = Tipo, @Nombre = NombreCompleto,
           @NumEmp = NumeroEmpleado, @NumWish = NumeroWishPOS
      FROM dbo.CV_Empleados
     WHERE CodigoAcceso = @CodigoAcceso AND Activo = 1;

    IF @IDEmp IS NULL
    BEGIN
        SELECT N'NO_ENCONTRADO' AS Resultado;
        RETURN;
    END

    DECLARE @Hoy DATE = CAST(GETDATE() AS DATE);

    SELECT
        N'OK'           AS Resultado,
        @IDEmp          AS ID_Empleado,
        @NumEmp         AS NumeroEmpleado,
        @NumWish        AS NumeroWishPOS,
        @Nombre         AS NombreCompleto,
        @Tipo           AS Tipo,
        ISNULL(a.Entrada,       '1900-01-01 00:00:00') AS Entrada,
        ISNULL(a.SalidaComer,   '1900-01-01 00:00:00') AS SalidaComer,
        ISNULL(a.RegresoComida, '1900-01-01 00:00:00') AS RegresoComida,
        ISNULL(a.Salida,        '1900-01-01 00:00:00') AS Salida
      FROM (SELECT @Hoy AS f) x
      LEFT JOIN dbo.CV_Asistencia a
             ON a.ID_Empleado = @IDEmp AND a.Fecha = @Hoy;
END
GO

/* -----------------------------------------------------------------------------
   sp_CV_Asistencia_Registrar
   Registra UN movimiento del día para un empleado, validando la secuencia
   server-side (defensa igual que en el flujo de visitas). Crea la fila del día
   si no existe. @TipoMovimiento: Entrada | SalidaComer | RegresoComida | Salida.
   @FotoRuta solo aplica a la Entrada.
   Resultado: OK | NO_ENCONTRADO | MENSAJERO_SOLO_ENTRADA | YA_REGISTRADO |
              FUERA_DE_SECUENCIA | JORNADA_CERRADA | MOVIMIENTO_INVALIDO.
   Devuelve además la hora registrada (HoraMovimiento) cuando OK.
   ----------------------------------------------------------------------------- */
CREATE PROCEDURE dbo.sp_CV_Asistencia_Registrar
    @ID_Empleado     INT,
    @TipoMovimiento  NVARCHAR(20),
    @FotoRuta        NVARCHAR(260) = ''
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Centinela DATETIME = '1900-01-01 00:00:00';
    DECLARE @Ahora DATETIME = GETDATE();
    DECLARE @Hoy DATE = CAST(@Ahora AS DATE);
    DECLARE @Tipo NVARCHAR(20);

    SELECT @Tipo = Tipo FROM dbo.CV_Empleados WHERE ID = @ID_Empleado AND Activo = 1;
    IF @Tipo IS NULL
    BEGIN
        SELECT N'NO_ENCONTRADO' AS Resultado;
        RETURN;
    END

    IF @TipoMovimiento NOT IN (N'Entrada', N'SalidaComer', N'RegresoComida', N'Salida')
    BEGIN
        SELECT N'MOVIMIENTO_INVALIDO' AS Resultado;
        RETURN;
    END

    -- Mensajeros: solo Entrada
    IF @Tipo = N'Mensajero' AND @TipoMovimiento <> N'Entrada'
    BEGIN
        SELECT N'MENSAJERO_SOLO_ENTRADA' AS Resultado;
        RETURN;
    END

    -- Asegurar la fila del día
    IF NOT EXISTS (SELECT 1 FROM dbo.CV_Asistencia WHERE ID_Empleado = @ID_Empleado AND Fecha = @Hoy)
        INSERT INTO dbo.CV_Asistencia (ID_Empleado, Fecha, TipoEmpleado)
        VALUES (@ID_Empleado, @Hoy, @Tipo);

    DECLARE @Entrada DATETIME, @SalidaComer DATETIME, @RegresoComida DATETIME, @Salida DATETIME;
    SELECT @Entrada = Entrada, @SalidaComer = SalidaComer,
           @RegresoComida = RegresoComida, @Salida = Salida
      FROM dbo.CV_Asistencia WHERE ID_Empleado = @ID_Empleado AND Fecha = @Hoy;

    -- Jornada ya cerrada: no se registra nada más
    IF @Salida <> @Centinela
    BEGIN
        SELECT N'JORNADA_CERRADA' AS Resultado;
        RETURN;
    END

    IF @TipoMovimiento = N'Entrada'
    BEGIN
        IF @Entrada <> @Centinela BEGIN SELECT N'YA_REGISTRADO' AS Resultado; RETURN; END
        UPDATE dbo.CV_Asistencia
           SET Entrada = @Ahora, FotoRuta = @FotoRuta, ID_Fecha_Modificacion = @Ahora
         WHERE ID_Empleado = @ID_Empleado AND Fecha = @Hoy;
    END
    ELSE IF @TipoMovimiento = N'SalidaComer'
    BEGIN
        IF @Entrada = @Centinela BEGIN SELECT N'FUERA_DE_SECUENCIA' AS Resultado; RETURN; END
        IF @SalidaComer <> @Centinela BEGIN SELECT N'YA_REGISTRADO' AS Resultado; RETURN; END
        UPDATE dbo.CV_Asistencia
           SET SalidaComer = @Ahora, ID_Fecha_Modificacion = @Ahora
         WHERE ID_Empleado = @ID_Empleado AND Fecha = @Hoy;
    END
    ELSE IF @TipoMovimiento = N'RegresoComida'
    BEGIN
        IF @SalidaComer = @Centinela BEGIN SELECT N'FUERA_DE_SECUENCIA' AS Resultado; RETURN; END
        IF @RegresoComida <> @Centinela BEGIN SELECT N'YA_REGISTRADO' AS Resultado; RETURN; END
        UPDATE dbo.CV_Asistencia
           SET RegresoComida = @Ahora, ID_Fecha_Modificacion = @Ahora
         WHERE ID_Empleado = @ID_Empleado AND Fecha = @Hoy;
    END
    ELSE -- Salida (anticipada permitida: basta con tener Entrada)
    BEGIN
        IF @Entrada = @Centinela BEGIN SELECT N'FUERA_DE_SECUENCIA' AS Resultado; RETURN; END
        UPDATE dbo.CV_Asistencia
           SET Salida = @Ahora, ID_Fecha_Modificacion = @Ahora
         WHERE ID_Empleado = @ID_Empleado AND Fecha = @Hoy;
    END

    SELECT N'OK' AS Resultado, @Ahora AS HoraMovimiento;
END
GO

/* -----------------------------------------------------------------------------
   sp_CV_Asistencia_Reporte
   Reporte por rango de fechas (una fila por empleado por día).
   ----------------------------------------------------------------------------- */
CREATE PROCEDURE dbo.sp_CV_Asistencia_Reporte
    @Desde DATE,
    @Hasta DATE
AS
BEGIN
    SET NOCOUNT ON;
    SELECT a.Fecha, e.NumeroEmpleado, e.NombreCompleto, a.TipoEmpleado,
           a.Entrada, a.SalidaComer, a.RegresoComida, a.Salida
      FROM dbo.CV_Asistencia a
      JOIN dbo.CV_Empleados e ON e.ID = a.ID_Empleado
     WHERE a.Fecha >= @Desde AND a.Fecha <= @Hasta
     ORDER BY a.Fecha DESC, e.NombreCompleto;
END
GO
