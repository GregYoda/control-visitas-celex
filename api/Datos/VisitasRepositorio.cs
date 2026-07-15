using System.Data;
using ControlVisitas.Api.Modelos;
using Microsoft.Data.SqlClient;

namespace ControlVisitas.Api.Datos;

public interface IVisitasRepositorio
{
    Task<VisitaRegistroResponse> RegistrarAsync(VisitaRegistroRequest datos);
    Task<ValidarAccesoResultado> ValidarAccesoAsync(ValidarAccesoRequest datos);
    Task<SalidaInfo?> BuscarPorCodigoSalidaAsync(string codigo);
    Task<ConfirmarSalidaResultado?> ConfirmarSalidaAsync(long id);
    Task<List<ReporteFila>> ReporteAsync(DateOnly fechaInicio, DateOnly fechaFin);
}

public class VisitasRepositorio(ISqlConnectionFactory conexionFactory) : IVisitasRepositorio
{
    public async Task<VisitaRegistroResponse> RegistrarAsync(VisitaRegistroRequest datos)
    {
        await using var conexion = conexionFactory.Crear();
        await using var comando = new SqlCommand("dbo.sp_CV_Visitas_Registrar", conexion) { CommandType = CommandType.StoredProcedure };

        comando.Parameters.AddWithValue("@Nombre", datos.Nombre);
        comando.Parameters.AddWithValue("@ApellidoPaterno", datos.ApellidoPaterno);
        comando.Parameters.AddWithValue("@ApellidoMaterno", datos.ApellidoMaterno);
        comando.Parameters.AddWithValue("@Correo", datos.Correo);
        comando.Parameters.AddWithValue("@Empresa", datos.Empresa);
        comando.Parameters.AddWithValue("@ID_Area", datos.IdArea);
        comando.Parameters.AddWithValue("@Motivo", datos.Motivo);
        comando.Parameters.AddWithValue("@Anfitrion", datos.Anfitrion);
        comando.Parameters.AddWithValue("@RegistradoPor", datos.RegistradoPor);
        comando.Parameters.Add("@FechaVisita", SqlDbType.Date).Value = datos.FechaVisita.ToDateTime(TimeOnly.MinValue);
        comando.Parameters.AddWithValue("@TraeAuto", datos.TraeAuto);
        comando.Parameters.AddWithValue("@Marca", (object?)datos.Marca ?? DBNull.Value);
        comando.Parameters.AddWithValue("@Modelo", (object?)datos.Modelo ?? DBNull.Value);
        comando.Parameters.AddWithValue("@Placas", (object?)datos.Placas ?? DBNull.Value);

        await conexion.OpenAsync();
        await using var lector = await comando.ExecuteReaderAsync();
        await lector.ReadAsync();
        return new VisitaRegistroResponse(
            Convert.ToInt64(lector["ID"]),
            lector.GetGuid(lector.GetOrdinal("UUID")));
    }

    public async Task<ValidarAccesoResultado> ValidarAccesoAsync(ValidarAccesoRequest datos)
    {
        await using var conexion = conexionFactory.Crear();
        await using var comando = new SqlCommand("dbo.sp_CV_Visitas_ValidarAcceso", conexion) { CommandType = CommandType.StoredProcedure };

        comando.Parameters.AddWithValue("@UUID", datos.Uuid);
        comando.Parameters.AddWithValue("@ApellidoTecleado", datos.ApellidoTecleado);
        comando.Parameters.AddWithValue("@FotoRuta", (object?)datos.FotoRuta ?? DBNull.Value);

        await conexion.OpenAsync();
        await using var lector = await comando.ExecuteReaderAsync();
        await lector.ReadAsync();

        var resultado = lector.GetString(lector.GetOrdinal("Resultado"));
        if (resultado == "OK")
        {
            var visita = new VisitaAccesoInfo(
                Convert.ToInt64(lector["ID"]),
                lector.GetString(lector.GetOrdinal("Nombre")),
                lector.GetString(lector.GetOrdinal("ApellidoPaterno")),
                lector.GetString(lector.GetOrdinal("ApellidoMaterno")),
                lector.GetString(lector.GetOrdinal("Empresa")),
                lector.GetString(lector.GetOrdinal("Motivo")),
                lector.GetString(lector.GetOrdinal("Anfitrion")),
                lector.GetString(lector.GetOrdinal("Area")),
                DateOnly.FromDateTime(lector.GetDateTime(lector.GetOrdinal("FechaVisita"))),
                lector.GetString(lector.GetOrdinal("CodigoSalida")),
                lector.GetDateTime(lector.GetOrdinal("FechaAcceso")));
            return new ValidarAccesoResultado(resultado, Visita: visita);
        }

        if (resultado == "FECHA_NO_COINCIDE")
        {
            var fechaVisita = DateOnly.FromDateTime(lector.GetDateTime(lector.GetOrdinal("FechaVisita")));
            return new ValidarAccesoResultado(resultado, FechaVisita: fechaVisita);
        }

        return new ValidarAccesoResultado(resultado);
    }

