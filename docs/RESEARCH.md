# Investigación del efecto

Investigación realizada el 16 de noviembre de 2026, antes de implementar Bruma.

## Qué se buscaba

Una animación vinculada al movimiento real de la tapa del MacBook: la imagen se difumina al cerrar y recupera nitidez al abrir. El desenfoque aumenta con la distancia a la bisagra: la parte superior pierde detalle primero, mientras que la zona del Dock permanece más nítida.

No basta una ventana translúcida, un cambio de opacidad o un desenfoque uniforme. Hay que tomar la imagen del escritorio y aplicar un radio de desenfoque distinto en cada altura.

## Herramientas localizadas

| Proyecto / fuente primaria | Lo que aporta al estudio |
| --- | --- |
| [Mac Duo, de Makito](https://github.com/sumimakito/Mac-Duo) | Captura en vivo con ScreenCaptureKit, filtro que excluye la propia app, pirámide gaussiana en Metal Performance Shaders, capa sin foco y con clics pasantes. Se leyó su implementación. |
| [macTilt, de lqSky7](https://github.com/lqSky7/iphone-duo-macos-animation) | Shader de plegado que mide la altura desde la bisagra inferior y aumenta el desenfoque hacia arriba. Su versión estudiada también recurre a funciones privadas para la pantalla de bloqueo; Bruma no las incorpora. Se leyeron el README y el shader. |
| [Lid Plane, de Jhey](https://github.com/jh3y/lid-plane) | Referencia de ilusión de plano fijo, controles y despejado/reanclaje al parar la tapa. Se consultaron README y documentación pública. Bruma no implementa su proyección física de observador fijo. |
| [LidBlur](https://github.com/Pallavrai/LidBlur) | Otra herramienta publicada con la misma idea de desenfoque vinculado a la tapa. Se consultó su ficha pública. |
| [Bendy](https://trybendy.app) | Demo comercial difundida por Adrian Abelarde. Las búsquedas de publicaciones de X devolvieron referencias indexadas a su anuncio; el acceso directo al sitio y a X fue limitado. No se analizó código propietario ni se verificó visualmente su vídeo. |

También aparecieron [Duo](https://github.com/fx-xf/duo), [ClamShell](https://github.com/nthanhtin/ClamShell) y otras variantes. Se eligieron las implementaciones anteriores para el estudio técnico por su relación directa con el efecto solicitado.

Revisiones de código examinadas: Mac Duo `2a9fa18` y macTilt `a1745b9`.

Hay conversaciones de autores en [Reddit / SwiftUI](https://www.reddit.com/r/SwiftUI/comments/1wfxr7o/iphone_duos_folding_animation_clone_for_macbooks/) y [Reddit / Swift](https://www.reddit.com/r/swift/comments/1xfzds8/made_my_macbook_screen_blur_as_i_close_the_lid/). Ayudaron a identificar proyectos y problemas de experiencia de uso; las decisiones técnicas se basaron en código y documentación primaria.

## Sensor comprobado

El sensor seleccionado es un dispositivo Apple integrado con vendor `0x05AC`, usage page `0x20` y usage `0x8A`. Solo se solicitan informes de características de ese dispositivo:

- Informe 1: identificador seguido por dos bytes little endian con grados enteros.
- Informe 7: identificador seguido por cuatro bytes little endian con centésimas de grado; si no responde se usa el informe 1.

Referencias: [LidAngleSensor](https://github.com/samhenrigold/LidAngleSensor) y [el lector de Mac Duo](https://github.com/sumimakito/Mac-Duo/blob/main/Sources/LidAngleKit/LidAngleSensor.swift).

Se verificó la lectura en el MacBook Pro M5 local. En una muestra, el informe 1 indicó 107° y el informe 7 unos 106,98°. El hardware actualiza por su cuenta: consultar a 20 Hz no significa que produzca 20 ángulos nuevos por segundo. La animación interpola entre muestras.

## Composición elegida

1. Detectar movimiento acumulado mayor o igual a 0,3° para ignorar pequeñas oscilaciones.
2. Calcular un progreso suave entre 110° y 12°, sin saltos al atravesar el umbral.
3. Iniciar una captura de la pantalla integrada excluyendo esta app. No mostrar ninguna capa hasta disponer de una imagen válida.
4. Copiar el fotograma más reciente a una textura con niveles de desenfoque gaussiano mediante `MPSImageGaussianPyramid`.
5. Elegir el nivel de desenfoque por píxel con muestreo trilineal. El radio crece con `pow(distanciaALaBisagra, 1.5)` y con el progreso de cierre.
6. Dibujar una ventana sin bordes, sin foco y con clics pasantes. Por defecto no se reproyectan ni se mueven los píxeles del escritorio.
7. Al detenerse, reducir el efecto a cero y parar la captura. Al dormir, bloquear o cambiar la configuración de pantallas, retirar la capa inmediatamente.

La perspectiva opcional de Bruma es una recesión visual suave, no una compensación física de la posición de los ojos. Se dejó apagada para priorizar exactamente el gradiente de nitidez solicitado.

Documentación de Apple: [ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit), [captura de pantalla en macOS](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos), [MPSImageGaussianPyramid](https://developer.apple.com/documentation/metalperformanceshaders/mpsimagegaussianpyramid), [IOHIDDeviceGetReport](https://developer.apple.com/documentation/iokit/1438383-iohiddevicegetreport). Las firmas y disponibilidades también se comprobaron compilando contra el SDK local.

## Alcance deliberado

No se reproduce la pantalla de bloqueo con APIs privadas, no se impide el reposo, no se instalan agentes ni se escribe en el sensor. El efecto es cosmético y temporal. La demo y las comprobaciones sintéticas permiten revisar el gradiente incluso sin mover la tapa o conceder acceso a la pantalla.
