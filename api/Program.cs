using ControlVisitas.Api.Datos;
using ControlVisitas.Api.Servicios;
using ControlVisitas.Api.Validaciones;
using FluentValidation;

var builder = WebApplication.CreateBuilder(args);

// Add services to the container.

// Validaciones por campo con FluentValidation. Los validadores viven en
// api/Validaciones (uno por request); el FluentValidationFilter los ejecuta
// automáticamente antes de cada acción y devuelve 400 con errores por campo.
builder.Services.AddValidatorsFromAssemblyContaining<VisitaRegistroRequestValidator>();
builder.Services.AddControllers(opciones => opciones.Filters.Add<FluentValidationFilter>());
// Learn more about configuring Swagger/OpenAPI at https://aka.ms/aspnetcore/swashbuckle
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

builder.Services.AddScoped<ISqlConnectionFactory, SqlConnectionFactory>();
builder.Services.AddScoped<IAreasRepositorio, AreasRepositorio>();
builder.Services.AddScoped<IVisitasRepositorio, VisitasRepositorio>();
builder.Services.AddScoped<IConfiguracionRepositorio, ConfiguracionRepositorio>();
builder.Services.AddScoped<IAsistenciaRepositorio, AsistenciaRepositorio>();
builder.Services.AddScoped<IFotoService, FotoService>();
builder.Services.AddHttpClient<IWishPosAuthService, WishPosAuthService>();

// El mockup (web/index.html) se sirve desde otro origen que la API; en beta
// local esto basta con permitir cualquier origen. Cuando haya un dominio real
// de producción, cambiar por una lista explícita de orígenes permitidos.
builder.Services.AddCors(options =>
{
    options.AddPolicy("MockupDev", p => p.AllowAnyOrigin().AllowAnyMethod().AllowAnyHeader());
});

var app = builder.Build();

// Configure the HTTP request pipeline.
if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
    app.UseCors("MockupDev");
}

app.UseHttpsRedirection();

// Sirve el frontend (web/index.html) desde el mismo sitio que la API
// (mismo-origen: no hace falta CORS y el front usa rutas relativas).
// El archivo se copia a wwwroot/ al compilar -- ver el Target en el .csproj.
app.UseDefaultFiles();
app.UseStaticFiles();

app.UseAuthorization();

// Las respuestas de la API no deben cachearse en el navegador: si no, un GET
// (ej. el padrón de empleados o el estado de asistencia) puede servir datos
// viejos justo después de un POST que los cambió (read-after-write). El
// frontend estático (index.html) sí puede cachearse normal.
app.Use(async (context, next) =>
{
    if (context.Request.Path.StartsWithSegments("/api"))
    {
        context.Response.Headers.CacheControl = "no-store, no-cache, must-revalidate";
        context.Response.Headers.Pragma = "no-cache";
    }
    await next();
});

app.MapControllers();

app.Run();
