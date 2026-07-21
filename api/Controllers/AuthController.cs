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

        // El checkbox "Visita VIP" solo se habilita para los Usuario_ID dados de
        // alta en CV_Configuracion.UsuariosVIP (lista separada por comas). Se
        // resuelve aquí (no en WishPosAuthService) porque depende de nuestra
        // configuración local, no de la respuesta de WishPOS.
        if (resultado.Autorizado && resultado.UsuarioId is int usuarioId)
        {
            var listaVip = await configuracionRepositorio.ObtenerValorAsync("UsuariosVIP", "");
            var puedeVip = listaVip
                .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
                .Any(id => int.TryParse(id, out var n) && n == usuarioId);
            resultado = resultado with { PuedeVIP = puedeVip };
        }

        return Ok(resultado);
    }
}
