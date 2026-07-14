# Checklist de configuración — Modo Kiosco (Caseta de Acceso)

Control de Visitas · Celex — equipo touch de la caseta, sin teclado/mouse físico.

---

## 0. Requisitos previos

- [ ] PC/mini-PC con Windows 10/11, monitor **touch**.
- [ ] Cámara integrada o USB (idealmente una trasera para QR y una frontal para foto; si solo hay una, se reutiliza para ambas).
- [ ] Impresora térmica de etiquetas configurada e instalada en Windows.
- [ ] El equipo está en la misma LAN que el SQL Server / servidor de la app (no depende de internet).
- [ ] Se definió el dominio interno, ej. `https://visitas.celex.local`.

---

## 1. Certificado HTTPS interno

La cámara (`getUserMedia`) **no funciona en `http://`** salvo en `localhost`. Es obligatorio HTTPS real, incluso dentro de la LAN.

- [ ] **Opción recomendada:** usar la CA interna de Active Directory Certificate Services (AD CS) — si Celex ya tiene una, emitir un certificado para `visitas.celex.local` desde ahí.
- [ ] **Alternativa sin AD CS:** generar una CA propia con `mkcert` o `OpenSSL`, e instalar el certificado raíz como "de confianza" en todos los equipos de caseta vía GPO (Directiva de grupo → Configuración del equipo → Directivas → Configuración de Windows → Seguridad → Políticas de claves públicas → Entidades de certificación raíz de confianza).
- [ ] Instalar el certificado del sitio en el servidor que hospeda el front (IIS, o el App Service/reverse proxy que se use).
- [ ] Verificar en el navegador del equipo de caseta que el candado aparece sin advertencias (si sale "no seguro", Chrome bloqueará la cámara).

---

## 2. Cuenta de Windows dedicada (Assigned Access)

- [ ] Crear una cuenta local **sin privilegios de administrador**, ej. `kiosco-recepcion`.
- [ ] Configurar **inicio de sesión automático** de esa cuenta al encender el equipo:
  - Ejecutar `netplwiz` → desmarcar "Los usuarios deben escribir su nombre y contraseña" → seleccionar la cuenta, o
  - Usar **Autologon** (Sysinternals) para mayor control.
- [ ] Configurar **Acceso asignado (kiosk mode)** de Windows: `Configuración → Cuentas → Familia y otros usuarios → Configurar un dispositivo de acceso asignado`, apuntando la cuenta a Chrome (o Edge) como app única.
  - Si Windows lo permite en la versión que tengan, esto impide que el usuario llegue al escritorio, la barra de tareas o el explorador de archivos.
- [ ] Deshabilitar el **teclado táctil nativo de Windows** (para que solo aparezca el teclado en pantalla propio de la app y no se encimen dos):
  `Configuración → Personalización → Barra de tareas → Mostrar el botón del teclado táctil` → desactivar. Adicionalmente, se puede deshabilitar el servicio "Panel de entrada táctil" (`TabletInputService`) si sigue apareciendo.
- [ ] Desactivar protector de pantalla, suspensión y apagado automático de pantalla:
  `powercfg /change standby-timeout-ac 0` y `powercfg /change monitor-timeout-ac 0`.
- [ ] Desactivar notificaciones de Windows (Enfoque asistido / Configuración → Notificaciones → desactivar todo) para que no aparezcan pop-ups sobre el kiosko.
- [ ] Programar **Windows Update** fuera del horario de operación (ej. madrugada) para que no reinicie el equipo a medio uso.

---

## 3. Flags de arranque de Chrome (modo kiosco real)

Crear un acceso directo (o script `.bat`) que lance Chrome así:

```bat
"C:\Program Files\Google\Chrome\Application\chrome.exe" ^
  --kiosk ^
  --kiosk-printing ^
  --noerrdialogs ^
  --disable-pinch ^
  --overscroll-history-navigation=0 ^
  --autoplay-policy=no-user-gesture-required ^
  --disable-session-crashed-bubble ^
  --incognito ^
  https://visitas.celex.local/kiosko
```

- `--kiosk` → pantalla completa, sin barra de direcciones ni forma de cerrar con la interfaz normal.
- `--kiosk-printing` → imprime la etiqueta directo a la impresora predeterminada, sin diálogo de impresión (clave, ya que no hay forma fácil de manejar ese diálogo sin teclado/mouse).
- `--disable-pinch` → evita que gestos táctiles de zoom saquen de proporción la pantalla.
- `--incognito` → cada sesión arranca limpia (recomendable ya que la app no depende de guardar nada en el navegador; toda la data vive en el servidor).

### Pre-autorizar el permiso de cámara (evitar el diálogo)

Aunque el touch permite tocar "Permitir", es más limpio pre-autorizarlo por política para que nunca aparezca el diálogo:

- [ ] Vía Registro de Windows: `HKLM\SOFTWARE\Policies\Google\Chrome\VideoCaptureAllowedUrls` → agregar `https://visitas.celex.local`.
- [ ] O vía plantillas ADMX de Chrome (`chrome.admx`) si administran política de grupo centralizada.

### Colocar el acceso directo en el inicio de la cuenta

- [ ] Copiar el acceso directo (o script `.bat`) a la carpeta de inicio de la cuenta `kiosco-recepcion`:
  `shell:startup` (equivale a `C:\Users\kiosco-recepcion\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup`).

---

## 4. Auto-recuperación (watchdog)

- [ ] Crear una **Tarea Programada** que revise cada 2–5 minutos si `chrome.exe` sigue corriendo; si no, relanzar el script de arranque (un script corto de PowerShell con `Get-Process` + `Start-Process` es suficiente).
- [ ] Programar un **reinicio nocturno automático** del equipo (Tarea Programada, ej. 3:00 a.m.) para limpiar memoria y liberar la cámara de cualquier estado colgado — el inicio de sesión automático + carpeta de inicio hacen que el kiosko vuelva a abrirse solo.

---

## 5. Impresora de etiquetas

- [ ] Configurar la impresora térmica como **predeterminada** en la cuenta `kiosco-recepcion`.
- [ ] Confirmar que con `--kiosk-printing` la etiqueta sale sin ningún diálogo intermedio.
- [ ] Revisar el CSS de impresión (`@media print`) de la etiqueta contra el ancho real del rollo/etiqueta física, para que no se corte texto.

---

## 6. Pantalla táctil

- [ ] Calibrar la pantalla táctil (Panel de control → Configuración de Tablet PC → Calibrar).
- [ ] Verificar que los gestos multitáctiles de Windows (3–4 dedos, cambiar de app) estén deshabilitados — de lo contrario un manotazo accidental puede sacar al visitante de Chrome.

---

## 7. Prueba de aceptación antes de salir a producción

- [ ] La cámara detecta un QR real sin pedir permiso manualmente.
- [ ] La cámara frontal toma la foto de la visita correctamente.
- [ ] El teclado en pantalla aparece y funciona en login de caseta y validación de apellido.
- [ ] El teclado numérico (PIN) de registro de salida funciona con dedos (botones suficientemente grandes).
- [ ] La etiqueta imprime automáticamente sin diálogos.
- [ ] Apagar y encender el equipo: vuelve solo al kiosko, sin necesidad de iniciar sesión manualmente.
- [ ] No hay manera de llegar al escritorio de Windows ni cerrar Chrome con gestos táctiles.
- [ ] Probar con el certificado ya instalado en 2–3 equipos de caseta distintos (no solo el de pruebas) para confirmar que la CA raíz quedó bien distribuida por GPO.
