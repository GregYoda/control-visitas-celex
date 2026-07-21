# Manual de uso — Control de Visitas (Celex)

Sistema para registrar y controlar el acceso de visitantes: reemplaza la
bitácora de papel por un flujo digital con **código de acceso**, **foto** y
**código de salida**, todo consultable en reportes.

---

## 1. Conceptos clave (léelo primero)

- **Código de acceso** (6 dígitos): se genera al **registrar** la visita y se
  le comparte al visitante (además, le llega por correo). Lo teclea en la
  caseta para registrar su llegada. Sirve **una sola vez** y solo el **día**
  para el que se registró la visita.
- **Código de salida** (6 dígitos): es **distinto** al de acceso. Se genera
  **cuando la visita entra** (al validar el acceso) y aparece en su etiqueta.
  El visitante lo conserva y lo usa al salir.
- **Estados de una visita:**
  - **Pendiente** — registrada, aún no llega.
  - **Dentro** — ya registró su acceso, sigue en las instalaciones.
  - **Salida registrada** — ya entró y salió.
  - **Cancelada** — se anuló antes de que entrara.

---

## 2. Iniciar sesión

1. Abre el sistema en el navegador.
2. Escribe tu **contraseña de WishPOS** (no se pide usuario) y presiona
   **Entrar**.
3. Entras al **Menú**; da clic en **Control de Visitas** para abrir el módulo.

> Si tu contraseña es rechazada, verifica que sea la misma de WishPOS. El
> sistema no crea usuarios nuevos.

---

## 3. El módulo Control de Visitas

Verás hasta cinco tarjetas (la de Configuración solo aparece si tu usuario
tiene el permiso correspondiente):

| Tarjeta | Para qué sirve |
|---|---|
| 📝 **Registrar visita** | Capturar un visitante y generar su código de acceso. |
| 📋 **Mis visitas** | Consultar, editar o cancelar las visitas que tú registraste. |
| 📊 **Reportes / Bitácora** | Consultar accesos por fechas y exportar a CSV. |
| 🛡️ **Área de Acceso** | Modo caseta/kiosko (registrar llegada y salida). |
| ⚙️ **Configuración** | Parámetros del sistema (solo usuarios autorizados). |

---

## 4. Registrar una visita

1. En el módulo, entra a **Registrar visita**.
2. Llena los campos (los marcados con \* son obligatorios):
   - Nombre, Apellido paterno, Apellido materno \*
   - Correo electrónico \* — a esta dirección le llega el código de acceso.
   - Empresa \*, Área a visitar \*, Motivo de la visita \*
   - **Observaciones** (opcional) — comentarios para que **vigilancia** los
     tenga en cuenta al recibir a la visita.
   - Fecha de visita \* — el acceso solo se permitirá ese día.
   - Persona que visita (anfitrión) \*
   - **⭐ Marcar como visita VIP** — *solo aparece si tu usuario está
     autorizado* (ver Configuración). Úsalo para visitas que requieren
     atención especial.
   - **¿El visitante trae vehículo?** — si lo activas, captura Marca, Modelo y
     Placas.
3. Presiona **Generar código de acceso**.
4. La pantalla muestra el **código de acceso de 6 dígitos** y un resumen.
   - El visitante lo recibe **automáticamente por correo**.
   - Puedes copiarlo con el botón correspondiente para compartirlo por otro
     medio.

> El visitante necesita este código **el día de su visita** para registrar su
> llegada en la caseta.

---

## 5. Mis visitas (consultar / editar / cancelar)

En **Mis visitas** ves la lista de lo que tú registraste, con su estado, foto
(si ya entró) y etiqueta ⭐ VIP cuando aplica.

- **Editar** — solo disponible mientras la visita está **Pendiente** (aún no
  registra acceso). Abre la visita, cambia lo necesario y **Guardar cambios**.
  Una vez que el visitante entró, el botón Editar queda deshabilitado.
- **Cancelar** — dentro de la edición, botón **"Cancelar esta visita"** (pide
  confirmación). Solo se puede cancelar mientras esté **Pendiente**. Al
  cancelarla, su código de acceso deja de funcionar.
- **Volver sin guardar** — sale de la edición sin aplicar cambios.

---

## 6. Modo caseta / Área de Acceso

Pensado para el equipo de la caseta. Entra con **Área de Acceso → Entrar al
kiosko**. Verás dos opciones grandes:

