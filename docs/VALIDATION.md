# Validación local

16 de noviembre de 2026 · MacBook Pro M5 · arm64 · macOS 27.2.1 · Xcode / Swift 6.4.2.

## Comprobado

- Compilación de producción y creación de `Bruma.app` con firma ad hoc verificada.
- Compilación del shader Metal en el dispositivo.
- Lectura real del sensor integrado mediante los informes 1 y 7.
- Siete tests de política aprobados: apertura/cierre, arranque con tapa inclinada, despejado al detenerse, ruido, movimiento acumulado lento, pérdida del sensor/pantalla y suavizado sin sobrepasar el destino.
- Siete comprobaciones GPU aprobadas sobre imágenes sintéticas:
  - Imagen abierta idéntica al original: error máximo de canal **0**.
  - Desenfoque en la zona superior.
  - Más detalle junto a la bisagra.
  - Mayor desenfoque al aumentar el cierre.
  - Alfa opaco.
  - Intensidad cero conserva el original.
  - Perspectiva opcional produce imagen válida.
- En el patrón de líneas, el contraste horizontal medio fue **31,732** en el original superior, **0,149** en la parte superior desenfocada y **36,514** junto a la bisagra. La variación de brillo del propio patrón hace diferentes los contrastes originales arriba y abajo; se usan para detectar pérdida de detalle, no como una medida óptica calibrada.
- Ventana nativa abierta y revisada visualmente. Se ve el gradiente de nitidez correcto en el patrón, los controles y las instrucciones de permiso.
- Al intentar la demo desde la app sin autorización, se mantuvo visible el escritorio normal y apareció la explicación de acceso requerido.
- Revisión de código: sin llamadas de red, sin captura de audio y sin escritura de imágenes del escritorio. Solo el modo de comprobación sintética guarda PNG.

## Pendiente de comprobación manual

- Conceder Grabación de pantalla a la **app empaquetada** y ejecutar su demo con el escritorio real. El diagnóstico invocado desde Terminal puede heredar el permiso del proceso anfitrión; un resultado positivo allí no acredita el permiso de la app abierta con Finder.
- Barrido físico completo de la tapa, en ambos sentidos, observando el resultado desde la posición normal de uso.
- Bloqueo/desbloqueo, reposo/despertar y desconexión de monitores durante un efecto activo.
- Atajo global y clics pasantes durante un efecto real.
- Pruebas en modelos diferentes y medición sostenida de CPU, GPU, energía y latencia.

La presencia de código para estos casos no se presenta como una prueba física realizada.

## Reproducir

```bash
./scripts/build.sh
./scripts/check.sh
./build/Bruma.app/Contents/MacOS/Bruma --diagnose
open build/Bruma.app
```

Concede el permiso a Bruma, pulsa **Activar en mi escritorio** y **Probar escritorio · 6 s**. Comprueba después la tapa: apertura nítida, cierre progresivo y despejado al mantenerla inmóvil.
