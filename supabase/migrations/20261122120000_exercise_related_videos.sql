-- Related videos of an exercise (format 1.1, issue #182): external videos that
-- explain it, curated with the catalogue. A list of `{ title, url, source }`
-- objects, in order, none twice; NULL when the exercise has none, never an
-- empty list.
-- The app reads this column and never writes it, so a push cannot erase it.

CREATE FUNCTION public.related_videos_are_valid(videos jsonb)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT CASE
    WHEN jsonb_typeof(videos) <> 'array' OR jsonb_array_length(videos) = 0 THEN false
    -- No video twice, as the format's uniqueItems and the app require.
    WHEN jsonb_array_length(videos)
      <> (SELECT count(DISTINCT video) FROM jsonb_array_elements(videos) AS video) THEN false
    ELSE NOT EXISTS (
      SELECT 1
      FROM jsonb_array_elements(videos) AS video
      WHERE CASE
        WHEN jsonb_typeof(video) <> 'object' THEN true
        ELSE (SELECT count(*) FROM jsonb_object_keys(video)) <> 3
          OR jsonb_typeof(video -> 'title') IS DISTINCT FROM 'string'
          OR jsonb_typeof(video -> 'url') IS DISTINCT FROM 'string'
          OR jsonb_typeof(video -> 'source') IS DISTINCT FROM 'string'
          OR char_length(video ->> 'title') = 0
          OR char_length(video ->> 'source') = 0
          OR (video ->> 'url') !~ '^https://[^[:space:]]+$'
      END
    )
  END
$$;

COMMENT ON FUNCTION public.related_videos_are_valid(jsonb) IS
  'True when a value of exercises.related_videos follows the format: a non-empty list of distinct { title, url (https), source }.';

ALTER TABLE public.exercises
  ADD COLUMN related_videos jsonb
  CONSTRAINT exercises_related_videos_valid CHECK (public.related_videos_are_valid(related_videos));

COMMENT ON COLUMN public.exercises.related_videos IS
  'Format exercise.relatedVideos (1.1): curated external videos, NULL when none. Read-only for the app.';
