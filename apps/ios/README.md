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

El CI usa **Xcode 27.2**, la misma versión que se usa en desarrollo. Está fijada en un único sitio: el valor por defecto de `xcode-version` en `.github/actions/ios-setup/action.yml`.

Xcode 27 solo está disponible en el runner `xcode-27` de GitHub, que sigue en vista previa y puede tener colas más largas. Si deja de estar disponible, la alternativa estable es el runner `macos-26` con Xcode 26.6: hay que cambiar `runs-on` en el workflow y `xcode-version` en la acción.
