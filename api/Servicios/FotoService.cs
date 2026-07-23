using ControlVisitas.Api.Datos;

namespace ControlVisitas.Api.Servicios;

public interface IFotoService
{
    Task<string> GuardarAsync(long id, string fotoBase64);
    Task<string?> ObtenerRutaFisicaAsync(long id);
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

        var indiceComa = fotoBase64.IndexOf(',');
        var base64Limpio = indiceComa >= 0 ? fotoBase64[(indiceComa + 1)..] : fotoBase64;
        var bytes = Convert.FromBase64String(base64Limpio);
        await File.WriteAllBytesAsync(rutaCompleta, bytes);

        return rutaCompleta;
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
