-- =============================================================================
-- Seed data for local development
-- This file is executed by `supabase db reset` after migrations.
-- Do NOT use real/production data here — only safe development fixtures.
-- =============================================================================

-- =============================================================================
-- Global Exercises (user_id = NULL) — visible to all authenticated users
-- Fixed UUIDs so the TypeScript seed script can reference them.
-- Idempotent via ON CONFLICT (id) DO NOTHING.
-- =============================================================================

-- Push
INSERT INTO public.exercises (id, user_id, name, category, muscle_groups, instructions, is_public) VALUES
('e1000001-0000-0000-0000-000000000001', NULL, 'Barbell Bench Press',     'Push', ARRAY['chest','front_delts','triceps'],               'Lie flat on bench. Grip bar slightly wider than shoulder-width. Lower to chest with controlled eccentric. Press back to full lockout.', true),
('e1000002-0000-0000-0000-000000000002', NULL, 'Dumbbell Shoulder Press', 'Push', ARRAY['front_delts','lateral_delts','triceps'],       'Seated with back support. Dumbbells at shoulder height, palms forward. Press up to full extension. Lower with control.', true),
('e1000003-0000-0000-0000-000000000003', NULL, 'Incline Dumbbell Press',  'Push', ARRAY['upper_chest','front_delts','triceps'],         'Bench set at 30-45°. Dumbbells at chest level, elbows ~45° from torso. Press up. Lower to feel deep stretch in upper pecs.', true),
('e1000004-0000-0000-0000-000000000004', NULL, 'Tricep Pushdown',         'Push', ARRAY['triceps','lateral_head'],                      'Stand facing cable. Grip straight or rope attachment at upper-chest height. Elbows pinned to sides. Push down to full extension. Pause and squeeze.', true),
('e1000005-0000-0000-0000-000000000005', NULL, 'Lateral Raises',          'Push', ARRAY['lateral_delts'],                               'Stand with slight hinge forward. Dumbbells at sides. Lead with elbows, raising to shoulder height (not above). Control the negative.', true),
('e1000006-0000-0000-0000-000000000006', NULL, 'Overhead Tricep Extension','Push', ARRAY['triceps','long_head'],                          'Seated or standing. Dumbbell behind head, elbows forward. Extend to full lockout. Keep upper arms stationary.', true),

-- Pull
('e1000007-0000-0000-0000-000000000007', NULL, 'Barbell Row',             'Pull', ARRAY['lats','rhomboids','biceps','rear_delts'],     'Hinge at hips with flat back (~45°). Grip bar shoulder-width. Pull to lower sternum, squeeze shoulder blades. Lower with control.', true),
('e1000008-0000-0000-0000-000000000008', NULL, 'Pull-Up',                 'Pull', ARRAY['lats','biceps','rhomboids'],                   'Hang from bar with overhand grip, shoulder-width. Initiate with scapular depression, pull chin above bar. Control eccentric. Add weight if bodyweight too easy.', true),
('e1000009-0000-0000-0000-000000000009', NULL, 'Lat Pulldown',            'Pull', ARRAY['lats','biceps'],                               'Slightly wider than shoulder-width overhand grip. Lean back ~15°. Pull bar to upper chest, squeeze at bottom. Avoid excessive lean.', true),
('e100000a-0000-0000-0000-00000000000a', NULL, 'Seated Cable Row',        'Pull', ARRAY['rhomboids','lats','biceps','rear_delts'],     'Feet planted, knees slightly bent. Neutral grip attachment. Pull handle to lower abdomen, squeeze shoulder blades. Do not rock torso.', true),
('e100000b-0000-0000-0000-00000000000b', NULL, 'Face Pull',               'Pull', ARRAY['rear_delts','rhomboids','rotator_cuff'],       'Rope attachment at upper-chest height. Pull toward face, externally rotating so thumbs point behind you. Upper back and rear delts — not arms.', true),

-- Legs
('e100000c-0000-0000-0000-00000000000c', NULL, 'Barbell Back Squat',      'Legs', ARRAY['quadriceps','glutes','hamstrings','core'],    'Bar on upper traps. Feet shoulder-width. Break at hips and knees simultaneously. Descend to at least parallel depth. Drive through midfoot to stand.', true),
('e100000d-0000-0000-0000-00000000000d', NULL, 'Romanian Deadlift',       'Legs', ARRAY['hamstrings','glutes','erectors'],              'Bar at hip level. Soft knees. Push hips back, letting bar slide down thighs. Feel hamstring stretch. Drive hips forward to lockout. Keep bar close.', true),
('e100000e-0000-0000-0000-00000000000e', NULL, 'Leg Press',               'Legs', ARRAY['quadriceps','glutes'],                         'Seated in machine. Feet shoulder-width, mid-platform. Lower until knees ~90°, do not let lower back round. Press through heels to full extension without locking knees.', true),
('e100000f-0000-0000-0000-00000000000f', NULL, 'Walking Lunge',           'Legs', ARRAY['quadriceps','glutes','hamstrings'],            'Hold dumbbells at sides. Step forward into lunge, rear knee nearly touches floor. Front shin vertical. Drive through front heel to stand and step forward with opposite leg.', true),
('e1000010-0000-0000-0000-000000000010', NULL, 'Leg Curl',                'Legs', ARRAY['hamstrings'],                                  'Lying or seated machine. Ankle pad just above heel. Curl pad toward glutes. Pause at peak contraction. Lower with 2-3 second eccentric.', true),

-- Core
('e1000011-0000-0000-0000-000000000011', NULL, 'Plank',                   'Core', ARRAY['rectus_abdominis','transverse_abdominis'],     'Forearms on floor, elbows under shoulders. Body in straight line from head to heels. Engage glutes and quads. Hold without sagging hips or raising them.', true),
('e1000012-0000-0000-0000-000000000012', NULL, 'Hanging Leg Raise',       'Core', ARRAY['rectus_abdominis','hip_flexors'],              'Hang from pull-up bar. With straight or bent legs, raise them until parallel to floor or higher. Control the negative — no swinging.', true),
('e1000013-0000-0000-0000-000000000013', NULL, 'Cable Crunch',            'Core', ARRAY['rectus_abdominis'],                            'Kneel facing cable with rope attachment behind head. Crunch torso down toward knees. Round spine — flex the abs, do not hip hinge. Control eccentric.', true)
ON CONFLICT (id) DO NOTHING;

-- =============================================================================
-- Motivational Quotes
-- =============================================================================

INSERT INTO public.motivational_quotes (id, content, author) VALUES
('c1000001-0000-0000-0000-000000000001', 'The only bad workout is the one that didn''t happen.',         NULL),
('c1000002-0000-0000-0000-000000000002', 'Strength does not come from the body. It comes from the will.', NULL),
('c1000003-0000-0000-0000-000000000003', 'The body achieves what the mind believes.',                   'Napoleon Hill'),
('c1000004-0000-0000-0000-000000000004', 'Success is usually the culmination of controlling failure.',  'Sylvester Stallone'),
('c1000005-0000-0000-0000-000000000005', 'The last three or four reps is what makes the muscle grow.',   'Arnold Schwarzenegger'),
('c1000006-0000-0000-0000-000000000006', 'What seems impossible today will one day be your warm-up.',    NULL),
('c1000007-0000-0000-0000-000000000007', 'Discipline is doing what needs to be done, even if you don''t want to do it.', NULL),
('c1000008-0000-0000-0000-000000000008', 'You don''t have to be great to start, but you have to start to be great.', 'Zig Ziglar')
ON CONFLICT (id) DO NOTHING;