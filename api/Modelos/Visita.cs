namespace ControlVisitas.Api.Modelos;

public record VisitaRegistroRequest(
    string Nombre,
    string ApellidoPaterno,
    string ApellidoMaterno,
    string Correo,
    string Empresa,
    int IdArea,
    string Motivo,
    string Anfitrion,
    string RegistradoPor,
    int? IdUsuario,
    DateOnly FechaVisita,
    bool TraeAuto,
    string? Marca,
    string? Modelo,
    string? Placas);

public record VisitaRegistroResponse(long Id, Guid Uuid);

public record ValidarAccesoRequest(Guid Uuid, string ApellidoTecleado, string? FotoRuta);

public record VisitaAccesoInfo(
    long Id,
    string Nombre,
    string ApellidoPaterno,
    string ApellidoMaterno,
    string Empresa,
    string Motivo,
    string Anfitrion,
    string Area,
    DateOnly FechaVisita,
    string CodigoSalida,
    DateTime FechaAcceso);

public record ValidarAccesoResultado(string Resultado, VisitaAccesoInfo? Visita = null, DateOnly? FechaVisita = null);

public record SalidaInfo(
    long Id,
    string Nombre,
    string ApellidoPaterno,
    string ApellidoMaterno,
    string Empresa,
    string Anfitrion,
    DateTime FechaAcceso,
    string? FotoRuta);

public record ConfirmarSalidaResultado(
    string Nombre,
    string ApellidoPaterno,
    string ApellidoMaterno,
    DateTime FechaAcceso,
    DateTime FechaSalida,
    int MinutosEstancia);

public record ReporteFila(
    long Id,
    string Nombre,
    string ApellidoPaterno,
    string ApellidoMaterno,
    string Empresa,
    string Area,
    string Anfitrion,
    string Motivo,
    string Estado,
    DateOnly FechaVisita,
    DateTime FechaRegistro,
    DateTime? FechaAcceso,
    string? CodigoSalida,
    DateTime? FechaSalida,
    int? MinutosEstancia,
    string? FotoRuta);

public record MiVisita(
    long Id,
    Guid Uuid,
    string Nombre,
    string ApellidoPaterno,
    string ApellidoMaterno,
    string Correo,
    string Empresa,
    int IdArea,
    string Area,
    string Motivo,
    string Anfitrion,
    DateOnly FechaVisita,
    bool TraeAuto,
    string? Marca,
    string? Modelo,
    string? Placas,
    string Estado,
    string Status,
    DateTime FechaRegistro,
    DateTime? FechaAcceso,
    string? FotoRuta);

public record VisitaActualizarRequest(
    string Nombre,
    string ApellidoPaterno,
    string ApellidoMaterno,
    string Correo,
    string Empresa,
    int IdArea,
    string Motivo,
    string Anfitrion,
    DateOnly FechaVisita,
    bool TraeAuto,
    string? Marca,
    string? Modelo,
    string? Placas);

public record ActualizarResultado(string Resultado);
