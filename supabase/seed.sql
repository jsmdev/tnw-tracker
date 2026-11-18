-- =============================================================================
-- Seed data for local development
-- Executed by `supabase db reset` after the migrations.
-- Invented, generic fixtures only: no real workouts, people or providers.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Catalogue exercises (user_id NULL): readable by every signed-in user.
-- Fixed UUIDs so local tooling can reference them.
-- -----------------------------------------------------------------------------
INSERT INTO public.exercises (id, user_id, name, type, equipment, setup_steps, execution_steps, tips) VALUES
('e1000001-0000-4000-8000-000000000001', NULL, 'Barbell Bench Press', 'strength', 'free_weights',
  ARRAY['Lie flat on the bench.', 'Grip the bar slightly wider than shoulder width.'],
  ARRAY['Lower the bar to the chest with control.', 'Press back to full lockout.'],
  NULL),
('e1000002-0000-4000-8000-000000000002', NULL, 'Dumbbell Shoulder Press', 'strength', 'free_weights',
  ARRAY['Sit with back support.', 'Hold the dumbbells at shoulder height, palms forward.'],
  ARRAY['Press up to full extension.', 'Lower with control.'],
  NULL),
('e1000003-0000-4000-8000-000000000003', NULL, 'Chest Press Machine', 'strength', 'connected_machine',
  ARRAY['Adjust the seat so the handles are at mid-chest height.'],
  ARRAY['Press the handles forward until the arms are extended.', 'Return slowly.'],
  ARRAY['Keep the shoulder blades against the pad.']),
('e1000004-0000-4000-8000-000000000004', NULL, 'Lat Pulldown', 'strength', 'machine',
  ARRAY['Grip the bar slightly wider than shoulder width.'],
  ARRAY['Pull the bar to the upper chest.', 'Return with control.'],
  ARRAY['Avoid leaning back too far.']),
('e1000005-0000-4000-8000-000000000005', NULL, 'Seated Row Machine', 'strength', 'connected_machine',
  ARRAY['Sit with the chest against the pad.'],
  ARRAY['Pull the handles towards the torso.', 'Squeeze the shoulder blades, then return.'],
  NULL),
('e1000006-0000-4000-8000-000000000006', NULL, 'Pull-Up', 'bodyweight', 'none',
  ARRAY['Hang from the bar with an overhand grip.'],
  ARRAY['Pull until the chin is above the bar.', 'Lower with control.'],
  NULL),
('e1000007-0000-4000-8000-000000000007', NULL, 'Barbell Back Squat', 'strength', 'free_weights',
  ARRAY['Rest the bar on the upper back.', 'Stand with feet shoulder width apart.'],
  ARRAY['Bend hips and knees to at least parallel.', 'Drive up through the mid-foot.'],
  NULL),
('e1000008-0000-4000-8000-000000000008', NULL, 'Leg Press', 'strength', 'connected_machine',
  ARRAY['Place the feet shoulder width apart on the platform.'],
  ARRAY['Lower until the knees reach about 90 degrees.', 'Press back without locking the knees.'],
  NULL),
('e1000009-0000-4000-8000-000000000009', NULL, 'Leg Curl', 'strength', 'machine',
  ARRAY['Set the pad just above the heels.'],
  ARRAY['Curl the pad towards the glutes.', 'Lower over two to three seconds.'],
  NULL),
('e100000a-0000-4000-8000-00000000000a', NULL, 'Plank', 'bodyweight', 'none',
  ARRAY['Forearms on the floor, elbows under the shoulders.'],
  ARRAY['Hold the body in a straight line.'],
  ARRAY['Do not let the hips sag.']),
('e100000b-0000-4000-8000-00000000000b', NULL, 'Treadmill Run', 'cardio', 'cardio_machine',
  NULL, NULL, NULL),
('e100000c-0000-4000-8000-00000000000c', NULL, 'Rowing Machine', 'cardio', 'cardio_machine',
  NULL,
  ARRAY['Push with the legs, then pull the handle to the lower ribs.'],
  NULL)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.exercise_muscle_groups (exercise_id, muscle, role) VALUES
('e1000001-0000-4000-8000-000000000001', 'chest', 'primary'),
('e1000001-0000-4000-8000-000000000001', 'triceps', 'secondary'),
('e1000001-0000-4000-8000-000000000001', 'shoulders', 'secondary'),
('e1000002-0000-4000-8000-000000000002', 'shoulders', 'primary'),
('e1000002-0000-4000-8000-000000000002', 'triceps', 'secondary'),
('e1000003-0000-4000-8000-000000000003', 'chest', 'primary'),
('e1000003-0000-4000-8000-000000000003', 'triceps', 'secondary'),
('e1000004-0000-4000-8000-000000000004', 'back', 'primary'),
('e1000004-0000-4000-8000-000000000004', 'biceps', 'secondary'),
('e1000005-0000-4000-8000-000000000005', 'back', 'primary'),
('e1000005-0000-4000-8000-000000000005', 'biceps', 'secondary'),
('e1000006-0000-4000-8000-000000000006', 'back', 'primary'),
('e1000006-0000-4000-8000-000000000006', 'biceps', 'secondary'),
('e1000007-0000-4000-8000-000000000007', 'quadriceps', 'primary'),
('e1000007-0000-4000-8000-000000000007', 'glutes', 'primary'),
('e1000007-0000-4000-8000-000000000007', 'hamstrings', 'secondary'),
('e1000008-0000-4000-8000-000000000008', 'quadriceps', 'primary'),
('e1000008-0000-4000-8000-000000000008', 'glutes', 'secondary'),
('e1000009-0000-4000-8000-000000000009', 'hamstrings', 'primary'),
('e100000a-0000-4000-8000-00000000000a', 'core', 'primary'),
('e100000c-0000-4000-8000-00000000000c', 'back', 'primary'),
('e100000c-0000-4000-8000-00000000000c', 'quadriceps', 'secondary')
ON CONFLICT (exercise_id, muscle, role) DO NOTHING;
