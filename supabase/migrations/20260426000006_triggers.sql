-- Migration: Triggers — updated_at, new auth user, immutable completed_at

-- Universal updated_at function
CREATE OR REPLACE FUNCTION public.tg_set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END $$;

-- Apply updated_at trigger to all tables that have the column
DO $$
DECLARE
  t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY['users', 'exercises', 'plans', 'routines', 'sessions'] LOOP
    -- Drop first to make this idempotent
    EXECUTE format(
      'DROP TRIGGER IF EXISTS set_updated_at ON public.%I;', t);
    EXECUTE format(
      'CREATE TRIGGER set_updated_at
       BEFORE UPDATE ON public.%I
       FOR EACH ROW EXECUTE FUNCTION public.tg_set_updated_at();', t);
  END LOOP;
END $$;

-- Handle new auth user → insert into public.users
CREATE OR REPLACE FUNCTION public.tg_handle_new_auth_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public AS $$
BEGIN
  INSERT INTO public.users (id, email)
  VALUES (NEW.id, NEW.email)
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.tg_handle_new_auth_user();

-- Immutability of completed_at in exercise_sets
CREATE OR REPLACE FUNCTION public.tg_immutable_completed_at()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.completed_at IS NOT NULL AND NEW.completed_at <> OLD.completed_at THEN
    RAISE EXCEPTION 'completed_at is immutable once set';
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS immutable_completed_at ON public.exercise_sets;
CREATE TRIGGER immutable_completed_at
  BEFORE UPDATE ON public.exercise_sets
  FOR EACH ROW EXECUTE FUNCTION public.tg_immutable_completed_at();
