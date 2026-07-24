using ControlVisitas.Api.Datos;
using ControlVisitas.Api.Modelos;
using Microsoft.AspNetCore.Mvc;

namespace ControlVisitas.Api.Controllers;

// Padrón de empleados/mensajeros. Base para la pantalla de administración
// (a futuro); hoy expone listar y guardar (alta/edición).
[ApiController]
[Route("api/empleados")]
public class EmpleadosController(IAsistenciaRepositorio repositorio) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> Listar([FromQuery] bool soloActivos = true)
    {
        var empleados = await repositorio.ListarEmpleadosAsync(soloActivos);
        return Ok(empleados);
    }

    [HttpPost]
    public async Task<IActionResult> Guardar(EmpleadoGuardarRequest datos)
    {
        var resultado = await repositorio.GuardarEmpleadoAsync(datos);
        return Ok(resultado);
    }
}
