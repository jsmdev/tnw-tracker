-- pgTAP: unicidad de personal_records (estado actual = 1 fila por combo)
BEGIN;

SELECT plan(3);

-- Seed: auth.users dispara el trigger que crea public.users
INSERT INTO auth.users (
    id, instance_id, email, encrypted_password,
    email_confirmed_at, created_at, updated_at,
    raw_app_meta_data, raw_user_meta_data,
    is_super_admin, role
)
VALUES (
    '00000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000000',
    'pr-user@test.com', '',
    now(), now(), now(),
    '{}', '{}', false, 'authenticated'
);

INSERT INTO public.exercises (id, user_id, name, category)
VALUES ('eeeeeeee-0000-0000-0000-000000000001',
        '00000000-0000-0000-0000-000000000001', 'Bench Press', 'Push');

-- Primer récord: válido
INSERT INTO public.personal_records (user_id, exercise_id, record_type, value, weight_unit, achieved_at)
VALUES ('00000000-0000-0000-0000-000000000001',
        'eeeeeeee-0000-0000-0000-000000000001',
        'max_weight', 100, 'kg', now());

-- 1. Duplicar (user, exercise, record_type) debe ser rechazado por el UNIQUE
SELECT throws_ok(
    $$ INSERT INTO public.personal_records (user_id, exercise_id, record_type, value, weight_unit, achieved_at)
       VALUES ('00000000-0000-0000-0000-000000000001',
               'eeeeeeee-0000-0000-0000-000000000001',
               'max_weight', 120, 'kg', now()) $$,
    '23505',
    NULL,
    'duplicate (user, exercise, max_weight) is rejected by unique constraint'
);

-- 2. Otro record_type para el mismo ejercicio: permitido
SELECT lives_ok(
    $$ INSERT INTO public.personal_records (user_id, exercise_id, record_type, value, weight_unit, achieved_at)
       VALUES ('00000000-0000-0000-0000-000000000001',
               'eeeeeeee-0000-0000-0000-000000000001',
               'max_reps', 12, 'kg', now()) $$,
    'a different record_type for the same exercise is allowed'
);

-- 3. UPSERT (ON CONFLICT) actualiza la fila vigente en lugar de duplicar
INSERT INTO public.personal_records (user_id, exercise_id, record_type, value, weight_unit, achieved_at)
VALUES ('00000000-0000-0000-0000-000000000001',
        'eeeeeeee-0000-0000-0000-000000000001',
        'max_weight', 90, 'kg', now())
ON CONFLICT (user_id, exercise_id, record_type)
DO UPDATE SET value = EXCLUDED.value;

SELECT is(
    (SELECT value FROM public.personal_records
     WHERE user_id = '00000000-0000-0000-0000-000000000001'
       AND exercise_id = 'eeeeeeee-0000-0000-0000-000000000001'
       AND record_type = 'max_weight')::numeric,
    90::numeric,
    'upsert lowers the record value (anti-fantasma) without duplicating'
);

SELECT * FROM finish();
ROLLBACK;
