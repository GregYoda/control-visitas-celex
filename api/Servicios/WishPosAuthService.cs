using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Xml.Linq;
using ControlVisitas.Api.Modelos;

namespace ControlVisitas.Api.Servicios;

public interface IWishPosAuthService
{
    Task<LoginResponse> LoginAsync(string password, string originIp);
}

internal record WishPosAccesoNodo(string? Pantalla_Identidad, List<WishPosAccesoNodo>? SubModule);

internal record WishPosLoginResultado(
    int Error_Codigo,
    string Error_Mensaje,
    int Usuario_ID,
    string? Usuario,
    string? Nombre,
    List<WishPosAccesoNodo>? Accesos,
    List<WishPosAccesoNodo>? MiEspacio);

public class WishPosAuthService(HttpClient http) : IWishPosAuthService
{
    private const string EndpointBase = "https://celexpos.celex.com/prod/WSWish.asmx/mtdActiva11";

    public async Task<LoginResponse> LoginAsync(string password, string originIp)
    {
        var clave = Convert.ToHexString(SHA512.HashData(Encoding.UTF8.GetBytes(password))).ToLowerInvariant();
        var payload = new object[]
        {
            new
            {
                Proceso = "System_LOGIN",
                Clave = clave,
                Origin = originIp,
                Usuario_ID = 0,
                UUID = Guid.NewGuid().ToString(),
                Aplicacion = "WEB",
                Version = "1.00"
            }
        };
        var url = $"{EndpointBase}?JsonRequest={Uri.EscapeDataString(JsonSerializer.Serialize(payload))}";

        string xml;
        try
        {
            xml = await http.GetStringAsync(url);
        }
        catch (Exception)
        {
            return new LoginResponse(false, "No se pudo contactar el servidor de WishPOS.", null, null, null);
        }

        string innerJson;
        try
        {
            innerJson = XDocument.Parse(xml).Root!.Value;
        }
        catch (Exception)
        {
            return new LoginResponse(false, "Respuesta inesperada de WishPOS.", null, null, null);
        }

        List<WishPosLoginResultado>? resultados;
        try
        {
            resultados = JsonSerializer.Deserialize<List<WishPosLoginResultado>>(innerJson);
        }
        catch (Exception)
        {
            return new LoginResponse(false, "No se pudo interpretar la respuesta de WishPOS.", null, null, null);
        }

        var resultado = resultados?.FirstOrDefault();
        if (resultado is null)
        {
            return new LoginResponse(false, "WishPOS no regresó información de acceso.", null, null, null);
        }

        if (resultado.Error_Codigo != 0)
        {
            return new LoginResponse(false, resultado.Error_Mensaje, null, null, null);
        }

        // La pantalla de Configuración solo se muestra si WishPOS le dio al
        // usuario acceso a la pantalla CV.230.01 (buscar en Accesos y
        // MiEspacio, incluyendo SubModule anidados).
        const string PantallaConfiguracion = "CV.230.01";
        var puedeConfigurar = TieneAcceso(resultado.Accesos, PantallaConfiguracion)
            || TieneAcceso(resultado.MiEspacio, PantallaConfiguracion);

        return new LoginResponse(true, resultado.Error_Mensaje, resultado.Usuario, resultado.Nombre, resultado.Usuario_ID, puedeConfigurar);
    }

    private static bool TieneAcceso(List<WishPosAccesoNodo>? nodos, string identidad)
    {
        if (nodos is null) return false;
        foreach (var nodo in nodos)
        {
            if (nodo.Pantalla_Identidad == identidad) return true;
            if (TieneAcceso(nodo.SubModule, identidad)) return true;
        }
        return false;
    }
}