### 6.1 Registrar acceso (llegada)

1. Toca **🔑 REGISTRAR ACCESO**.
2. El visitante teclea su **código de acceso de 6 dígitos** en el teclado
   numérico.
3. **Confirma identidad**: escribe el **apellido paterno** tal como se
   registró y presiona **Validar**.
4. **Foto**: toma la fotografía del visitante (**Tomar foto** → **Usar esta
   foto**, o **Repetir foto**). Si no hay cámara, se puede **Continuar sin
   foto**.
5. Aparece la **etiqueta de acceso** con nombre, área, anfitrión, la marca
   **⭐ VISITA VIP** si aplica, y el **código de salida** (que el visitante
   debe conservar). Se puede **Imprimir etiqueta**.

**Mensajes posibles al validar:**
- *Código no reconocido* — mal tecleado o no existe.
- *Este código ya fue utilizado* — ya se registró el acceso con él.
- *Esta visita fue cancelada* — solicitar apoyo en recepción.
- *Esta visita está registrada para el [fecha], no para hoy* — el acceso solo
  es válido el día registrado.
- *Apellido no coincide* — hay hasta **3 intentos**; tras el tercero se pide
  apoyo a seguridad/recepción.

### 6.2 Registrar salida

1. Toca **🚪 REGISTRAR SALIDA**.
2. El visitante teclea su **código de salida**.
3. Aparece **"¿Eres tú?"** con su nombre y hora de entrada para confirmar que
   es la persona correcta:
   - **✅ Confirmar salida** — registra la salida y muestra el tiempo de
     estancia.
   - **❌ No soy yo** — regresa para volver a teclear.

### 6.3 Salir del kiosko

El botón **‹ Salir del kiosko** **cierra la sesión** por completo (para no
dejar la cuenta abierta en el equipo de la caseta).

---

## 7. Reportes / Bitácora

1. Entra a **Reportes / Bitácora**.
2. Elige el **rango de fechas** (Desde / Hasta) y presiona **Generar**.
3. La tabla muestra cada visita: visitante, empresa, área, anfitrión, fecha,
   **estado**, registro, acceso, código de salida, salida y duración (y la
   marca VIP cuando aplica).
4. **Exportar CSV** descarga exactamente lo que ves en pantalla (se abre en
   Excel).

---

## 8. Configuración (solo usuarios autorizados)

La tarjeta ⚙️ **Configuración** solo aparece para usuarios con el permiso
correspondiente de WishPOS. Permite ajustar:

- **Ruta de fotos** — carpeta del servidor donde se guardan las fotos.
- **Prefijo del nombre de archivo** y **Dígitos del ID** — arman el nombre de
  cada foto (ej. `CV0000000001.jpg`).
- **Usuarios que pueden marcar visitas VIP** — lista de **IDs de usuario**
  (el ID que aparece al iniciar sesión) separados por coma (ej. `100, 205`).
  Solo esos usuarios verán el checkbox "Visita VIP" al registrar. Déjalo vacío
  si nadie debe marcar VIP.

> **Importante:** un cambio en la lista de usuarios VIP surte efecto la
> **próxima vez que esa persona inicie sesión**.

---

## 9. Preguntas frecuentes

- **¿El visitante puede entrar otro día con el mismo código?**
  No. El código de acceso solo funciona el día registrado y una sola vez.

- **¿Se puede editar una visita que ya entró?**
  No. Solo mientras está *Pendiente*. Después queda como registro histórico.

- **No me aparece la opción VIP al registrar.**
  Solo la ven los usuarios dados de alta en Configuración → *Usuarios que
  pueden marcar visitas VIP*. Si deberías tenerla, pide que agreguen tu ID de
  usuario y vuelve a iniciar sesión.

- **No me aparece la tarjeta de Configuración.**
  Requiere un permiso especial de WishPOS; no todos los usuarios lo tienen.

- **La cámara no funciona en la caseta.**
  La toma de foto requiere que el sistema se abra por **HTTPS** (sitio
  seguro). Si no hay cámara disponible, usa **Continuar sin foto**.

- **El visitante no recibió el correo.**
  El correo se envía automáticamente al registrar. Si no llega, verifica que
  el correo capturado sea correcto y reporta a soporte (el envío depende de un
  proceso del servidor).
