using ControlVisitas.Api.Modelos;
using ControlVisitas.Api.Servicios;
using Microsoft.AspNetCore.Mvc;

namespace ControlVisitas.Api.Controllers;

[ApiController]
[Route("api/auth")]
public class AuthController(IWishPosAuthService authService) : ControllerBase
{
    [HttpPost("login")]
    public async Task<IActionResult> Login(LoginRequest datos)
    {
        var originIp = HttpContext.Connection.RemoteIpAddress?.MapToIPv4().ToString() ?? "0.0.0.0";
        var resultado = await authService.LoginAsync(datos.Password, originIp);
        return Ok(resultado);
    }
}
