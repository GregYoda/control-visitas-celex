using ControlVisitas.Api.Datos;
using ControlVisitas.Api.Modelos;
using ControlVisitas.Api.Servicios;
using Microsoft.AspNetCore.Mvc;

namespace ControlVisitas.Api.Controllers;

[ApiController]
[Route("api/auth")]
public class AuthController(IWishPosAuthService authService, IConfiguracionRepositorio configuracionRepositorio) : ControllerBase
{
    [HttpPost("login")]
    public async Task<IActionResult> Login(LoginRequest datos)
    {
        var originIp = HttpContext.Connection.RemoteIpAddress?.MapToIPv4().ToString() ?? "0.0.0.0";
        var resultado = await authService.LoginAsync(datos.Password, originIp);

        // Algunas capacidades dependen de listas de Usuario_ID en nuestra
        // configuración local (no de WishPOS), por eso se resuelven aquí:
        //  - UsuariosVIP: pueden marcar una visita como VIP.
        //  - UsuariosKiosko: al entrar van directo al kiosko (modo caseta).
        // Ambas son listas de IDs separados por comas.
        if (resultado.Autorizado && resultado.UsuarioId is int usuarioId)
        {
            resultado = resultado with
            {
                PuedeVIP = await EstaEnListaAsync("UsuariosVIP", usuarioId),
                IniciarEnKiosko = await EstaEnListaAsync("UsuariosKiosko", usuarioId)
            };
        }

        return Ok(resultado);
    }

    private async Task<bool> EstaEnListaAsync(string clave, int usuarioId)
    {
        var lista = await configuracionRepositorio.ObtenerValorAsync(clave, "");
        return lista
            .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Any(id => int.TryParse(id, out var n) && n == usuarioId);
    }
}
