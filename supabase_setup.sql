-- ============================================================
-- Sanctuary Project Hub — Supabase Database Setup
-- Run this in your Supabase SQL Editor (supabase.com/dashboard)
-- ============================================================

-- 1. PROFILES TABLE
CREATE TABLE IF NOT EXISTS public.profiles (
  id       uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  org_id   text NOT NULL DEFAULT 'sanctuary',
  email    text,
  name     text,
  role     text DEFAULT 'member',
  created_at timestamptz DEFAULT now()
);

-- Add any missing columns (safe if they already exist)
DO $$ BEGIN
  ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS org_id text NOT NULL DEFAULT 'sanctuary';
  ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS email text;
  ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS name text;
  ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS role text DEFAULT 'member';
  ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS created_at timestamptz DEFAULT now();
END $$;

-- 2. PROJECTS TABLE
CREATE TABLE IF NOT EXISTS public.projects (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id     text NOT NULL DEFAULT 'sanctuary',
  name       text NOT NULL,
  status     text DEFAULT 'in_progress',
  deadline   date,
  created_by uuid REFERENCES auth.users(id),
  created_at timestamptz DEFAULT now()
);

-- 3. PROJECT ASSIGNMENTS TABLE
CREATE TABLE IF NOT EXISTS public.project_assignments (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id uuid NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
  user_id    uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at timestamptz DEFAULT now(),
  UNIQUE(project_id, user_id)
);

-- 4. UPDATES TABLE
CREATE TABLE IF NOT EXISTS public.updates (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id   uuid NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
  author_id    uuid REFERENCES auth.users(id),
  author_name  text,
  content      text,
  created_at   timestamptz DEFAULT now()
);

-- 5. DOCUMENTS TABLE
CREATE TABLE IF NOT EXISTS public.documents (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id    uuid NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
  name          text,
  url           text,
  added_by_name text,
  created_at    timestamptz DEFAULT now()
);

-- 6. FEEDBACK LOGS TABLE
CREATE TABLE IF NOT EXISTS public.feedback_logs (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id      uuid REFERENCES public.projects(id) ON DELETE CASCADE,
  org_id          text,
  note            text,
  recipient_email text,
  sent_by         uuid REFERENCES auth.users(id),
  created_at      timestamptz DEFAULT now()
);

-- ============================================================
-- 7. FIX AUTH TRIGGER (this is likely causing the 500 error)
-- Drop any broken trigger first, then recreate it safely
-- ============================================================

-- Drop existing trigger if it exists
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

-- Create or replace the handler function
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
BEGIN
  INSERT INTO public.profiles (id, email, org_id)
  VALUES (
    NEW.id,
    NEW.email,
    'sanctuary'
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Recreate the trigger
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ============================================================
-- 8. ROW LEVEL SECURITY — enable but allow anon key access
-- ============================================================

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.projects ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.project_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.updates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.feedback_logs ENABLE ROW LEVEL SECURITY;

-- Allow authenticated users full access (adjust as needed)
DO $$
DECLARE
  tbl text;
BEGIN
  FOR tbl IN SELECT unnest(ARRAY['profiles','projects','project_assignments','updates','documents','feedback_logs'])
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS "Allow authenticated access" ON public.%I', tbl);
    EXECUTE format('CREATE POLICY "Allow authenticated access" ON public.%I FOR ALL USING (auth.role() = ''authenticated'') WITH CHECK (auth.role() = ''authenticated'')', tbl);
  END LOOP;
END $$;

-- Allow the profiles upsert to work for the user's own row
DROP POLICY IF EXISTS "Users can update own profile" ON public.profiles;
CREATE POLICY "Users can update own profile" ON public.profiles
  FOR UPDATE USING (auth.uid() = id) WITH CHECK (auth.uid() = id);

-- ============================================================
-- Done! Your login should now work.
-- ============================================================
