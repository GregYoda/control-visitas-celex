@echo off
REM ============================================================================
REM  Control de Visitas - Celex  |  Lanzador del kiosko de caseta
REM ----------------------------------------------------------------------------
REM  Abre Chrome en modo kiosko con impresion DIRECTA (sin dialogo):
REM    --kiosk-printing  => al oprimir "Imprimir etiqueta" (window.print())
REM                         la etiqueta sale DIRECTO a la impresora
REM                         PREDETERMINADA de Windows, sin confirmacion.
REM
REM  IMPORTANTE:
REM   1) La impresora termica de etiquetas debe estar como PREDETERMINADA
REM      en la cuenta de Windows del kiosko (Configuracion > Bluetooth y
REM      dispositivos > Impresoras y escaneres > elegir la termica >
REM      "Establecer como predeterminada"). Chrome imprime a la predeterminada.
REM   2) Ajusta la variable URL de abajo a tu direccion real.
REM   3) Para copiarlo al inicio automatico de la cuenta del kiosko:
REM      pegar un acceso directo a este .bat en  shell:startup
REM ============================================================================

set "URL=https://visitas.celex.local/"
set "CHROME=C:\Program Files\Google\Chrome\Application\chrome.exe"
if not exist "%CHROME%" set "CHROME=C:\Program Files (x86)\Google\Chrome\Application\chrome.exe"

start "" "%CHROME%" ^
  --kiosk ^
  --kiosk-printing ^
  --noerrdialogs ^
  --disable-pinch ^
  --overscroll-history-navigation=0 ^
  --autoplay-policy=no-user-gesture-required ^
  --disable-session-crashed-bubble ^
  --incognito ^
  "%URL%"

REM ----------------------------------------------------------------------------
REM  PARA PROBAR SOLO LA IMPRESION SILENCIOSA (sin pantalla completa),
REM  comenta el bloque de arriba y usa esta linea apuntando al equipo local:
REM
REM  start "" "%CHROME%" --kiosk-printing "http://localhost:5280/"
REM ----------------------------------------------------------------------------
