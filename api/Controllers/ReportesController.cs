using ControlVisitas.Api.Datos;
using Microsoft.AspNetCore.Mvc;

namespace ControlVisitas.Api.Controllers;

[ApiController]
[Route("api/reportes")]
public class ReportesController(IVisitasRepositorio repositorio) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> Get([FromQuery] DateOnly fechaInicio, [FromQuery] DateOnly fechaFin)
    {
        var filas = await repositorio.ReporteAsync(fechaInicio, fechaFin);
        return Ok(filas);
    }
}
