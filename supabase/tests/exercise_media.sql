-- pgTAP: the private exercise-media bucket (issue #137). Each user reads,
-- uploads, renames and deletes objects only under their own `<user_id>/`
-- folder; anonymous clients see nothing.
BEGIN;

SELECT plan(14);

-- Storage blocks SQL deletes unless this is set (the Storage API sets it);
-- the policies below still decide which rows a user may delete.
SET LOCAL storage.allow_delete_query = 'true';

INSERT INTO auth.users (
  id, instance_id, email, encrypted_password, email_confirmed_at,
  created_at, updated_at, raw_app_meta_data, raw_user_meta_data, is_super_admin, role
) VALUES
  ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'one@example.test', '', now(), now(), now(), '{}', '{}', false, 'authenticated'),
  ('00000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000',
   'two@example.test', '', now(), now(), now(), '{}', '{}', false, 'authenticated');

-- Objects of both users, written as postgres (RLS bypassed).
INSERT INTO storage.objects (bucket_id, name, owner_id) VALUES
  ('exercise-media', '00000000-0000-0000-0000-000000000001/e1/image-1.jpeg', '00000000-0000-0000-0000-000000000001'),
  ('exercise-media', '00000000-0000-0000-0000-000000000002/e2/image-1.jpeg', '00000000-0000-0000-0000-000000000002');

SELECT is(
  (SELECT public FROM storage.buckets WHERE id = 'exercise-media'),
  false, 'the exercise-media bucket is private'
);
SELECT is(
  (SELECT allowed_mime_types FROM storage.buckets WHERE id = 'exercise-media'),
  ARRAY['image/jpeg', 'image/png', 'image/webp', 'video/mp4'],
  'the bucket accepts only images and MP4 videos'
);

-- ---------------------------------------------------------------
-- User one
-- ---------------------------------------------------------------
SET LOCAL role = authenticated;
SET LOCAL "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}';

SELECT is(
  (SELECT array_agg(name) FROM storage.objects WHERE bucket_id = 'exercise-media'),
  ARRAY['00000000-0000-0000-0000-000000000001/e1/image-1.jpeg'],
  'a user sees only the objects in their own folder'
);
SELECT lives_ok(
  $$INSERT INTO storage.objects (bucket_id, name, owner_id)
    VALUES ('exercise-media', '00000000-0000-0000-0000-000000000001/e1/video-1.mp4',
            '00000000-0000-0000-0000-000000000001')$$,
  'a user uploads into their own folder'
);
SELECT throws_ok(
  $$INSERT INTO storage.objects (bucket_id, name, owner_id)
    VALUES ('exercise-media', '00000000-0000-0000-0000-000000000002/e2/video-1.mp4',
            '00000000-0000-0000-0000-000000000001')$$,
  '42501', NULL, 'a user cannot upload into another user''s folder'
);
SELECT throws_ok(
  $$INSERT INTO storage.objects (bucket_id, name, owner_id)
    VALUES ('exercise-media', 'e1/image-2.jpeg', '00000000-0000-0000-0000-000000000001')$$,
  '42501', NULL, 'a user cannot upload outside any user folder'
);
SELECT throws_ok(
  $$UPDATE storage.objects SET name = '00000000-0000-0000-0000-000000000002/e1/moved.jpeg'
    WHERE name = '00000000-0000-0000-0000-000000000001/e1/image-1.jpeg'$$,
  '42501', NULL, 'a user cannot move an object into another user''s folder'
);
SELECT lives_ok(
  $$UPDATE storage.objects SET name = '00000000-0000-0000-0000-000000000001/e1/image-1b.jpeg'
    WHERE name = '00000000-0000-0000-0000-000000000001/e1/image-1.jpeg'$$,
  'a user renames an object within their own folder'
);

UPDATE storage.objects SET name = '00000000-0000-0000-0000-000000000001/e2/hijack.jpeg'
  WHERE name = '00000000-0000-0000-0000-000000000002/e2/image-1.jpeg';
DELETE FROM storage.objects WHERE name = '00000000-0000-0000-0000-000000000002/e2/image-1.jpeg';
SELECT lives_ok(
  $$DELETE FROM storage.objects WHERE name = '00000000-0000-0000-0000-000000000001/e1/video-1.mp4'$$,
  'a user deletes an object from their own folder'
);

-- ---------------------------------------------------------------
-- User two
-- ---------------------------------------------------------------
SET LOCAL "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000000002","role":"authenticated"}';

SELECT is(
  (SELECT array_agg(name) FROM storage.objects WHERE bucket_id = 'exercise-media'),
  ARRAY['00000000-0000-0000-0000-000000000002/e2/image-1.jpeg'],
  'another user''s update and delete did not touch this user''s object'
);
SELECT is(
  (SELECT count(*)::int FROM storage.objects WHERE name LIKE '00000000-0000-0000-0000-000000000001/%'),
  0, 'user two sees none of user one''s objects'
);

-- ---------------------------------------------------------------
-- Anonymous
-- ---------------------------------------------------------------
SET LOCAL role = anon;
SET LOCAL "request.jwt.claims" = '{"role":"anon"}';

SELECT is(
  (SELECT count(*)::int FROM storage.objects WHERE bucket_id = 'exercise-media'),
  0, 'anonymous clients see no exercise media'
);
SELECT throws_ok(
  $$INSERT INTO storage.objects (bucket_id, name)
    VALUES ('exercise-media', '00000000-0000-0000-0000-000000000001/e1/anon.jpeg')$$,
  '42501', NULL, 'anonymous clients cannot upload'
);

RESET role;
SELECT is(
  (SELECT count(*)::int FROM storage.objects WHERE bucket_id = 'exercise-media'),
  2, 'both users'' objects still exist after the denied writes'
);

SELECT * FROM finish();
ROLLBACK;
