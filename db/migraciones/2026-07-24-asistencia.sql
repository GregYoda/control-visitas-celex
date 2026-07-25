/* =============================================================================
   MIGRACION -- ASISTENCIA DE EMPLEADOS  (Control de Visitas, Celex)
   Agrega a una base YA INSTALADA las tablas y procedimientos del modulo de
   asistencia (empleados/mensajeros). Es idempotente: se puede correr varias
   veces sin dano (crea lo que falte y refresca los SP con CREATE OR ALTER).
   >>> Correr con codepage UTF-8:
       sqlcmd -S SERVIDOR -d ControlVisitas_Celex -f i:65001 -i este-archivo.sql
   >>> NO inserta empleados de ejemplo: el padron se carga aparte
       (ver sp_CV_Empleados_Alta / sp_CV_Empleados_GenerarCodigosFaltantes).
   ============================================================================= */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* 1) Tabla CV_Empleados (padron) --------------------------------------------- */
IF OBJECT_ID(N'dbo.CV_Empleados','U') IS NULL
CREATE TABLE dbo.CV_Empleados (
    ID                      INT IDENTITY(1,1)   NOT NULL,
    UUID                    UNIQUEIDENTIFIER    NOT NULL DEFAULT (NEWID()),
    NumeroEmpleado          NVARCHAR(20)        NOT NULL DEFAULT (''),
    NumeroWishPOS           NVARCHAR(20)        NOT NULL DEFAULT (''),
    NombreCompleto          NVARCHAR(150)       NOT NULL,
    Tipo                    NVARCHAR(20)        NOT NULL DEFAULT (N'Empleado'),
    CodigoAcceso            CHAR(6)             NOT NULL DEFAULT (''),  -- 6 digitos, lo GENERA el sistema
    Activo                  BIT                 NOT NULL DEFAULT (1),
    FechaRegistro           DATETIME            NOT NULL DEFAULT (GETDATE()),
    ID_Fecha_Modificacion   DATETIME            NOT NULL DEFAULT ('1900-01-01 00:00:00'),
    CONSTRAINT PK_CV_Empleados PRIMARY KEY CLUSTERED (ID),
    CONSTRAINT CK_CV_Empleados_Tipo CHECK (Tipo IN (N'Empleado', N'Mensajero'))
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UX_CV_Empleados_Codigo' AND object_id = OBJECT_ID(N'dbo.CV_Empleados'))
CREATE UNIQUE INDEX UX_CV_Empleados_Codigo ON dbo.CV_Empleados(CodigoAcceso) WHERE Activo = 1 AND CodigoAcceso <> '';
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UX_CV_Empleados_UUID' AND object_id = OBJECT_ID(N'dbo.CV_Empleados'))
CREATE UNIQUE INDEX UX_CV_Empleados_UUID ON dbo.CV_Empleados(UUID);
GO

/* 2) Tabla CV_Asistencia (una fila por empleado por dia) --------------------- */
IF OBJECT_ID(N'dbo.CV_Asistencia','U') IS NULL
CREATE TABLE dbo.CV_Asistencia (
    ID                      BIGINT IDENTITY(1,1)    NOT NULL,
    ID_Empleado             INT                     NOT NULL,
    Fecha                   DATE                    NOT NULL,
    Entrada                 DATETIME                NOT NULL DEFAULT ('1900-01-01 00:00:00'),
    SalidaComer             DATETIME                NOT NULL DEFAULT ('1900-01-01 00:00:00'),
    RegresoComida           DATETIME                NOT NULL DEFAULT ('1900-01-01 00:00:00'),
    Salida                  DATETIME                NOT NULL DEFAULT ('1900-01-01 00:00:00'),
    FotoRuta                NVARCHAR(260)           NOT NULL DEFAULT (''),
    TipoEmpleado            NVARCHAR(20)            NOT NULL DEFAULT (N'Empleado'),
    ID_Fecha_Modificacion   DATETIME                NOT NULL DEFAULT ('1900-01-01 00:00:00'),
    CONSTRAINT PK_CV_Asistencia PRIMARY KEY CLUSTERED (ID),
    CONSTRAINT FK_CV_Asistencia_Empleado FOREIGN KEY (ID_Empleado) REFERENCES dbo.CV_Empleados(ID)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UX_CV_Asistencia_EmpFecha' AND object_id = OBJECT_ID(N'dbo.CV_Asistencia'))
CREATE UNIQUE INDEX UX_CV_Asistencia_EmpFecha ON dbo.CV_Asistencia(ID_Empleado, Fecha);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_CV_Asistencia_Fecha' AND object_id = OBJECT_ID(N'dbo.CV_Asistencia'))
CREATE INDEX IX_CV_Asistencia_Fecha ON dbo.CV_Asistencia(Fecha);
GO

/* =============================================================================
   3) Procedimientos de asistencia (CREATE OR ALTER; seguro re-ejecutar)
   ============================================================================= */

/* =============================================================================
   STORED PROCEDURES -- ASISTENCIA DE EMPLEADOS
   ============================================================================= */

/* -----------------------------------------------------------------------------
   sp_CV_Empleados_Listar
   Catálogo de empleados para la pantalla de administración (a futuro).
   @SoloActivos = 1 -> solo activos; 0 -> todos.
   ----------------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.sp_CV_Empleados_Listar
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
CREATE OR ALTER PROCEDURE dbo.sp_CV_Empleados_GenerarCodigo
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
CREATE OR ALTER PROCEDURE dbo.sp_CV_Empleados_Guardar
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
CREATE OR ALTER PROCEDURE dbo.sp_CV_Empleados_Alta
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
CREATE OR ALTER PROCEDURE dbo.sp_CV_Empleados_GenerarCodigosFaltantes
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
CREATE OR ALTER PROCEDURE dbo.sp_CV_Asistencia_BuscarPorCodigo
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
CREATE OR ALTER PROCEDURE dbo.sp_CV_Asistencia_Registrar
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
CREATE OR ALTER PROCEDURE dbo.sp_CV_Asistencia_Reporte
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
