import Foundation
import Observation
import UIKit

/// The top of the exercise sheet (#137 S7): the video, else the image, else a
/// neutral placeholder saying why there is nothing to show. Both are
/// downloaded on demand, the first time the sheet shows them, and read from
/// the account's files from then on, offline too.
@Observable
@MainActor
public final class ExerciseHeroModel {
    public private(set) var image: UIImage?
    public private(set) var videoFile: URL?
    /// True until the first load ends, when there is something to load.
    public private(set) var isLoading: Bool
    public private(set) var imageUnavailable: ExerciseMediaLibrary.Unavailable?
    public private(set) var videoUnavailable: ExerciseMediaLibrary.Unavailable?

    private let library: ExerciseMediaLibrary
    private let imagePath: String?
    private let videoPath: String?

    public init(content: ExerciseSheetContent, library: ExerciseMediaLibrary) {
        self.library = library
        imagePath = content.imagePath
        videoPath = content.videoPath
        isLoading = content.imagePath != nil || content.videoPath != nil
        // Shown at once when this account decoded it before: no flash of the placeholder.
        image = content.imagePath.flatMap(library.memoryCachedImage(path:))
    }

    /// Loads the image, then the video.
    public func load() async {
        isLoading = true
        defer { isLoading = false }
        if let imagePath {
            do {
                image = try await library.image(path: imagePath)
            } catch {
                imageUnavailable = ExerciseMediaLibrary.Unavailable(error)
            }
        }
        if let videoPath {
            do {
                videoFile = try await library.videoFile(path: videoPath)
            } catch {
                videoUnavailable = ExerciseMediaLibrary.Unavailable(error)
            }
        }
    }

    /// Why the hero shows the placeholder; nil while loading, or when the
    /// image or the video shows.
    public var placeholder: ExerciseMediaLibrary.Unavailable? {
        guard !isLoading, image == nil, videoFile == nil else { return nil }
        let reasons = [imageUnavailable, videoUnavailable].compactMap(\.self)
        if reasons.contains(.offline) { return .offline }
        if reasons.contains(.failed) { return .failed }
        return ExerciseMediaLibrary.Unavailable.none
    }

    /// Why the video is missing while the image shows; nil otherwise.
    public var videoNotice: ExerciseMediaLibrary.Unavailable? {
        image != nil && videoFile == nil ? videoUnavailable : nil
    }
}
