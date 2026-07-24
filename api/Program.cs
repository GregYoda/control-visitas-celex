using ControlVisitas.Api.Datos;
using ControlVisitas.Api.Servicios;

var builder = WebApplication.CreateBuilder(args);

// Add services to the container.

builder.Services.AddControllers();
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

app.MapControllers();

app.Run();
