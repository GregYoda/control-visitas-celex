using ControlVisitas.Api.Datos;
using Microsoft.AspNetCore.Mvc;

namespace ControlVisitas.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
public class AreasController(IAreasRepositorio repositorio) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> Get()
    {
        var areas = await repositorio.ObtenerActivasAsync();
        return Ok(areas);
    }
}
