using ControlVisitas.Api.Modelos;
using Microsoft.Data.SqlClient;

namespace ControlVisitas.Api.Datos;

public interface IAreasRepositorio
{
    Task<List<Area>> ObtenerActivasAsync();
}

public class AreasRepositorio(ISqlConnectionFactory conexionFactory) : IAreasRepositorio
{
    public async Task<List<Area>> ObtenerActivasAsync()
    {
        const string sql = "SELECT ID, Nombre, Activo, UUID FROM dbo.CV_Areas WHERE Activo = 1 ORDER BY Nombre;";

        await using var conexion = conexionFactory.Crear();
        await using var comando = new SqlCommand(sql, conexion);
        await conexion.OpenAsync();
        await using var lector = await comando.ExecuteReaderAsync();

        var areas = new List<Area>();
        while (await lector.ReadAsync())
        {
            areas.Add(new Area(
                lector.GetInt32(0),
                lector.GetString(1),
                lector.GetBoolean(2),
                lector.GetGuid(3)));
        }
        return areas;
    }
}
