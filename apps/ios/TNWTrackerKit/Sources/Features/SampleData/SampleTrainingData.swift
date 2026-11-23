#if DEBUG
    import Foundation

    /// Invented training data for previews, tests and UI tests.
    /// Every name and number is made up; nothing comes from a real workout or provider.
    /// Built through the repositories, so the sample data obeys the same rules as real data.
    @MainActor
    public enum SampleTrainingData {
        /// Provider slug of the sample imported data.
        public static let importProvider = "machines-atlas"

        public enum ExerciseID {
            public static let gobletSquat = fixed("a0000000-0000-4000-8000-000000000001")
            public static let benchPress = fixed("a0000000-0000-4000-8000-000000000002")
            public static let chestPress = fixed("a0000000-0000-4000-8000-000000000003")
            public static let seatedRow = fixed("a0000000-0000-4000-8000-000000000004")
            public static let plank = fixed("a0000000-0000-4000-8000-000000000005")
            public static let pushUp = fixed("a0000000-0000-4000-8000-000000000006")
            public static let rowingMachine = fixed("a0000000-0000-4000-8000-000000000007")
        }

        public enum RoutineID {
            public static let fullBodyA = fixed("b0000000-0000-4000-8000-000000000001")
            public static let fullBodyB = fixed("b0000000-0000-4000-8000-000000000002")
        }

        public static var exercises: [Exercise] {
            [
                Exercise(
                    id: ExerciseID.gobletSquat, name: "Goblet Squat", type: .strength, equipment: .freeWeights,
                    muscleGroups: [
                        .init(muscle: .quadriceps, role: .primary),
                        .init(muscle: .glutes, role: .secondary)
                    ],
                    instructions: ExerciseInstructions(
                        setup: ["Hold the weight close to the chest."],
                        execution: ["Sit down between the knees.", "Stand up tall."],
                        tips: ["Keep the heels on the floor."]
                    )
                ),
                Exercise(
                    id: ExerciseID.benchPress, name: "Bench Press", type: .strength, equipment: .freeWeights,
                    muscleGroups: [.init(muscle: .chest, role: .primary), .init(muscle: .triceps, role: .secondary)]
                ),
                Exercise(
                    id: ExerciseID.chestPress,
                    externalRef: ExternalRef(provider: importProvider, id: "ex-100"),
                    name: "Chest Press Machine", type: .strength, equipment: .connectedMachine,
                    muscleGroups: [.init(muscle: .chest, role: .primary), .init(muscle: .shoulders, role: .secondary)],
                    media: ExerciseMedia(imageURI: "exercises/chest-press.jpg", videoURI: "exercises/chest-press.mp4"),
                    // Invented: a YouTube address shaped like a real one, and a link to any other site.
                    relatedVideos: [
                        RelatedVideo(
                            title: "Chest press, step by step",
                            url: "https://www.youtube.com/watch?v=Inv3nted_01",
                            source: "YouTube"
                        ),
                        RelatedVideo(
                            title: "Chest press guide",
                            url: "https://example.test/chest-press-guide",
                            source: "Example"
                        )
                    ]
                ),
                Exercise(
                    id: ExerciseID.seatedRow,
                    externalRef: ExternalRef(provider: importProvider, id: "ex-200"),
                    name: "Seated Row Machine", type: .strength, equipment: .connectedMachine,
                    muscleGroups: [.init(muscle: .back, role: .primary), .init(muscle: .biceps, role: .secondary)]
                ),
                Exercise(
                    id: ExerciseID.plank, name: "Plank", type: .bodyweight, equipment: Equipment.none,
                    muscleGroups: [.init(muscle: .core, role: .primary)]
                ),
                Exercise(
                    id: ExerciseID.pushUp, name: "Push-Up", type: .bodyweight, equipment: Equipment.none,
                    muscleGroups: [.init(muscle: .chest, role: .primary)]
                ),
                Exercise(
                    id: ExerciseID.rowingMachine, name: "Rowing Machine", type: .cardio, equipment: .cardioMachine
                )
            ]
        }

        public static var routines: [Routine] {
            [
                Routine(
                    id: RoutineID.fullBodyA, name: "Full Body A", description: "Squat, press and a plank.",
                    items: [
                        RoutineItem(
                            order: 1,
                            exerciseId: ExerciseID.gobletSquat,
                            targetSets: 3,
                            targetReps: RepRange(min: 8, max: 12),
                            targetWeight: .kg(16),
                            restSeconds: 90
                        ),
                        RoutineItem(
                            order: 2,
                            exerciseId: ExerciseID.chestPress,
                            targetSets: 3,
                            targetReps: RepRange(min: 8, max: 10),
                            restSeconds: 90
                        ),
                        RoutineItem(
                            order: 3,
                            exerciseId: ExerciseID.plank,
                            targetSets: 2,
                            targetDurationSeconds: 45,
                            restSeconds: 60
                        )
                    ]
                ),
                Routine(
                    id: RoutineID.fullBodyB, name: "Full Body B",
                    items: [
                        RoutineItem(
                            order: 1,
                            exerciseId: ExerciseID.benchPress,
                            targetSets: 3,
                            targetReps: RepRange(min: 6, max: 8),
                            restSeconds: 120
                        ),
                        RoutineItem(
                            order: 2,
                            exerciseId: ExerciseID.seatedRow,
                            targetSets: 3,
                            targetReps: RepRange(min: 10, max: 12),
                            restSeconds: 90
                        ),
                        RoutineItem(order: 3, exerciseId: ExerciseID.rowingMachine, targetDurationSeconds: 600)
                    ]
                )
            ]
        }

        /// Loads the sample data into an empty store; does nothing if it already holds data.
        public static func loadIfEmpty(into store: TrainingStore, now: Date = Date()) throws {
            guard try store.isEmpty() else { return }
            try load(into: store, now: now)
        }

        /// Replaces every exercise, routine and session with the sample data.
        public static func replaceAll(in store: TrainingStore, now: Date = Date()) throws {
            try store.deleteAllTrainingData()
            try load(into: store, now: now)
        }

        private static func load(into store: TrainingStore, now: Date) throws {
            for exercise in exercises {
                try store.exercises.save(exercise)
            }
            for routine in routines {
                try store.routines.save(routine)
            }
            try loadHistory(into: store.sessions, now: now)
        }

        /// Two completed sessions, Full Body A four days ago and Full Body B two days
        /// ago, so "Próxima sesión" proposes Full Body A:
        /// - Full Body A: squats, a chest press logged by hand and also imported
        ///   (reconciled by default), and a skipped plank.
        /// - Full Body B: bench press, a row swapped for push-ups, removed cardio and an added timed plank.
        private static func loadHistory(into sessions: any SessionRepositoryProtocol, now: Date) throws {
            let zone = TimeZone(identifier: "Europe/Madrid") ?? .gmt
            let day: TimeInterval = 86400

            let startA = now.addingTimeInterval(-4 * day)
            let first = try sessions.startSession(
                routineId: RoutineID.fullBodyA,
                name: "Full Body A",
                at: startA,
                timeZone: zone
            )
            for (index, reps) in [12, 10, 10].enumerated() {
                try sessions.logManualSet(
                    SetValues(reps: reps, weight: .kg(16), rir: 2),
                    exerciseId: ExerciseID.gobletSquat, sessionId: first.id,
                    at: startA.addingTimeInterval(Double(index + 1) * 180)
                )
            }
            for reps in [10, 9] {
                try sessions.logManualSet(
                    SetValues(reps: reps, weight: .kg(40)),
                    exerciseId: ExerciseID.chestPress, sessionId: first.id, at: startA.addingTimeInterval(900)
                )
            }
            try sessions.importEntry(
                ImportedEntry(
                    exerciseId: ExerciseID.chestPress,
                    externalRef: ExternalRef(provider: importProvider, id: "e-5001"),
                    sets: (1 ... 3).map { order in
                        ImportedSet(
                            externalRef: ExternalRef(provider: importProvider, id: "e-5001#\(order)"),
                            order: order,
                            values: SetValues(reps: 10, weight: .kg(42.5), durationSeconds: 38)
                        )
                    }
                ),
                into: first.id
            )
            try sessions.finishSession(id: first.id, at: startA.addingTimeInterval(3000), durationSeconds: 2700)

            try loadFullBodyB(into: sessions, startB: now.addingTimeInterval(-2 * day), zone: zone)
        }

        /// The Full Body B session of `loadHistory`.
        private static func loadFullBodyB(
            into sessions: any SessionRepositoryProtocol,
            startB: Date,
            zone: TimeZone
        ) throws {
            let second = try sessions.startSession(
                routineId: RoutineID.fullBodyB,
                name: "Full Body B",
                at: startB,
                timeZone: zone
            )
            for reps in [8, 8, 7] {
                try sessions.logManualSet(
                    SetValues(reps: reps, weight: .kg(60), rir: 1),
                    exerciseId: ExerciseID.benchPress, sessionId: second.id, at: startB.addingTimeInterval(600)
                )
            }
            if let row = try sessions.session(id: second.id)?.entries
                .first(where: { $0.exerciseId == ExerciseID.seatedRow }) {
                try sessions.replaceExercise(entryId: row.id, with: ExerciseID.pushUp)
            }
            for reps in [15, 12] {
                try sessions.logManualSet(
                    SetValues(reps: reps), exerciseId: ExerciseID.pushUp, sessionId: second.id,
                    at: startB.addingTimeInterval(1500)
                )
            }
            if let cardio = try sessions.session(id: second.id)?.entries
                .first(where: { $0.exerciseId == ExerciseID.rowingMachine }) {
                try sessions.removeEntry(id: cardio.id)
            }
            try sessions.logManualSet(
                SetValues(durationSeconds: 300), exerciseId: ExerciseID.plank, sessionId: second.id,
                at: startB.addingTimeInterval(2000)
            )
            try sessions.finishSession(id: second.id, at: startB.addingTimeInterval(2600), durationSeconds: 2400)
        }

        private nonisolated static func fixed(_ uuid: String) -> UUID {
            guard let id = UUID(uuidString: uuid) else { preconditionFailure("Invalid sample UUID \(uuid)") }
            return id
        }
    }
#endif
