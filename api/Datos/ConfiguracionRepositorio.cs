using System.Data;
using ControlVisitas.Api.Modelos;
using Microsoft.Data.SqlClient;

namespace ControlVisitas.Api.Datos;

public interface IConfiguracionRepositorio
{
    Task<List<ConfiguracionItem>> ObtenerAsync();
    Task<string> ObtenerValorAsync(string clave, string valorPorDefecto);
    Task ActualizarAsync(string clave, string valor);
}

public class ConfiguracionRepositorio(ISqlConnectionFactory conexionFactory) : IConfiguracionRepositorio
{
    public async Task<List<ConfiguracionItem>> ObtenerAsync()
    {
        await using var conexion = conexionFactory.Crear();
        await using var comando = new SqlCommand("dbo.sp_CV_Configuracion_Obtener", conexion) { CommandType = CommandType.StoredProcedure };

        await conexion.OpenAsync();
        await using var lector = await comando.ExecuteReaderAsync();

        var items = new List<ConfiguracionItem>();
        while (await lector.ReadAsync())
        {
            items.Add(new ConfiguracionItem(
                lector.GetString(lector.GetOrdinal("Clave")),
                lector.GetString(lector.GetOrdinal("Valor"))));
        }
        return items;
    }

    public async Task<string> ObtenerValorAsync(string clave, string valorPorDefecto)
    {
        var items = await ObtenerAsync();
        var item = items.FirstOrDefault(i => i.Clave == clave);
        return string.IsNullOrEmpty(item?.Valor) ? valorPorDefecto : item.Valor;
    }

    public async Task ActualizarAsync(string clave, string valor)
    {
        await using var conexion = conexionFactory.Crear();
        await using var comando = new SqlCommand("dbo.sp_CV_Configuracion_Actualizar", conexion) { CommandType = CommandType.StoredProcedure };
        comando.Parameters.AddWithValue("@Clave", clave);
        comando.Parameters.AddWithValue("@Valor", valor);

        await conexion.OpenAsync();
        await comando.ExecuteNonQueryAsync();
    }
}
