-- Exercise media (issue #137): a private Storage bucket for the images and
-- videos of a user's own exercises. Objects live under the owner's folder,
-- `<user_id>/<exercise_id>/<file>`, and `exercises.image_uri` / `video_uri`
-- hold that object path. Each user reads and writes only their own folder; the
-- app downloads with the user's session and caches by object path, so a changed
-- file gets a new name instead of being overwritten.
--
-- The shared catalogue's media will live in a separate public bucket once the
-- app has its own content; nothing here is readable by another user.

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'exercise-media',
  'exercise-media',
  false,
  52428800,
  ARRAY['image/jpeg', 'image/png', 'image/webp', 'video/mp4']
)
ON CONFLICT (id) DO NOTHING;

CREATE POLICY "exercise-media: owner reads own folder"
  ON storage.objects FOR SELECT TO authenticated
  USING (
    bucket_id = 'exercise-media'
    AND (storage.foldername(name))[1] = (SELECT auth.uid())::text
  );

CREATE POLICY "exercise-media: owner uploads to own folder"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'exercise-media'
    AND (storage.foldername(name))[1] = (SELECT auth.uid())::text
  );

CREATE POLICY "exercise-media: owner updates own folder"
  ON storage.objects FOR UPDATE TO authenticated
  USING (
    bucket_id = 'exercise-media'
    AND (storage.foldername(name))[1] = (SELECT auth.uid())::text
  )
  WITH CHECK (
    bucket_id = 'exercise-media'
    AND (storage.foldername(name))[1] = (SELECT auth.uid())::text
  );

CREATE POLICY "exercise-media: owner deletes from own folder"
  ON storage.objects FOR DELETE TO authenticated
  USING (
    bucket_id = 'exercise-media'
    AND (storage.foldername(name))[1] = (SELECT auth.uid())::text
  );
