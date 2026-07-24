namespace ControlVisitas.Api.Modelos;

// ---- Empleados (padrón) ----
public record Empleado(
    int Id,
    string NumeroEmpleado,
    string NumeroWishPos,
    string NombreCompleto,
    string Tipo,          // Empleado | Mensajero
    string CodigoAcceso,
    bool Activo);

public record EmpleadoGuardarRequest(
    int Id,               // 0 = alta; >0 = edición
    string NumeroEmpleado,
    string? NumeroWishPos,
    string NombreCompleto,
    string Tipo,
    string CodigoAcceso,
    bool Activo);

public record EmpleadoGuardarResultado(string Resultado, int Id);  // OK | CODIGO_DUPLICADO | NO_ENCONTRADO

// ---- Asistencia (kiosko) ----
// Estado del día del empleado. Las horas van en null cuando aún no se marcan
// (la base guarda el centinela '1900-01-01'; la API lo traduce a null).
public record EmpleadoEstado(
    string Resultado,     // OK | NO_ENCONTRADO
    int IdEmpleado = 0,
    string NumeroEmpleado = "",
    string NumeroWishPos = "",
    string NombreCompleto = "",
    string Tipo = "",
    DateTime? Entrada = null,
    DateTime? SalidaComer = null,
    DateTime? RegresoComida = null,
    DateTime? Salida = null);

public record RegistrarMovimientoRequest(
    int IdEmpleado,
    string TipoMovimiento,   // Entrada | SalidaComer | RegresoComida | Salida
    string? FotoBase64);     // solo aplica a la Entrada

// Resultado: OK | NO_ENCONTRADO | MENSAJERO_SOLO_ENTRADA | YA_REGISTRADO |
//            FUERA_DE_SECUENCIA | JORNADA_CERRADA | MOVIMIENTO_INVALIDO
public record RegistrarMovimientoResultado(string Resultado, DateTime? HoraMovimiento = null);

public record AsistenciaReporteFila(
    DateOnly Fecha,
    string NumeroEmpleado,
    string NombreCompleto,
    string TipoEmpleado,
    DateTime? Entrada,
    DateTime? SalidaComer,
    DateTime? RegresoComida,
    DateTime? Salida);
