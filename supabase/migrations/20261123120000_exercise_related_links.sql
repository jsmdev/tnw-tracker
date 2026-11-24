-- Related links of an exercise (format 1.2, S10): 1.1's related videos become
-- links to any external information (a video, an article…), with the same
-- `{ title, url, source }` shape. Renamed in place, so the stored lists stay.
-- The app still reads this column and never writes it.

ALTER FUNCTION public.related_videos_are_valid(jsonb) RENAME TO related_links_are_valid;

COMMENT ON FUNCTION public.related_links_are_valid(jsonb) IS
  'True when a value of exercises.related_links follows the format: a non-empty list of distinct { title, url (https), source }.';

ALTER TABLE public.exercises RENAME COLUMN related_videos TO related_links;

ALTER TABLE public.exercises
  RENAME CONSTRAINT exercises_related_videos_valid TO exercises_related_links_valid;

COMMENT ON COLUMN public.exercises.related_links IS
  'Format exercise.relatedLinks (1.2): curated external links, NULL when none. Read-only for the app.';