    public async Task<SalidaInfo?> BuscarPorCodigoSalidaAsync(string codigo)
    {
        await using var conexion = conexionFactory.Crear();
        await using var comando = new SqlCommand("dbo.sp_CV_Visitas_BuscarPorCodigoSalida", conexion) { CommandType = CommandType.StoredProcedure };
        comando.Parameters.AddWithValue("@Codigo", codigo);

        await conexion.OpenAsync();
        await using var lector = await comando.ExecuteReaderAsync();
        if (!await lector.ReadAsync()) return null;

        return new SalidaInfo(
            Convert.ToInt64(lector["ID"]),
            lector.GetString(lector.GetOrdinal("Nombre")),
            lector.GetString(lector.GetOrdinal("ApellidoPaterno")),
            lector.GetString(lector.GetOrdinal("ApellidoMaterno")),
            lector.GetString(lector.GetOrdinal("Empresa")),
            lector.GetString(lector.GetOrdinal("Anfitrion")),
            lector.GetDateTime(lector.GetOrdinal("FechaAcceso")),
            lector.IsDBNull(lector.GetOrdinal("FotoRuta")) ? null : lector.GetString(lector.GetOrdinal("FotoRuta")));
    }

    public async Task<ConfirmarSalidaResultado?> ConfirmarSalidaAsync(long id)
    {
        await using var conexion = conexionFactory.Crear();
        await using var comando = new SqlCommand("dbo.sp_CV_Visitas_ConfirmarSalida", conexion) { CommandType = CommandType.StoredProcedure };
        comando.Parameters.AddWithValue("@ID", id);

        await conexion.OpenAsync();
        await using var lector = await comando.ExecuteReaderAsync();
        if (!await lector.ReadAsync()) return null;

        return new ConfirmarSalidaResultado(
            lector.GetString(lector.GetOrdinal("Nombre")),
            lector.GetString(lector.GetOrdinal("ApellidoPaterno")),
            lector.GetString(lector.GetOrdinal("ApellidoMaterno")),
            lector.GetDateTime(lector.GetOrdinal("FechaAcceso")),
            lector.GetDateTime(lector.GetOrdinal("FechaSalida")),
            Convert.ToInt32(lector["MinutosEstancia"]));
    }

    public async Task<List<ReporteFila>> ReporteAsync(DateOnly fechaInicio, DateOnly fechaFin)
    {
        await using var conexion = conexionFactory.Crear();
        await using var comando = new SqlCommand("dbo.sp_CV_Visitas_Reporte", conexion) { CommandType = CommandType.StoredProcedure };
        comando.Parameters.Add("@FechaInicio", SqlDbType.Date).Value = fechaInicio.ToDateTime(TimeOnly.MinValue);
        comando.Parameters.Add("@FechaFin", SqlDbType.Date).Value = fechaFin.ToDateTime(TimeOnly.MinValue);

        await conexion.OpenAsync();
        await using var lector = await comando.ExecuteReaderAsync();

        var filas = new List<ReporteFila>();
        while (await lector.ReadAsync())
        {
            filas.Add(new ReporteFila(
                Convert.ToInt64(lector["ID"]),
                lector.GetString(lector.GetOrdinal("Nombre")),
                lector.GetString(lector.GetOrdinal("ApellidoPaterno")),
                lector.GetString(lector.GetOrdinal("ApellidoMaterno")),
                lector.GetString(lector.GetOrdinal("Empresa")),
                lector.GetString(lector.GetOrdinal("Area")),
                lector.GetString(lector.GetOrdinal("Anfitrion")),
                lector.GetString(lector.GetOrdinal("Motivo")),
                lector.GetString(lector.GetOrdinal("Estado")),
                DateOnly.FromDateTime(lector.GetDateTime(lector.GetOrdinal("FechaVisita"))),
                lector.GetDateTime(lector.GetOrdinal("FechaRegistro")),
                lector.IsDBNull(lector.GetOrdinal("FechaAcceso")) ? null : lector.GetDateTime(lector.GetOrdinal("FechaAcceso")),
                lector.IsDBNull(lector.GetOrdinal("CodigoSalida")) ? null : lector.GetString(lector.GetOrdinal("CodigoSalida")),
                lector.IsDBNull(lector.GetOrdinal("FechaSalida")) ? null : lector.GetDateTime(lector.GetOrdinal("FechaSalida")),
                lector.IsDBNull(lector.GetOrdinal("MinutosEstancia")) ? null : Convert.ToInt32(lector["MinutosEstancia"]),
                lector.IsDBNull(lector.GetOrdinal("FotoRuta")) ? null : lector.GetString(lector.GetOrdinal("FotoRuta"))));
        }
        return filas;
    }
}
