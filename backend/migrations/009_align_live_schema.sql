-- Migration: Align live Supabase schema with the mobile app and backend.
-- Description:
-- 1. Brings the public.vehicles table back into compatibility with the app/backend
--    while preserving the newer live columns already present in production.
-- 2. Recreates the missing gamification tables and policies when absent.
-- 3. Seeds badges and restores the weekly_leaderboard view.

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Vehicles compatibility columns
ALTER TABLE IF EXISTS public.vehicles
    ADD COLUMN IF NOT EXISTS range_efficiency DOUBLE PRECISION DEFAULT 1.0,
    ADD COLUMN IF NOT EXISTS is_primary BOOLEAN DEFAULT FALSE;

ALTER TABLE IF EXISTS public.vehicles
    ALTER COLUMN preferred_charging_networks SET DEFAULT ARRAY[]::TEXT[],
    ALTER COLUMN range_efficiency_factor SET DEFAULT 1.0,
    ALTER COLUMN is_default SET DEFAULT FALSE,
    ALTER COLUMN updated_at SET DEFAULT NOW();

UPDATE public.vehicles
SET
    range_efficiency = COALESCE(range_efficiency, range_efficiency_factor, 1.0),
    is_primary = COALESCE(is_primary, is_default, FALSE),
    preferred_charging_networks = COALESCE(
        preferred_charging_networks,
        ARRAY[]::TEXT[]
    )
WHERE
    range_efficiency IS NULL
    OR is_primary IS NULL
    OR preferred_charging_networks IS NULL;

CREATE OR REPLACE FUNCTION public.sync_vehicle_compatibility_columns()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.range_efficiency :=
        COALESCE(NEW.range_efficiency, NEW.range_efficiency_factor, 1.0);
    NEW.range_efficiency_factor :=
        COALESCE(NEW.range_efficiency_factor, NEW.range_efficiency, 1.0);

    NEW.is_primary := COALESCE(NEW.is_primary, NEW.is_default, FALSE);
    NEW.is_default := COALESCE(NEW.is_default, NEW.is_primary, FALSE);

    NEW.preferred_charging_networks :=
        COALESCE(NEW.preferred_charging_networks, ARRAY[]::TEXT[]);
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_sync_vehicle_compatibility_columns
ON public.vehicles;

CREATE TRIGGER trigger_sync_vehicle_compatibility_columns
    BEFORE INSERT OR UPDATE ON public.vehicles
    FOR EACH ROW
    EXECUTE FUNCTION public.sync_vehicle_compatibility_columns();

-- Keep only one primary/default vehicle per user.
CREATE OR REPLACE FUNCTION public.enforce_single_primary_vehicle()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF COALESCE(NEW.is_primary, FALSE) OR COALESCE(NEW.is_default, FALSE) THEN
        UPDATE public.vehicles
        SET
            is_primary = FALSE,
            is_default = FALSE,
            updated_at = NOW()
        WHERE
            user_id = NEW.user_id
            AND id <> NEW.id
            AND (COALESCE(is_primary, FALSE) OR COALESCE(is_default, FALSE));
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_enforce_single_primary_vehicle
ON public.vehicles;

CREATE TRIGGER trigger_enforce_single_primary_vehicle
    BEFORE INSERT OR UPDATE ON public.vehicles
    FOR EACH ROW
    EXECUTE FUNCTION public.enforce_single_primary_vehicle();

CREATE UNIQUE INDEX IF NOT EXISTS vehicles_single_primary_idx
ON public.vehicles (user_id)
WHERE COALESCE(is_primary, FALSE) OR COALESCE(is_default, FALSE);

