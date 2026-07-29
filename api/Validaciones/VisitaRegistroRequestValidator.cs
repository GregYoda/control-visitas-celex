using ControlVisitas.Api.Modelos;
using FluentValidation;

namespace ControlVisitas.Api.Validaciones;

// Reglas de validación al REGISTRAR una visita. Fuente única de verdad de las
// reglas por campo: para agregar/ajustar una validación, se edita aquí (no en
// el SP ni en el front). Los mensajes van en español porque se muestran al
// usuario tal cual los devuelve la API (400 con errores por campo).
public class VisitaRegistroRequestValidator : AbstractValidator<VisitaRegistroRequest>
{
    public VisitaRegistroRequestValidator()
    {
        RuleFor(x => x.Nombre)
            .NotEmpty().WithMessage("El nombre es obligatorio.")
            .MaximumLength(100).WithMessage("El nombre no puede exceder 100 caracteres.");

        RuleFor(x => x.ApellidoPaterno)
            .NotEmpty().WithMessage("El apellido paterno es obligatorio.")
            .MaximumLength(100).WithMessage("El apellido paterno no puede exceder 100 caracteres.");

        RuleFor(x => x.ApellidoMaterno)
            .NotEmpty().WithMessage("El apellido materno es obligatorio.")
            .MaximumLength(100).WithMessage("El apellido materno no puede exceder 100 caracteres.");

        RuleFor(x => x.Correo)
            .NotEmpty().WithMessage("El correo es obligatorio.")
            .EmailAddress().WithMessage("El correo no tiene un formato válido.")
            .MaximumLength(150).WithMessage("El correo no puede exceder 150 caracteres.");

        RuleFor(x => x.Empresa)
            .MaximumLength(150).WithMessage("La empresa no puede exceder 150 caracteres.");

        RuleFor(x => x.IdArea)
            .GreaterThan(0).WithMessage("Selecciona un área válida.");

        RuleFor(x => x.Motivo)
            .NotEmpty().WithMessage("El motivo es obligatorio.")
            .MaximumLength(300).WithMessage("El motivo no puede exceder 300 caracteres.");

        RuleFor(x => x.Observaciones)
            .MaximumLength(500).WithMessage("Las observaciones no pueden exceder 500 caracteres.");

        RuleFor(x => x.Anfitrion)
            .NotEmpty().WithMessage("La persona que visita (anfitrión) es obligatoria.")
            .MaximumLength(100).WithMessage("El anfitrión no puede exceder 100 caracteres.");

        RuleFor(x => x.RegistradoPor)
            .NotEmpty().WithMessage("Falta el usuario que registra (sesión).");

        RuleFor(x => x.HoraVisita)
            .NotNull().WithMessage("La hora de visita es obligatoria.");

        // Datos del vehículo: solo obligatorios (y validados) si trae automóvil.
        When(x => x.TraeAuto, () =>
        {
            RuleFor(x => x.Marca)
                .NotEmpty().WithMessage("Indica la marca del vehículo.")
                .MaximumLength(50).WithMessage("La marca no puede exceder 50 caracteres.");
            RuleFor(x => x.Modelo)
                .NotEmpty().WithMessage("Indica el modelo del vehículo.")
                .MaximumLength(50).WithMessage("El modelo no puede exceder 50 caracteres.");
            RuleFor(x => x.Placas)
                .NotEmpty().WithMessage("Indica las placas del vehículo.")
                .MaximumLength(20).WithMessage("Las placas no pueden exceder 20 caracteres.")
                .Matches("^[A-Za-z0-9 -]+$").WithMessage("Las placas solo admiten letras, números, espacios y guiones.");
        });
    }
}
