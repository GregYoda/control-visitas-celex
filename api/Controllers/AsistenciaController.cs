using ControlVisitas.Api.Datos;
using ControlVisitas.Api.Modelos;
using ControlVisitas.Api.Servicios;
using Microsoft.AspNetCore.Mvc;

namespace ControlVisitas.Api.Controllers;

[ApiController]
[Route("api/asistencia")]
public class AsistenciaController(IAsistenciaRepositorio repositorio, IFotoService fotoService) : ControllerBase
{
    // El kiosko teclea el código y obtiene el empleado + su estado del día.
    [HttpGet("empleado/{codigo}")]
    public async Task<IActionResult> BuscarPorCodigo(string codigo)
    {
        var estado = await repositorio.BuscarPorCodigoAsync(codigo);
        return Ok(estado);
    }

    // Registra un movimiento. En la Entrada, si viene foto, se guarda en disco
    // antes de registrar; si el guardado falla, no se bloquea el registro
    // (mismo criterio que la foto de visitas).
    [HttpPost("registrar")]
    public async Task<IActionResult> Registrar(RegistrarMovimientoRequest datos)
    {
        var fotoRuta = "";
        if (datos.TipoMovimiento == "Entrada" && !string.IsNullOrEmpty(datos.FotoBase64))
        {
            try
            {
                fotoRuta = await fotoService.GuardarAsistenciaAsync(
                    datos.IdEmpleado, DateOnly.FromDateTime(DateTime.Today), datos.FotoBase64);
            }
            catch
            {
                fotoRuta = "";
            }
        }

        var resultado = await repositorio.RegistrarMovimientoAsync(datos.IdEmpleado, datos.TipoMovimiento, fotoRuta);
        return Ok(resultado);
    }

    [HttpGet("reporte")]
    public async Task<IActionResult> Reporte([FromQuery] DateOnly desde, [FromQuery] DateOnly hasta)
    {
        var filas = await repositorio.ReporteAsync(desde, hasta);
        return Ok(filas);
    }
}