-- Gamification tables
CREATE TABLE IF NOT EXISTS public.user_stats (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    total_points INTEGER DEFAULT 0 NOT NULL,
    current_streak INTEGER DEFAULT 0 NOT NULL,
    longest_streak INTEGER DEFAULT 0 NOT NULL,
    last_active_date DATE,
    total_check_ins INTEGER DEFAULT 0 NOT NULL,
    total_routes_planned INTEGER DEFAULT 0 NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.badges (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(100) NOT NULL,
    description TEXT,
    icon VARCHAR(50),
    requirement_type VARCHAR(50),
    requirement_value INTEGER,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.user_badges (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    badge_id UUID NOT NULL REFERENCES public.badges(id) ON DELETE CASCADE,
    earned_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    UNIQUE (user_id, badge_id)
);

CREATE OR REPLACE FUNCTION public.update_user_stats_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_user_stats_updated_at
ON public.user_stats;

CREATE TRIGGER trigger_user_stats_updated_at
    BEFORE UPDATE ON public.user_stats
    FOR EACH ROW
    EXECUTE FUNCTION public.update_user_stats_updated_at();

CREATE OR REPLACE VIEW public.weekly_leaderboard AS
SELECT
    u.id AS user_id,
    COALESCE(u.raw_user_meta_data ->> 'name', 'Anonymous') AS name,
    COALESCE(u.raw_user_meta_data ->> 'profile_image_url', NULL) AS profile_image_url,
    COALESCE(us.total_points, 0) AS total_points,
    COALESCE(us.current_streak, 0) AS current_streak,
    COUNT(DISTINCT ub.badge_id) AS badge_count,
    ROW_NUMBER() OVER (ORDER BY COALESCE(us.total_points, 0) DESC) AS rank
FROM auth.users u
LEFT JOIN public.user_stats us ON u.id = us.user_id
LEFT JOIN public.user_badges ub ON u.id = ub.user_id
GROUP BY u.id, u.raw_user_meta_data, us.total_points, us.current_streak
ORDER BY total_points DESC
LIMIT 10;

INSERT INTO public.badges (
    name,
    description,
    icon,
    requirement_type,
    requirement_value
)
SELECT *
FROM (
    VALUES
        (
            'First Check-in',
            'Complete your first charging station check-in',
            'check_circle',
            'check_in',
            1
        ),
        (
            'Route Planner',
            'Plan 10 routes',
            'map',
            'route',
            10
        ),
        (
            'Week Warrior',
            'Maintain a 7-day streak',
            'local_fire_department',
            'streak',
            7
        )
) AS seed(name, description, icon, requirement_type, requirement_value)
WHERE NOT EXISTS (
    SELECT 1
    FROM public.badges b
    WHERE b.name = seed.name
);

ALTER TABLE public.user_stats ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.badges ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_badges ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'user_stats'
          AND policyname = 'Everyone can read user_stats'
    ) THEN
        CREATE POLICY "Everyone can read user_stats"
            ON public.user_stats
            FOR SELECT
            USING (TRUE);
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'user_stats'
          AND policyname = 'Users can update own stats'
    ) THEN
        CREATE POLICY "Users can update own stats"
            ON public.user_stats
            FOR UPDATE
            USING (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'user_stats'
          AND policyname = 'Users can insert own stats'
    ) THEN
        CREATE POLICY "Users can insert own stats"
            ON public.user_stats
            FOR INSERT
            WITH CHECK (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'badges'
          AND policyname = 'Everyone can read badges'
    ) THEN
        CREATE POLICY "Everyone can read badges"
            ON public.badges
            FOR SELECT
            USING (TRUE);
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'user_badges'
          AND policyname = 'Everyone can read user_badges'
    ) THEN
        CREATE POLICY "Everyone can read user_badges"
            ON public.user_badges
            FOR SELECT
            USING (TRUE);
    END IF;
END $$;

GRANT SELECT, INSERT, UPDATE ON public.user_stats TO authenticated;
GRANT SELECT ON public.user_stats TO anon;
GRANT SELECT ON public.badges TO authenticated, anon;
GRANT SELECT, INSERT ON public.user_badges TO authenticated;
GRANT SELECT ON public.user_badges TO anon;
GRANT SELECT ON public.weekly_leaderboard TO authenticated, anon;
