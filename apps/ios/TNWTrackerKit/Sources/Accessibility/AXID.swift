// MARK: - AXID

/// Accessibility identifiers for UI test automation.
/// Format: AXID.<Screen>.<element> where element is lowerCamelCase.
/// NOT localized. Stable across copy changes.
/// Use .accessibilityIdentifier(AXID.Screen.element) on leaf interactive elements only —
/// never on containers with Liquid Glass material (.glassEffect, .background(.regularMaterial), etc.).
public enum AXID {
    public enum Home {
        public static let quickStartButton = "home.quickStartButton"
        public static let nextSessionTitle = "home.nextSessionTitle"
        public static let settingsButton = "home.settingsButton"
    }

    public enum ActiveWorkout {
        public static let elapsedTimer = "activeWorkout.elapsedTimer"
        public static let endButton = "activeWorkout.endButton"
        public static let logSetButton = "activeWorkout.logSetButton"
        public static let exerciseTitle = "activeWorkout.exerciseTitle"
        public static let progressIndicator = "activeWorkout.progressIndicator"
    }

    public enum SetLog {
        public static let repsField = "setLog.repsField"
        public static let weightField = "setLog.weightField"
        public static let saveButton = "setLog.saveButton"
        public static let cancelButton = "setLog.cancelButton"
    }

    public enum RestTimer {
        public static let timerLabel = "restTimer.timerLabel"
        public static let skipButton = "restTimer.skipButton"
    }

    public enum Summary {
        public static let title = "summary.title"
        public static let workoutNameLabel = "summary.workoutNameLabel"
        public static let durationLabel = "summary.durationLabel"
        public static let closeButton = "summary.closeButton"
    }
}
