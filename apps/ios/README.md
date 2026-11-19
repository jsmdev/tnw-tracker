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

## Datos de entrenamiento

Los datos locales siguen el [formato de datos de entrenamiento](../../docs/training-data-format.md).

| Capa | Dónde | Qué hace |
| --- | --- | --- |
| Valores | `TNWTrackerKit/Sources/Domain/Training` | `Exercise`, `Routine`, `TrainingSession`, `SessionEntry` y `ExerciseSet`: structs `Sendable` con la forma del formato. |
| Repositorios | `TNWTrackerKit/Sources/Data/Repositories` | `ExerciseRepositoryProtocol`, `RoutineRepositoryProtocol` y `SessionRepositoryProtocol`. Mantienen las reglas del formato: una entrada `done` por ejercicio, orden de series por origen, series manuales e importadas, reconciliación (por defecto se quedan las importadas), `superseded` y entradas `skipped` y `removed`. |
| Persistencia | `TNWTrackerKit/Sources/Data/Persistence` | Modelos `@Model` de SwiftData en `TrainingSchemaV1`, detrás de `TrainingMigrationPlan`. Son internos al framework. |
| Store | `TrainingStore` | Abre el contenedor y entrega los repositorios. |

Las vistas y los view models solo ven los valores y los protocolos de repositorio. No importan SwiftData.

- **Sin migración del modelo anterior.** El esquema sustituye por completo al modelo anterior. El store vive en un fichero nuevo, `training-v1.store`, dentro del app group. El antiguo `tnwtracker.sqlite` no se lee ni se migra, y sus datos no aparecen en la app. No había usuarios reales, así que no se pierde nada.
- **Versiones futuras.** Copiar los modelos a `TrainingSchemaV2`, añadirlo a `TrainingMigrationPlan.schemas` y añadir una etapa.
- **Sesiones en curso.** Una sesión sin `completedAt` está en curso. Es un estado solo de la app: el formato describe únicamente sesiones completadas.
- **Datos de ejemplo.** `SampleTrainingData` (solo en Debug) tiene ejercicios, rutinas y dos sesiones inventados. Alimenta las previews, los tests y los tests de interfaz, y lo usa el botón "Reset & seed" de Ajustes.
- **Sincronización.** `SyncEngine` no hace nada (`NoopSyncEngine`) hasta que exista la sincronización con el esquema nuevo (#135).
