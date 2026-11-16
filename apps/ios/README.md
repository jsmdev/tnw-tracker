# TNW Tracker — iOS

Este proyecto usa [XcodeGen](https://github.com/yonaskolb/XcodeGen) para generar el `.xcodeproj`.

1. Instalá XcodeGen: `brew install xcodegen`
2. Desde `apps/ios/`, ejecutá: `xcodegen generate`
3. Abrí el `TnwTracker.xcodeproj` generado en Xcode.

## Tests

Desde la raíz del repositorio, con el proyecto ya generado:

```sh
xcodebuild test \
  -project apps/ios/TnwTracker.xcodeproj \
  -scheme TNWTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' \
  -only-testing:TNWTrackerTests
```

Para los tests de interfaz, cambia el filtro por `-only-testing:TNWTrackerUITests`.

## CI

El workflow `.github/workflows/ios-tests.yml` se ejecuta en cada PR contra `develop` o `main`:

| Job              | Qué ejecuta                       | Cuándo                                  |
| ---------------- | --------------------------------- | --------------------------------------- |
| `ios-unit-tests` | `TNWTrackerTests` (Swift Testing) | Si el PR toca `apps/ios` o el propio CI |
| `ios-ui-tests`   | `TNWTrackerUITests` (XCTest)      | Siempre                                 |

Los dos jobs comparten la acción `.github/actions/ios-setup`, que selecciona Xcode, genera el proyecto con XcodeGen a partir de `Local.xcconfig.example` y restaura la caché de paquetes SPM.

### Versión de Xcode

El CI usa **Xcode 26.6** en el runner `macos-26`. Está fijada en un único sitio: el valor por defecto de `xcode-version` en `.github/actions/ios-setup/action.yml`.

En desarrollo se usa Xcode 27.2, y el CI no puede igualarla todavía. GitHub solo ofrece Xcode 27 en el runner `xcode-27`, que sigue en vista previa. Se probó en el PR #149 y dos de las seis ejecuciones de los jobs fallaron porque el simulador dejó de responder, sin relación con el código. Como `ios-ui-tests` es una comprobación obligatoria, se prefiere el runner estable.

Mientras dure esta diferencia, el CI compila con el SDK de iOS 26: el código que use API nuevas de iOS 27 compilará en local pero no en el CI. Cuando el runner `xcode-27` salga de la vista previa, hay que cambiar `runs-on` en el workflow y `xcode-version` en la acción a la versión de desarrollo.
