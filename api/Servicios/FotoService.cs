using ControlVisitas.Api.Datos;

namespace ControlVisitas.Api.Servicios;

public interface IFotoService
{
    Task<string> GuardarAsync(long id, string fotoBase64);
    Task<string?> ObtenerRutaFisicaAsync(long id);
}

public class FotoService(IConfiguracionRepositorio configuracionRepositorio) : IFotoService
{
    private const string RutaPorDefecto = @"C:\Control de Visitas\Fotos";
    private const string PrefijoPorDefecto = "CV";
    private const string DigitosPorDefecto = "10";

    public async Task<string> GuardarAsync(long id, string fotoBase64)
    {
        var rutaCompleta = await ConstruirRutaAsync(id);
        Directory.CreateDirectory(Path.GetDirectoryName(rutaCompleta)!);

        var indiceComa = fotoBase64.IndexOf(',');
        var base64Limpio = indiceComa >= 0 ? fotoBase64[(indiceComa + 1)..] : fotoBase64;
        var bytes = Convert.FromBase64String(base64Limpio);
        await File.WriteAllBytesAsync(rutaCompleta, bytes);

        return rutaCompleta;
    }

    // Usado por el endpoint GET .../foto: recalcula la ruta con la configuración
    // actual (RutaFotos puede cambiar desde la pantalla de Configuración) en vez
    // de depender de la ruta cruda de disco que quedó guardada en CV_Visitas.
    public async Task<string?> ObtenerRutaFisicaAsync(long id)
    {
        var rutaCompleta = await ConstruirRutaAsync(id);
        return File.Exists(rutaCompleta) ? rutaCompleta : null;
    }

    private async Task<string> ConstruirRutaAsync(long id)
    {
        var ruta = await configuracionRepositorio.ObtenerValorAsync("RutaFotos", RutaPorDefecto);
        var prefijo = await configuracionRepositorio.ObtenerValorAsync("PrefijoFoto", PrefijoPorDefecto);
        var digitosTexto = await configuracionRepositorio.ObtenerValorAsync("DigitosFoto", DigitosPorDefecto);
        var digitos = int.TryParse(digitosTexto, out var valor) ? valor : int.Parse(DigitosPorDefecto);

        // <PrefijoFoto> + ID con ceros a la izquierda a <DigitosFoto> dígitos,
        // ej. CV0000000001.jpg con los valores por defecto.
        var nombreArchivo = $"{prefijo}{id.ToString("D" + digitos)}.jpg";
        return Path.Combine(ruta, nombreArchivo);
    }
}
