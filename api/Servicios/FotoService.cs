using ControlVisitas.Api.Datos;

namespace ControlVisitas.Api.Servicios;

public interface IFotoService
{
    Task<string> GuardarAsync(long id, string fotoBase64);
}

public class FotoService(IConfiguracionRepositorio configuracionRepositorio) : IFotoService
{
    private const string RutaPorDefecto = @"C:\Control de Visitas\Fotos";
    private const string PrefijoPorDefecto = "CV";
    private const string DigitosPorDefecto = "10";

    public async Task<string> GuardarAsync(long id, string fotoBase64)
    {
        var ruta = await configuracionRepositorio.ObtenerValorAsync("RutaFotos", RutaPorDefecto);
        var prefijo = await configuracionRepositorio.ObtenerValorAsync("PrefijoFoto", PrefijoPorDefecto);
        var digitosTexto = await configuracionRepositorio.ObtenerValorAsync("DigitosFoto", DigitosPorDefecto);
        var digitos = int.TryParse(digitosTexto, out var valor) ? valor : int.Parse(DigitosPorDefecto);

        Directory.CreateDirectory(ruta);

        // <PrefijoFoto> + ID con ceros a la izquierda a <DigitosFoto> dígitos,
        // ej. CV0000000001.jpg con los valores por defecto.
        var nombreArchivo = $"{prefijo}{id.ToString("D" + digitos)}.jpg";
        var rutaCompleta = Path.Combine(ruta, nombreArchivo);

        var indiceComa = fotoBase64.IndexOf(',');
        var base64Limpio = indiceComa >= 0 ? fotoBase64[(indiceComa + 1)..] : fotoBase64;
        var bytes = Convert.FromBase64String(base64Limpio);
        await File.WriteAllBytesAsync(rutaCompleta, bytes);

        return rutaCompleta;
    }
}
