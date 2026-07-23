namespace ControlVisitas.Api.Modelos;

public record LoginRequest(string Password);

public record LoginResponse(bool Autorizado, string Mensaje, string? Usuario, string? Nombre, int? UsuarioId, bool PuedeConfigurar = false, bool PuedeVIP = false, bool IniciarEnKiosko = false, bool EsReclutador = false);
