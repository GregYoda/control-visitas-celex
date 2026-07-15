using Microsoft.Data.SqlClient;

namespace ControlVisitas.Api.Datos;

public interface ISqlConnectionFactory
{
    SqlConnection Crear();
}

public class SqlConnectionFactory(IConfiguration configuracion) : ISqlConnectionFactory
{
    private readonly string _cadenaConexion =
        configuracion.GetConnectionString("ControlVisitas")
        ?? throw new InvalidOperationException("Falta la cadena de conexión 'ControlVisitas' en la configuración.");

    public SqlConnection Crear() => new(_cadenaConexion);
}
