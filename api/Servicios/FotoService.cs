using ControlVisitas.Api.Datos;

namespace ControlVisitas.Api.Servicios;

public interface IFotoService
{
    Task<string> GuardarAsync(long id, string fotoBase64);
    Task<string?> ObtenerRutaFisicaAsync(long id);
    Task<string> GuardarAsistenciaAsync(int idEmpleado, DateOnly fecha, string fotoBase64);
}

public class FotoService(IConfiguracionRepositorio configuracionRepositorio, IVisitasRepositorio visitasRepositorio) : IFotoService
{
    private const string RutaPorDefecto = @"C:\Control de Visitas\Fotos";
    private const string PrefijoPorDefecto = "CV";
    private const string DigitosPorDefecto = "10";

    public async Task<string> GuardarAsync(long id, string fotoBase64)
    {
        var info = await visitasRepositorio.ObtenerInfoFotoAsync(id)
            ?? throw new InvalidOperationException($"No existe la visita {id} para guardar su foto.");
        var rutaCompleta = await ConstruirRutaAsync(id, info);
        Directory.CreateDirectory(Path.GetDirectoryName(rutaCompleta)!);

        await File.WriteAllBytesAsync(rutaCompleta, DecodificarBase64(fotoBase64));
        return rutaCompleta;
    }

    // Foto tomada al registrar la ENTRADA de un empleado en el kiosko de
    // asistencia. Ruta: <RutaFotos>/<Año>/<Mes>/Asistencia/<Prefijo>ASIS_<idEmpleado>_<yyyyMMdd>.jpg
    // (una foto por empleado por día, igual que la fila de CV_Asistencia).
    public async Task<string> GuardarAsistenciaAsync(int idEmpleado, DateOnly fecha, string fotoBase64)
    {
        var ruta = await configuracionRepositorio.ObtenerValorAsync("RutaFotos", RutaPorDefecto);
        var prefijo = await configuracionRepositorio.ObtenerValorAsync("PrefijoFoto", PrefijoPorDefecto);

        var anio = fecha.Year.ToString("D4");
        var mes = fecha.Month.ToString("D2");
        var nombreArchivo = $"{prefijo}ASIS_{idEmpleado}_{fecha:yyyyMMdd}.jpg";
        var rutaCompleta = Path.Combine(ruta, anio, mes, "Asistencia", nombreArchivo);

        Directory.CreateDirectory(Path.GetDirectoryName(rutaCompleta)!);
        await File.WriteAllBytesAsync(rutaCompleta, DecodificarBase64(fotoBase64));
        return rutaCompleta;
    }

    private static byte[] DecodificarBase64(string fotoBase64)
    {
        var indiceComa = fotoBase64.IndexOf(',');
        var base64Limpio = indiceComa >= 0 ? fotoBase64[(indiceComa + 1)..] : fotoBase64;
        return Convert.FromBase64String(base64Limpio);
    }

    // Usado por el endpoint GET .../foto: sirve la foto desde la ruta que quedó
    // guardada en CV_Visitas (su ubicación real), para no depender de recalcular
    // si la configuración cambió después de guardarla.
    public async Task<string?> ObtenerRutaFisicaAsync(long id)
    {
        var info = await visitasRepositorio.ObtenerInfoFotoAsync(id);
        var ruta = info?.FotoRuta;
        return !string.IsNullOrEmpty(ruta) && File.Exists(ruta) ? ruta : null;
    }

    // Ruta: <RutaFotos>/<Año>/<Mes>/<Tipo>/<Prefijo><ID>.jpg
    //   Año/Mes: de la fecha de visita.  Tipo: "Entrevista" o "Visita".
    //   ej. C:\Control de Visitas\Fotos\2026\07\Entrevista\CV0000000001.jpg
    private async Task<string> ConstruirRutaAsync(long id, VisitaInfoFoto info)
    {
        var ruta = await configuracionRepositorio.ObtenerValorAsync("RutaFotos", RutaPorDefecto);
        var prefijo = await configuracionRepositorio.ObtenerValorAsync("PrefijoFoto", PrefijoPorDefecto);
        var digitosTexto = await configuracionRepositorio.ObtenerValorAsync("DigitosFoto", DigitosPorDefecto);
        var digitos = int.TryParse(digitosTexto, out var valor) ? valor : int.Parse(DigitosPorDefecto);

        var anio = info.FechaVisita.Year.ToString("D4");
        var mes = info.FechaVisita.Month.ToString("D2");
        var tipo = info.EsEntrevista ? "Entrevista" : "Visita";

        var nombreArchivo = $"{prefijo}{id.ToString("D" + digitos)}.jpg";
        return Path.Combine(ruta, anio, mes, tipo, nombreArchivo);
    }
}
