using ControlVisitas.Api.Datos;
using ControlVisitas.Api.Modelos;
using Microsoft.AspNetCore.Mvc;

namespace ControlVisitas.Api.Controllers;

[ApiController]
[Route("api/configuracion")]
public class ConfiguracionController(IConfiguracionRepositorio repositorio) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> Get()
    {
        var items = await repositorio.ObtenerAsync();
        return Ok(items);
    }

    [HttpPut("{clave}")]
    public async Task<IActionResult> Actualizar(string clave, ActualizarConfiguracionRequest datos)
    {
        await repositorio.ActualizarAsync(clave, datos.Valor);
        return Ok(new ConfiguracionItem(clave, datos.Valor));
    }
}
