using ControlVisitas.Api.Datos;
using ControlVisitas.Api.Modelos;
using Microsoft.AspNetCore.Mvc;

namespace ControlVisitas.Api.Controllers;

[ApiController]
[Route("api/visitas")]
public class VisitasController(IVisitasRepositorio repositorio) : ControllerBase
{
    [HttpPost]
    public async Task<IActionResult> Registrar(VisitaRegistroRequest datos)
    {
        var resultado = await repositorio.RegistrarAsync(datos);
        return Ok(resultado);
    }

    [HttpPost("validar-acceso")]
    public async Task<IActionResult> ValidarAcceso(ValidarAccesoRequest datos)
    {
        var resultado = await repositorio.ValidarAccesoAsync(datos);
        return Ok(resultado);
    }

    [HttpGet("salida/{codigo}")]
    public async Task<IActionResult> BuscarPorCodigoSalida(string codigo)
    {
        var salida = await repositorio.BuscarPorCodigoSalidaAsync(codigo);
        return salida is null ? NotFound() : Ok(salida);
    }

    [HttpPost("salida/{id:long}/confirmar")]
    public async Task<IActionResult> ConfirmarSalida(long id)
    {
        var resultado = await repositorio.ConfirmarSalidaAsync(id);
        return resultado is null ? NotFound() : Ok(resultado);
    }

    [HttpGet("mias")]
    public async Task<IActionResult> Mias([FromQuery] string registradoPor)
    {
        var mias = await repositorio.MisVisitasAsync(registradoPor);
        return Ok(mias);
    }

    [HttpPut("{id:long}")]
    public async Task<IActionResult> Actualizar(long id, VisitaActualizarRequest datos)
    {
        var resultado = await repositorio.ActualizarAsync(id, datos);
        return Ok(resultado);
    }
}
