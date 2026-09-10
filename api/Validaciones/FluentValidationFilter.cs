using FluentValidation;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;

namespace ControlVisitas.Api.Validaciones;

// Filtro que, antes de ejecutar cada acción, busca si hay un IValidator<T>
// registrado para cada argumento del método y lo valida. Si falla, corta la
// petición y devuelve un 400 con el MISMO formato que usa ASP.NET
// (ValidationProblemDetails: { "errors": { "Campo": ["mensaje"] } }), de modo
// que el frontend lee los errores por campo igual que siempre.
//
// Se prefiere este filtro en vez de la auto-validación de FluentValidation.AspNetCore
// (deprecada): así el wiring queda explícito y bajo nuestro control.
public class FluentValidationFilter(IServiceProvider serviceProvider) : IAsyncActionFilter
{
    public async Task OnActionExecutionAsync(ActionExecutingContext context, ActionExecutionDelegate next)
    {
        foreach (var argumento in context.ActionArguments.Values)
        {
            if (argumento is null) continue;

            var tipoValidador = typeof(IValidator<>).MakeGenericType(argumento.GetType());
            if (serviceProvider.GetService(tipoValidador) is not IValidator validador) continue;

            var contexto = new ValidationContext<object>(argumento);
            var resultado = await validador.ValidateAsync(contexto);
            if (resultado.IsValid) continue;

            foreach (var error in resultado.Errors)
                context.ModelState.AddModelError(error.PropertyName, error.ErrorMessage);

            context.Result = new BadRequestObjectResult(new ValidationProblemDetails(context.ModelState));
            return;
        }

        await next();
    }
}
