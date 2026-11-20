#if DEBUG
    import Foundation
    import UIKit

    /// Invented media for previews, tests and UI tests: the objects it holds,
    /// and for any other path the error of a device with no network.
    public struct InventedExerciseMediaSource: ExerciseMediaSource {
        public let objects: [String: Data]

        public init(objects: [String: Data] = [:]) {
            self.objects = objects
        }

        public func download(path: String) throws -> Data {
            guard let data = objects[path] else { throw URLError(.notConnectedToInternet) }
            return data
        }

        /// A small invented PNG: one flat neutral tile.
        public static func inventedImage(side: CGFloat = 8) -> Data {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).pngData { context in
                UIColor.systemGray3.setFill()
                context.fill(CGRect(x: 0, y: 0, width: side, height: side))
            }
        }
    }

    extension ExerciseMediaLibrary {
        /// A library that never reaches a network and has nothing stored, in a
        /// new temporary folder: every image or video is unavailable offline.
        public static func offlineForTesting() -> ExerciseMediaLibrary {
            library(source: InventedExerciseMediaSource())
        }

        /// UI tests: the sample data's image (`SampleTrainingData`) is an invented PNG.
        public static func sampleForUITesting() -> ExerciseMediaLibrary {
            library(source: InventedExerciseMediaSource(objects: [
                "exercises/chest-press.jpg": InventedExerciseMediaSource.inventedImage()
            ]))
        }

        private static func library(source: InventedExerciseMediaSource) -> ExerciseMediaLibrary {
            let folder = FileManager.default.temporaryDirectory
                .appending(path: "exercise-media-\(UUID().uuidString)", directoryHint: .isDirectory)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return ExerciseMediaLibrary(store: ExerciseMediaStore(folder: folder, source: source))
        }
    }
#endif
