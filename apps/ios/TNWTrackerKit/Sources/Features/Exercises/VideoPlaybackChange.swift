/// What the exercise video does when its section opens or closes (#182 S9).
/// "Ver vídeo" shows the video and starts it. While the section stays open, a
/// pause or play is the user's own. Closing pauses it, unless it went on in
/// Picture in Picture.
public enum VideoPlaybackChange: Equatable, Sendable {
    case play
    case pause
    case none

    public static func when(wasOpen: Bool, isOpen: Bool, inPictureInPicture: Bool) -> Self {
        if isOpen { return wasOpen ? .none : .play }
        return inPictureInPicture ? .none : .pause
    }
}
