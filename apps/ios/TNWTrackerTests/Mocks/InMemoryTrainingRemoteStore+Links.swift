import Foundation
@testable import TNWTrackerKit

/// Exercise settings and personal links on the in-memory server, as the checks
/// of supabase/migrations/20261124120000_exercise_links.sql refuse links.
extension InMemoryTrainingRemoteStore {
    /// The user's own data about an exercise: settings and links name an
    /// exercise the user can see.
    func checkUserData(_ row: some RemoteRow) throws {
        switch row {
        case let setting as RemoteExerciseSettingRow:
            try requireExercise(setting.exerciseId, .exerciseSettings)
        case let link as RemoteExerciseLinkRow:
            try check(link)
        default:
            break
        }
    }

    /// Row-level security first (an exercise the user can see, 42501), then the
    /// column checks (23514): a title and a source that are not blank, an
    /// `https` address with no spaces, a position from 1. No uniqueness on url.
    func check(_ link: RemoteExerciseLinkRow) throws {
        try requireExercise(link.exerciseId, .exerciseLinks)
        let blank = { (text: String) in text.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !blank(link.title), !blank(link.source), RelatedLink.isHTTPSAddress(link.url), link.position >= 1 else {
            throw RemoteStoreError.rejected(code: "23514", message: "exercise_links check")
        }
    }
}
