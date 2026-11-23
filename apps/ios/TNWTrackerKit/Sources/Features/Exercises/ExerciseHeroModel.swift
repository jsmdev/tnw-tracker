import Foundation
import Observation
import UIKit

/// The media of the exercise sheet (#137 S7, #182 S9): the photo, always at the
/// top, else a neutral placeholder saying why there is none; and the video, in
/// its own section, loaded only when the user opens it. Both are downloaded
/// on demand, the first time they show, and read from the account's files
/// from then on, offline too.
@Observable
@MainActor
public final class ExerciseHeroModel {
    public private(set) var image: UIImage?
    public private(set) var videoFile: URL?
    /// True until the photo's first load ends, when there is one to load.
    public private(set) var isLoading: Bool
    /// True while the video is being read or downloaded.
    public private(set) var isLoadingVideo = false
    public private(set) var imageUnavailable: ExerciseMediaLibrary.Unavailable?
    public private(set) var videoUnavailable: ExerciseMediaLibrary.Unavailable?

    private let library: ExerciseMediaLibrary
    private let imagePath: String?
    private let videoPath: String?

    public init(content: ExerciseSheetContent, library: ExerciseMediaLibrary) {
        self.library = library
        imagePath = content.imagePath
        videoPath = content.videoPath
        isLoading = content.imagePath != nil
        // Shown at once when this account decoded it before: no flash of the placeholder.
        image = content.imagePath.flatMap(library.memoryCachedImage(path:))
    }

    /// True when the exercise has a video, so the sheet offers its section.
    public var hasVideo: Bool {
        videoPath != nil
    }

    /// Loads the photo.
    public func load() async {
        isLoading = true
        defer { isLoading = false }
        guard let imagePath else { return }
        do {
            image = try await library.image(path: imagePath)
        } catch {
            imageUnavailable = ExerciseMediaLibrary.Unavailable(error)
        }
    }

    /// Loads the video, once it is asked for; a loaded video is not loaded again.
    public func loadVideo() async {
        guard let videoPath, videoFile == nil, !isLoadingVideo else { return }
        isLoadingVideo = true
        defer { isLoadingVideo = false }
        do {
            videoFile = try await library.videoFile(path: videoPath)
            videoUnavailable = nil
        } catch {
            videoUnavailable = ExerciseMediaLibrary.Unavailable(error)
        }
    }

    /// Why the photo area shows the placeholder; nil while loading, or when the
    /// photo shows. The video never takes the photo's place.
    public var placeholder: ExerciseMediaLibrary.Unavailable? {
        guard !isLoading, image == nil else { return nil }
        return imageUnavailable ?? ExerciseMediaLibrary.Unavailable.none
    }

    /// Why the video section has no video to play; nil otherwise.
    public var videoNotice: ExerciseMediaLibrary.Unavailable? {
        videoFile == nil ? videoUnavailable : nil
    }
}
