using ControlVisitas.Api.Modelos;
using FluentValidation;

namespace ControlVisitas.Api.Validaciones;

// Alta / edición de un empleado del padrón de asistencia.
// (El código de acceso NO se valida: lo genera el sistema en el alta y se
//  conserva en la edición.)
public class EmpleadoGuardarRequestValidator : AbstractValidator<EmpleadoGuardarRequest>
{
    private static readonly string[] TiposValidos = { "Empleado", "Mensajero" };

    public EmpleadoGuardarRequestValidator()
    {
        RuleFor(x => x.NumeroEmpleado)
            .NotEmpty().WithMessage("El número de empleado es obligatorio.")
            .MaximumLength(20).WithMessage("El número de empleado no puede exceder 20 caracteres.");

        RuleFor(x => x.NumeroWishPos)
            .MaximumLength(20).WithMessage("El número de WishPOS no puede exceder 20 caracteres.");

        RuleFor(x => x.NombreCompleto)
            .NotEmpty().WithMessage("El nombre completo es obligatorio.")
            .MaximumLength(150).WithMessage("El nombre completo no puede exceder 150 caracteres.");

        RuleFor(x => x.Tipo)
            .NotEmpty().WithMessage("El tipo es obligatorio.")
            .Must(t => TiposValidos.Contains(t)).WithMessage("El tipo debe ser 'Empleado' o 'Mensajero'.");
    }
}

// Registro de un movimiento de asistencia en el kiosko.
public class RegistrarMovimientoRequestValidator : AbstractValidator<RegistrarMovimientoRequest>
{
    private static readonly string[] MovimientosValidos = { "Entrada", "SalidaComer", "RegresoComida", "Salida" };

    public RegistrarMovimientoRequestValidator()
    {
        RuleFor(x => x.IdEmpleado)
            .GreaterThan(0).WithMessage("Empleado no válido.");

        RuleFor(x => x.TipoMovimiento)
            .NotEmpty().WithMessage("Falta el tipo de movimiento.")
            .Must(t => MovimientosValidos.Contains(t)).WithMessage("El tipo de movimiento no es válido.");
    }
}
