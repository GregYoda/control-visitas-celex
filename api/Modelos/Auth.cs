namespace ControlVisitas.Api.Modelos;

public record LoginRequest(string Password);

public record LoginResponse(bool Autorizado, string Mensaje, string? Usuario, string? Nombre);
