import Testing
@testable import TNWTrackerKit

/// #182 S9: "Ver vídeo" shows the video and starts it; closing the section
/// pauses it, unless it went on in Picture in Picture.
@Suite("Exercise video playback")
struct VideoPlaybackChangeTests {
    @Test func openingTheSectionPlays() {
        #expect(VideoPlaybackChange.when(wasOpen: false, isOpen: true, inPictureInPicture: false) == .play)
    }

    @Test func stayingOpenLeavesTheUsersChoice() {
        #expect(VideoPlaybackChange.when(wasOpen: true, isOpen: true, inPictureInPicture: false) == .none)
    }

    @Test func closingPausesUnlessInPictureInPicture() {
        #expect(VideoPlaybackChange.when(wasOpen: true, isOpen: false, inPictureInPicture: false) == .pause)
        #expect(VideoPlaybackChange.when(wasOpen: true, isOpen: false, inPictureInPicture: true) == .none)
        #expect(VideoPlaybackChange.when(wasOpen: false, isOpen: false, inPictureInPicture: false) == .pause)
    }
}
