using System.Data;
using ControlVisitas.Api.Modelos;
using Microsoft.Data.SqlClient;

namespace ControlVisitas.Api.Datos;

public interface IAsistenciaRepositorio
{
    // Empleados (padrón)
    Task<List<Empleado>> ListarEmpleadosAsync(bool soloActivos);
    Task<EmpleadoGuardarResultado> GuardarEmpleadoAsync(EmpleadoGuardarRequest datos);

    // Asistencia (kiosko)
    Task<EmpleadoEstado> BuscarPorCodigoAsync(string codigo);
    Task<RegistrarMovimientoResultado> RegistrarMovimientoAsync(int idEmpleado, string tipoMovimiento, string fotoRuta);
    Task<List<AsistenciaReporteFila>> ReporteAsync(DateOnly desde, DateOnly hasta);
}

public class AsistenciaRepositorio(ISqlConnectionFactory conexionFactory) : IAsistenciaRepositorio
{
    // Misma convención que VisitasRepositorio: la base no guarda NULL, usa el
    // centinela '1900-01-01' para fechas; aquí se traduce de vuelta a null.
    private static readonly DateTime FechaVacia = new(1900, 1, 1);
    private static DateTime? NullSiVacia(DateTime valor) => valor == FechaVacia ? null : valor;

    public async Task<List<Empleado>> ListarEmpleadosAsync(bool soloActivos)
    {
        await using var conexion = conexionFactory.Crear();
        await using var comando = new SqlCommand("dbo.sp_CV_Empleados_Listar", conexion) { CommandType = CommandType.StoredProcedure };
        comando.Parameters.AddWithValue("@SoloActivos", soloActivos);

        await conexion.OpenAsync();
        await using var lector = await comando.ExecuteReaderAsync();

        var lista = new List<Empleado>();
        while (await lector.ReadAsync())
        {
            lista.Add(new Empleado(
                lector.GetInt32(lector.GetOrdinal("ID")),
                lector.GetString(lector.GetOrdinal("NumeroEmpleado")),
                lector.GetString(lector.GetOrdinal("NumeroWishPOS")),
                lector.GetString(lector.GetOrdinal("NombreCompleto")),
                lector.GetString(lector.GetOrdinal("Tipo")),
                lector.GetString(lector.GetOrdinal("CodigoAcceso")),
                lector.GetBoolean(lector.GetOrdinal("Activo"))));
        }
        return lista;
    }

    public async Task<EmpleadoGuardarResultado> GuardarEmpleadoAsync(EmpleadoGuardarRequest datos)
    {
        await using var conexion = conexionFactory.Crear();
        await using var comando = new SqlCommand("dbo.sp_CV_Empleados_Guardar", conexion) { CommandType = CommandType.StoredProcedure };
        comando.Parameters.AddWithValue("@ID", datos.Id);
        comando.Parameters.AddWithValue("@NumeroEmpleado", datos.NumeroEmpleado);
        comando.Parameters.AddWithValue("@NumeroWishPOS", datos.NumeroWishPos ?? "");
        comando.Parameters.AddWithValue("@NombreCompleto", datos.NombreCompleto);
        comando.Parameters.AddWithValue("@Tipo", datos.Tipo);
        comando.Parameters.AddWithValue("@Activo", datos.Activo);

        await conexion.OpenAsync();
        await using var lector = await comando.ExecuteReaderAsync();
        await lector.ReadAsync();
        return new EmpleadoGuardarResultado(
            lector.GetString(lector.GetOrdinal("Resultado")),
            lector.GetInt32(lector.GetOrdinal("ID")),
            lector.GetString(lector.GetOrdinal("CodigoAcceso")));
    }

    public async Task<EmpleadoEstado> BuscarPorCodigoAsync(string codigo)
    {
        await using var conexion = conexionFactory.Crear();
        await using var comando = new SqlCommand("dbo.sp_CV_Asistencia_BuscarPorCodigo", conexion) { CommandType = CommandType.StoredProcedure };
        comando.Parameters.AddWithValue("@CodigoAcceso", codigo);

        await conexion.OpenAsync();
        await using var lector = await comando.ExecuteReaderAsync();
        if (!await lector.ReadAsync())
            return new EmpleadoEstado("NO_ENCONTRADO");

        var resultado = lector.GetString(lector.GetOrdinal("Resultado"));
        if (resultado != "OK")
            return new EmpleadoEstado(resultado);

        return new EmpleadoEstado(
            "OK",
            lector.GetInt32(lector.GetOrdinal("ID_Empleado")),
            lector.GetString(lector.GetOrdinal("NumeroEmpleado")),
            lector.GetString(lector.GetOrdinal("NumeroWishPOS")),
            lector.GetString(lector.GetOrdinal("NombreCompleto")),
            lector.GetString(lector.GetOrdinal("Tipo")),
            NullSiVacia(lector.GetDateTime(lector.GetOrdinal("Entrada"))),
            NullSiVacia(lector.GetDateTime(lector.GetOrdinal("SalidaComer"))),
            NullSiVacia(lector.GetDateTime(lector.GetOrdinal("RegresoComida"))),
            NullSiVacia(lector.GetDateTime(lector.GetOrdinal("Salida"))));
    }

    public async Task<RegistrarMovimientoResultado> RegistrarMovimientoAsync(int idEmpleado, string tipoMovimiento, string fotoRuta)
    {
        await using var conexion = conexionFactory.Crear();
        await using var comando = new SqlCommand("dbo.sp_CV_Asistencia_Registrar", conexion) { CommandType = CommandType.StoredProcedure };
        comando.Parameters.AddWithValue("@ID_Empleado", idEmpleado);
        comando.Parameters.AddWithValue("@TipoMovimiento", tipoMovimiento);
        comando.Parameters.AddWithValue("@FotoRuta", fotoRuta ?? "");

        await conexion.OpenAsync();
        await using var lector = await comando.ExecuteReaderAsync();
        await lector.ReadAsync();

        var resultado = lector.GetString(lector.GetOrdinal("Resultado"));
        DateTime? hora = null;
        if (resultado == "OK")
        {
            var ordinalHora = lector.GetOrdinal("HoraMovimiento");
            if (!lector.IsDBNull(ordinalHora))
                hora = lector.GetDateTime(ordinalHora);
        }
        return new RegistrarMovimientoResultado(resultado, hora);
    }

    public async Task<List<AsistenciaReporteFila>> ReporteAsync(DateOnly desde, DateOnly hasta)
    {
        await using var conexion = conexionFactory.Crear();
        await using var comando = new SqlCommand("dbo.sp_CV_Asistencia_Reporte", conexion) { CommandType = CommandType.StoredProcedure };
        comando.Parameters.Add("@Desde", SqlDbType.Date).Value = desde.ToDateTime(TimeOnly.MinValue);
        comando.Parameters.Add("@Hasta", SqlDbType.Date).Value = hasta.ToDateTime(TimeOnly.MinValue);

        await conexion.OpenAsync();
        await using var lector = await comando.ExecuteReaderAsync();

        var lista = new List<AsistenciaReporteFila>();
        while (await lector.ReadAsync())
        {
            lista.Add(new AsistenciaReporteFila(
                DateOnly.FromDateTime(lector.GetDateTime(lector.GetOrdinal("Fecha"))),
                lector.GetString(lector.GetOrdinal("NumeroEmpleado")),
                lector.GetString(lector.GetOrdinal("NombreCompleto")),
                lector.GetString(lector.GetOrdinal("TipoEmpleado")),
                NullSiVacia(lector.GetDateTime(lector.GetOrdinal("Entrada"))),
                NullSiVacia(lector.GetDateTime(lector.GetOrdinal("SalidaComer"))),
                NullSiVacia(lector.GetDateTime(lector.GetOrdinal("RegresoComida"))),
                NullSiVacia(lector.GetDateTime(lector.GetOrdinal("Salida")))));
        }
        return lista;
    }
}
