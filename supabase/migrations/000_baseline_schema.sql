-- ============================================================
-- BASELINE SCHEMA — EVraahein
-- ============================================================
-- Purpose: Captures all core tables that were created directly
--          in the Supabase dashboard and never formally migrated.
--          Run this FIRST, before migrations 001–016.
--
-- Tables covered here (NOT present in any other migration):
--   1.  profiles
--   2.  vehicles
--   3.  vehicle_templates
--   4.  charging_stations      (base table; columns added by 013 & 015)
--   5.  saved_routes
--   6.  charging_sessions
--   7.  community_posts
--   8.  post_likes
--   9.  sos_alerts
--   10. trip_logs
--   11. user_blocks
--   12. user_reports
--   13. direct_messages
--   14. admin_audit_logs
--
-- Sources used to reconstruct each table:
--   - backend/routers/*.py  (Pydantic models + table operations)
--   - lib/src/features/**   (Flutter models + Supabase calls)
--   - backend/migrations/009_align_live_schema.sql (vehicles patch columns)
--   - backend/migrations/013_add_private_charger_requests.sql (station ALTER columns)
--   - backend/migrations/015_hosted_charger_safety_and_trust.sql (station ALTER columns)
--   - backend/routers/admin.py (audit log + moderation usage)
-- ============================================================

-- Extensions (idempotent — safe to run even if already enabled)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";


-- ────────────────────────────────────────────────────────────
-- HELPER: generic updated_at trigger function
-- (also created in migration 001 — this is idempotent)
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;


-- ════════════════════════════════════════════════════════════
-- 1. PROFILES
--    Source: user_model.dart, auth_service.dart, users.py
--    Fields: id, name, email, profile_image_url, phone_number,
--            preferences (JSONB), points (added by migration 001)
-- ════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.profiles (
    id                UUID        PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    name              TEXT        NOT NULL DEFAULT '',
    email             TEXT        NOT NULL DEFAULT '',
    profile_image_url TEXT,
    phone_number      TEXT,
    -- JSONB bag for semi-structured preferences:
    --   is_phone_verified (bool), vehicle_details (obj),
    --   preferred_charging_networks (list), any future prefs
    preferences       JSONB       NOT NULL DEFAULT '{}'::jsonb,
    -- points added by migration 001 via ALTER — included here for fresh installs
    points            INTEGER     NOT NULL DEFAULT 0,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE OR REPLACE TRIGGER trg_profiles_updated_at
    BEFORE UPDATE ON public.profiles
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='profiles' AND policyname='Users can read own profile'
  ) THEN
    CREATE POLICY "Users can read own profile"
      ON public.profiles FOR SELECT USING (auth.uid() = id);
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='profiles' AND policyname='Users can update own profile'
  ) THEN
    CREATE POLICY "Users can update own profile"
      ON public.profiles FOR UPDATE USING (auth.uid() = id);
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='profiles' AND policyname='Users can insert own profile'
  ) THEN
    CREATE POLICY "Users can insert own profile"
      ON public.profiles FOR INSERT WITH CHECK (auth.uid() = id);
  END IF;
END $$;

GRANT SELECT, INSERT, UPDATE ON public.profiles TO authenticated;
GRANT SELECT ON public.profiles TO anon;


-- ════════════════════════════════════════════════════════════
-- 2. VEHICLES
--    Source: vehicles.py VehicleCreateRequest / VehicleProfile
--    Note: migration 009 adds compatibility columns (range_efficiency,
--          is_primary) and sync triggers — those run AFTER this baseline.
-- ════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.vehicles (
    id                          UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id                     UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    brand                       TEXT        NOT NULL,
    model                       TEXT        NOT NULL,
    variant                     TEXT        NOT NULL DEFAULT '',
    -- canonical efficiency column (preferred by app v2+)
    range_efficiency            DOUBLE PRECISION NOT NULL DEFAULT 1.0,
    -- legacy alias — kept in sync with range_efficiency via trigger in migration 009
    range_efficiency_factor     DOUBLE PRECISION NOT NULL DEFAULT 1.0,
    image_url                   TEXT,
    photo_url                   TEXT,
    preferred_charging_networks TEXT[]      NOT NULL DEFAULT ARRAY[]::TEXT[],
    -- canonical primary flag (preferred by app v2+)
    is_primary                  BOOLEAN     NOT NULL DEFAULT FALSE,
    -- legacy alias — kept in sync with is_primary via trigger in migration 009
    is_default                  BOOLEAN     NOT NULL DEFAULT FALSE,
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_vehicles_user_id ON public.vehicles (user_id);

CREATE OR REPLACE TRIGGER trg_vehicles_updated_at
    BEFORE UPDATE ON public.vehicles
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

ALTER TABLE public.vehicles ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='vehicles' AND policyname='Users can manage own vehicles'
  ) THEN
    CREATE POLICY "Users can manage own vehicles"
      ON public.vehicles FOR ALL USING (auth.uid() = user_id);
  END IF;
END $$;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.vehicles TO authenticated;


-- ════════════════════════════════════════════════════════════
-- 3. VEHICLE TEMPLATES  (read-only reference / seeded data)
--    Source: vehicles.py VehicleTemplate, migration 014 (seed inserts)
--    Note: migration 014 only inserts rows — it assumes this table exists.
-- ════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.vehicle_templates (
    id                          TEXT        PRIMARY KEY,
    brand                       TEXT        NOT NULL,
    model                       TEXT        NOT NULL,
    variant                     TEXT        NOT NULL,
    range_efficiency            DOUBLE PRECISION NOT NULL DEFAULT 1.0,
    battery_kwh                 DOUBLE PRECISION,
    certified_range_km          DOUBLE PRECISION,
    range_cycle                 TEXT,
    real_world_range_km         DOUBLE PRECISION,
    dc_fast_charge_kw           DOUBLE PRECISION,
    ac_charge_kw                DOUBLE PRECISION,
    connector_type              TEXT,
    price_min                   NUMERIC(14, 2),
    price_max                   NUMERIC(14, 2),
    launch_status               TEXT        NOT NULL DEFAULT 'available',
    image_url                   TEXT        NOT NULL DEFAULT '',
    source_url                  TEXT,
    last_seen_at                TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    verified_at                 TIMESTAMPTZ,
    confidence_score            DOUBLE PRECISION NOT NULL DEFAULT 0.6,
    preferred_charging_networks TEXT[]      NOT NULL DEFAULT ARRAY[]::TEXT[],
    is_active                   BOOLEAN     NOT NULL DEFAULT TRUE,
    sort_order                  INTEGER     NOT NULL DEFAULT 0,
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT vehicle_templates_battery_kwh_positive
        CHECK (battery_kwh IS NULL OR battery_kwh > 0),
    CONSTRAINT vehicle_templates_ranges_non_negative
        CHECK (
            (certified_range_km IS NULL OR certified_range_km >= 0)
            AND (real_world_range_km IS NULL OR real_world_range_km >= 0)
        ),
    CONSTRAINT vehicle_templates_charge_kw_non_negative
        CHECK (
            (dc_fast_charge_kw IS NULL OR dc_fast_charge_kw >= 0)
            AND (ac_charge_kw IS NULL OR ac_charge_kw >= 0)
        ),
    CONSTRAINT vehicle_templates_price_non_negative
        CHECK (
            (price_min IS NULL OR price_min >= 0)
            AND (price_max IS NULL OR price_max >= 0)
            AND (
                price_min IS NULL
                OR price_max IS NULL
                OR price_max >= price_min
            )
        ),
    CONSTRAINT vehicle_templates_launch_status_valid
        CHECK (launch_status IN ('available', 'upcoming', 'discontinued')),
    CONSTRAINT vehicle_templates_confidence_score_range
        CHECK (confidence_score >= 0 AND confidence_score <= 1)
);

CREATE INDEX IF NOT EXISTS idx_vehicle_templates_active
    ON public.vehicle_templates (is_active, sort_order);
CREATE INDEX IF NOT EXISTS idx_vehicle_templates_brand_model_variant
    ON public.vehicle_templates (brand, model, variant);
CREATE INDEX IF NOT EXISTS idx_vehicle_templates_launch_status
    ON public.vehicle_templates (launch_status);
CREATE INDEX IF NOT EXISTS idx_vehicle_templates_last_seen
    ON public.vehicle_templates (last_seen_at DESC);

-- Public read, no RLS needed (reference table with no user data)
GRANT SELECT ON public.vehicle_templates TO anon, authenticated;


-- ════════════════════════════════════════════════════════════
-- 4. CHARGING STATIONS
--    Source: chargers.py ChargingStation + HostChargerRequest
--    Note: migrations 013 & 015 ADD columns to this table.
--          This baseline creates the initial set of columns.
--          All ADD COLUMN IF NOT EXISTS in those migrations are idempotent.
-- ════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.charging_stations (
    -- Use TEXT PK to support aggregated stations from multiple sources
    -- (OpenChargeMap IDs are integers, Google Place IDs are strings)
    id                      TEXT        PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
    name                    TEXT        NOT NULL,
    address                 TEXT,
    latitude                DOUBLE PRECISION NOT NULL,
    longitude               DOUBLE PRECISION NOT NULL,
    provider                TEXT,
    connector_types         TEXT[]      NOT NULL DEFAULT ARRAY[]::TEXT[],
    power_kw                DOUBLE PRECISION,
    status                  TEXT        NOT NULL DEFAULT 'Operational',
    availability_status     TEXT        NOT NULL DEFAULT 'Unknown',
    amenities               TEXT[]      NOT NULL DEFAULT ARRAY[]::TEXT[],
    is_24_7                 BOOLEAN     NOT NULL DEFAULT FALSE,
    image_urls              TEXT[]      NOT NULL DEFAULT ARRAY[]::TEXT[],
    is_private              BOOLEAN     NOT NULL DEFAULT FALSE,
    -- owner_id is set for community-hosted stations
    owner_id                UUID        REFERENCES auth.users(id) ON DELETE SET NULL,
    access_type             TEXT        NOT NULL DEFAULT 'Public',
    access_instructions     TEXT,
    submitted_by            TEXT,
    verification_status     TEXT        NOT NULL DEFAULT 'pending',
    average_rating          DOUBLE PRECISION NOT NULL DEFAULT 0.0,
    total_reviews           INTEGER     NOT NULL DEFAULT 0,
    total_checkins          INTEGER     NOT NULL DEFAULT 0,
    -- electricity_cost_per_kwh & host_margin_per_kwh: structured pricing inputs
    -- price_per_kwh is the derived/final price shown to drivers
    electricity_cost_per_kwh DOUBLE PRECISION,
    host_margin_per_kwh     DOUBLE PRECISION,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
    -- Columns added by migration 013: host_name, host_phone, host_upi_id,
    --   price_per_kwh, price_per_session, available_from, available_to,
    --   available_days, is_accepting_requests, parking_notes, house_rules,
    --   charger_photos
    -- Columns added by migration 015: property_type, visitor_access_type,
    --   available_hours, vehicle_size_support, parking_photos,
    --   location_access_checks, safety_checks, host_declarations,
    --   declaration_version, declarations_completed_at,
    --   moderation_flags, verification_badges
);

CREATE INDEX IF NOT EXISTS idx_charging_stations_location
    ON public.charging_stations (latitude, longitude);
CREATE INDEX IF NOT EXISTS idx_charging_stations_owner
    ON public.charging_stations (owner_id)
    WHERE owner_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_charging_stations_is_private
    ON public.charging_stations (is_private);

CREATE OR REPLACE TRIGGER trg_charging_stations_updated_at
    BEFORE UPDATE ON public.charging_stations
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

ALTER TABLE public.charging_stations ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='charging_stations' AND policyname='Public can read all stations'
  ) THEN
    CREATE POLICY "Public can read all stations"
      ON public.charging_stations FOR SELECT USING (true);
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='charging_stations' AND policyname='Authenticated users can submit stations'
  ) THEN
    CREATE POLICY "Authenticated users can submit stations"
      ON public.charging_stations FOR INSERT
      WITH CHECK (auth.role() = 'authenticated');
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='charging_stations' AND policyname='Owners can update own stations'
  ) THEN
    CREATE POLICY "Owners can update own stations"
      ON public.charging_stations FOR UPDATE
      USING (auth.uid() = owner_id);
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='charging_stations' AND policyname='Owners can delete own stations'
  ) THEN
    CREATE POLICY "Owners can delete own stations"
      ON public.charging_stations FOR DELETE
      USING (auth.uid() = owner_id);
  END IF;
END $$;

GRANT SELECT ON public.charging_stations TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.charging_stations TO authenticated;


-- ════════════════════════════════════════════════════════════
-- 5. SAVED ROUTES
--    Source: routes.py SavedRoute / SavedRouteCreate
-- ════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.saved_routes (
    id              UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    name            TEXT        NOT NULL DEFAULT 'My Route',
    start_location  JSONB       NOT NULL DEFAULT '{}'::jsonb,
    end_location    JSONB       NOT NULL DEFAULT '{}'::jsonb,
    vehicle_id      UUID        REFERENCES public.vehicles(id) ON DELETE SET NULL,
    route_data      JSONB       NOT NULL DEFAULT '{}'::jsonb,
    distance_km     DOUBLE PRECISION NOT NULL DEFAULT 0,
    duration_min    INTEGER     NOT NULL DEFAULT 0,
    charging_stops  INTEGER     NOT NULL DEFAULT 0,
    is_favorite     BOOLEAN     NOT NULL DEFAULT FALSE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_saved_routes_user_id
    ON public.saved_routes (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_saved_routes_favorites
    ON public.saved_routes (user_id, is_favorite)
    WHERE is_favorite = TRUE;

ALTER TABLE public.saved_routes ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='saved_routes' AND policyname='Users can manage own routes'
  ) THEN
    CREATE POLICY "Users can manage own routes"
      ON public.saved_routes FOR ALL USING (auth.uid() = user_id);
  END IF;
END $$;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.saved_routes TO authenticated;


-- ════════════════════════════════════════════════════════════
-- 6. CHARGING SESSIONS
--    Source: chargers.py ChargingSession / CreateSessionRequest
--    Used by: statistics endpoint (kwh_charged), charger history
-- ════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.charging_sessions (
    id          UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id     UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    station_id  TEXT        REFERENCES public.charging_stations(id) ON DELETE SET NULL,
    start_time  TIMESTAMPTZ NOT NULL,
    end_time    TIMESTAMPTZ,
    -- kwh_added: alias used by CreateSessionRequest
    -- kwh_charged: alias used by statistics endpoint
    -- Both refer to the same value; stored in kwh_added, kwh_charged is a generated column
    kwh_added   DOUBLE PRECISION,
    kwh_charged DOUBLE PRECISION GENERATED ALWAYS AS (kwh_added) STORED,
    cost        DOUBLE PRECISION,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_charging_sessions_user_id
    ON public.charging_sessions (user_id, start_time DESC);
CREATE INDEX IF NOT EXISTS idx_charging_sessions_station_id
    ON public.charging_sessions (station_id)
    WHERE station_id IS NOT NULL;

ALTER TABLE public.charging_sessions ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='charging_sessions' AND policyname='Users can manage own sessions'
  ) THEN
    CREATE POLICY "Users can manage own sessions"
      ON public.charging_sessions FOR ALL USING (auth.uid() = user_id);
  END IF;
END $$;

GRANT SELECT, INSERT ON public.charging_sessions TO authenticated;


-- ════════════════════════════════════════════════════════════
-- 7. COMMUNITY POSTS
--    Source: users.py (delete cleanup), admin.py (moderation)
--    Note: admin.py references community_posts and community_comments
--          as content types for moderation.
-- ════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.community_posts (
    id          UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id     UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    content     TEXT,
    image_url   TEXT,
    -- post_type: 'general' | 'tip' | 'question' | 'experience'
    post_type   TEXT        NOT NULL DEFAULT 'general',
    -- moderation: 'visible' | 'hidden' | 'removed'
    mod_status  TEXT        NOT NULL DEFAULT 'visible',
    like_count  INTEGER     NOT NULL DEFAULT 0,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_community_posts_user_id
    ON public.community_posts (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_community_posts_visible
    ON public.community_posts (mod_status, created_at DESC)
    WHERE mod_status = 'visible';

CREATE OR REPLACE TRIGGER trg_community_posts_updated_at
    BEFORE UPDATE ON public.community_posts
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

ALTER TABLE public.community_posts ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='community_posts' AND policyname='Visible posts are public'
  ) THEN
    CREATE POLICY "Visible posts are public"
      ON public.community_posts FOR SELECT
      USING (mod_status = 'visible' OR auth.uid() = user_id);
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='community_posts' AND policyname='Users can create posts'
  ) THEN
    CREATE POLICY "Users can create posts"
      ON public.community_posts FOR INSERT
      WITH CHECK (auth.uid() = user_id);
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='community_posts' AND policyname='Users can manage own posts'
  ) THEN
    CREATE POLICY "Users can manage own posts"
      ON public.community_posts FOR UPDATE USING (auth.uid() = user_id);
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='community_posts' AND policyname='Users can delete own posts'
  ) THEN
    CREATE POLICY "Users can delete own posts"
      ON public.community_posts FOR DELETE USING (auth.uid() = user_id);
  END IF;
END $$;

GRANT SELECT ON public.community_posts TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.community_posts TO authenticated;


-- ════════════════════════════════════════════════════════════
-- 8. POST LIKES
--    Source: users.py (delete cleanup: "post_likes")
-- ════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.post_likes (
    id         UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id    UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    post_id    UUID        NOT NULL REFERENCES public.community_posts(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, post_id)
);

CREATE INDEX IF NOT EXISTS idx_post_likes_post_id
    ON public.post_likes (post_id);

ALTER TABLE public.post_likes ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='post_likes' AND policyname='Public can read likes'
  ) THEN
    CREATE POLICY "Public can read likes"
      ON public.post_likes FOR SELECT USING (true);
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='post_likes' AND policyname='Users can like posts'
  ) THEN
    CREATE POLICY "Users can like posts"
      ON public.post_likes FOR INSERT WITH CHECK (auth.uid() = user_id);
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='post_likes' AND policyname='Users can unlike posts'
  ) THEN
    CREATE POLICY "Users can unlike posts"
      ON public.post_likes FOR DELETE USING (auth.uid() = user_id);
  END IF;
END $$;

GRANT SELECT ON public.post_likes TO anon;
GRANT SELECT, INSERT, DELETE ON public.post_likes TO authenticated;


-- Auto-maintain like_count on community_posts
CREATE OR REPLACE FUNCTION public.update_post_like_count()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE public.community_posts SET like_count = like_count + 1 WHERE id = NEW.post_id;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE public.community_posts SET like_count = GREATEST(0, like_count - 1) WHERE id = OLD.post_id;
  END IF;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_post_likes_count ON public.post_likes;
CREATE TRIGGER trg_post_likes_count
    AFTER INSERT OR DELETE ON public.post_likes
    FOR EACH ROW EXECUTE FUNCTION public.update_post_like_count();


-- ════════════════════════════════════════════════════════════
-- 9. SOS ALERTS
--    Source: sos.py SOSAlert / CreateAlertRequest
-- ════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.sos_alerts (
    id           UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id      UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    latitude     DOUBLE PRECISION NOT NULL,
    longitude    DOUBLE PRECISION NOT NULL,
    message      TEXT,
    car_model    TEXT,
    phone_number TEXT,
    -- status: 'Active' | 'Resolved' | 'Expired'
    status       TEXT        NOT NULL DEFAULT 'Active',
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_sos_alerts_active
    ON public.sos_alerts (status, created_at DESC)
    WHERE status = 'Active';
CREATE INDEX IF NOT EXISTS idx_sos_alerts_location
    ON public.sos_alerts (latitude, longitude)
    WHERE status = 'Active';
CREATE INDEX IF NOT EXISTS idx_sos_alerts_user_id
    ON public.sos_alerts (user_id);

ALTER TABLE public.sos_alerts ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='sos_alerts' AND policyname='Authenticated users can view active alerts'
  ) THEN
    CREATE POLICY "Authenticated users can view active alerts"
      ON public.sos_alerts FOR SELECT
      USING (auth.role() = 'authenticated' AND status = 'Active');
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='sos_alerts' AND policyname='Verified users can create SOS alerts'
  ) THEN
    CREATE POLICY "Verified users can create SOS alerts"
      ON public.sos_alerts FOR INSERT
      WITH CHECK (auth.uid() = user_id);
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='sos_alerts' AND policyname='Users can resolve own alerts'
  ) THEN
    CREATE POLICY "Users can resolve own alerts"
      ON public.sos_alerts FOR UPDATE
      USING (auth.uid() = user_id);
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='sos_alerts' AND policyname='Users can delete own alerts'
  ) THEN
    CREATE POLICY "Users can delete own alerts"
      ON public.sos_alerts FOR DELETE
      USING (auth.uid() = user_id);
  END IF;
END $$;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.sos_alerts TO authenticated;


-- ════════════════════════════════════════════════════════════
-- 10. TRIP LOGS
--     Source: users.py statistics endpoint (distance_km, trip count)
--     Used to calculate: total_km, co2_saved, money_saved
-- ════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.trip_logs (
    id           UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id      UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    -- route this trip was based on (optional)
    route_id     UUID        REFERENCES public.saved_routes(id) ON DELETE SET NULL,
    distance_km  DOUBLE PRECISION NOT NULL DEFAULT 0,
    duration_min INTEGER     NOT NULL DEFAULT 0,
    kwh_used     DOUBLE PRECISION,
    -- trip_type: 'highway' | 'city' | 'mixed'
    trip_type    TEXT,
    started_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ended_at     TIMESTAMPTZ,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_trip_logs_user_id
    ON public.trip_logs (user_id, started_at DESC);

ALTER TABLE public.trip_logs ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='trip_logs' AND policyname='Users can manage own trips'
  ) THEN
    CREATE POLICY "Users can manage own trips"
      ON public.trip_logs FOR ALL USING (auth.uid() = user_id);
  END IF;
END $$;

GRANT SELECT, INSERT ON public.trip_logs TO authenticated;


-- ════════════════════════════════════════════════════════════
-- 11. USER BLOCKS
--     Source: users.py BlockRequest + delete cleanup
-- ════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.user_blocks (
    id          UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    blocker_id  UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    blocked_id  UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (blocker_id, blocked_id)
);

CREATE INDEX IF NOT EXISTS idx_user_blocks_blocker
    ON public.user_blocks (blocker_id);
CREATE INDEX IF NOT EXISTS idx_user_blocks_blocked
    ON public.user_blocks (blocked_id);

ALTER TABLE public.user_blocks ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='user_blocks' AND policyname='Users can manage own blocks'
  ) THEN
    CREATE POLICY "Users can manage own blocks"
      ON public.user_blocks FOR ALL USING (auth.uid() = blocker_id);
  END IF;
END $$;

GRANT SELECT, INSERT, DELETE ON public.user_blocks TO authenticated;


-- ════════════════════════════════════════════════════════════
-- 12. USER REPORTS
--     Source: users.py ReportRequest + admin.py moderation
-- ════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.user_reports (
    id                UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    reporter_id       UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    reported_user_id  UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    -- reason: 'spam' | 'harassment' | 'misinformation' | 'inappropriate' | 'other'
    reason            TEXT        NOT NULL,
    details           TEXT,
    -- status: 'Open' | 'Reviewed' | 'Dismissed' | 'Actioned'
    status            TEXT        NOT NULL DEFAULT 'Open',
    reviewed_by       UUID        REFERENCES auth.users(id) ON DELETE SET NULL,
    reviewed_at       TIMESTAMPTZ,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_user_reports_reported
    ON public.user_reports (reported_user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_user_reports_open
    ON public.user_reports (status)
    WHERE status = 'Open';

ALTER TABLE public.user_reports ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='user_reports' AND policyname='Users can create reports'
  ) THEN
    CREATE POLICY "Users can create reports"
      ON public.user_reports FOR INSERT WITH CHECK (auth.uid() = reporter_id);
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='user_reports' AND policyname='Reporters can view own reports'
  ) THEN
    CREATE POLICY "Reporters can view own reports"
      ON public.user_reports FOR SELECT USING (auth.uid() = reporter_id);
  END IF;
END $$;

GRANT INSERT ON public.user_reports TO authenticated;
GRANT SELECT ON public.user_reports TO authenticated;


-- ════════════════════════════════════════════════════════════
-- 13. DIRECT MESSAGES
--     Source: users.py delete cleanup (sender_id, receiver_id cols)
--     Status: Table structure inferred; no Flutter UI yet implemented.
--             Infrastructure created so account deletion works correctly.
-- ════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.direct_messages (
    id           UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    sender_id    UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    receiver_id  UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    content      TEXT        NOT NULL,
    -- read_at NULL means unread
    read_at      TIMESTAMPTZ,
    -- status: 'sent' | 'delivered' | 'read' | 'deleted'
    status       TEXT        NOT NULL DEFAULT 'sent',
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_direct_messages_receiver
    ON public.direct_messages (receiver_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_direct_messages_sender
    ON public.direct_messages (sender_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_direct_messages_unread
    ON public.direct_messages (receiver_id, read_at)
    WHERE read_at IS NULL;

ALTER TABLE public.direct_messages ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='direct_messages' AND policyname='Users can read own messages'
  ) THEN
    CREATE POLICY "Users can read own messages"
      ON public.direct_messages FOR SELECT
      USING (auth.uid() = sender_id OR auth.uid() = receiver_id);
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='direct_messages' AND policyname='Users can send messages'
  ) THEN
    CREATE POLICY "Users can send messages"
      ON public.direct_messages FOR INSERT
      WITH CHECK (auth.uid() = sender_id);
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='direct_messages' AND policyname='Receivers can mark messages read'
  ) THEN
    CREATE POLICY "Receivers can mark messages read"
      ON public.direct_messages FOR UPDATE
      USING (auth.uid() = receiver_id);
  END IF;
END $$;

GRANT SELECT, INSERT, UPDATE ON public.direct_messages TO authenticated;


-- ════════════════════════════════════════════════════════════
-- 14. ADMIN AUDIT LOGS
--     Source: admin.py moderation actions (ban, content removal)
--     Note: api_daily_stats / external_api_daily_stats / user_daily_stats
--           are created in migration 016 — not duplicated here.
-- ════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.admin_audit_logs (
    id            UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    admin_user_id UUID        NOT NULL REFERENCES auth.users(id) ON DELETE SET NULL,
    -- action: 'ban_user' | 'hide_post' | 'dismiss_report' | 'approve_station' | etc.
    action        TEXT        NOT NULL,
    -- target_type: 'user' | 'post' | 'station' | 'report' | 'checkin'
    target_type   TEXT        NOT NULL,
    target_id     TEXT        NOT NULL,
    -- free-form metadata (reason, previous state, etc.)
    metadata      JSONB       NOT NULL DEFAULT '{}'::jsonb,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_admin_audit_logs_admin
    ON public.admin_audit_logs (admin_user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_admin_audit_logs_target
    ON public.admin_audit_logs (target_type, target_id);
CREATE INDEX IF NOT EXISTS idx_admin_audit_logs_created
    ON public.admin_audit_logs (created_at DESC);

-- Only service role / admin can read/write audit logs (no user-facing RLS)
ALTER TABLE public.admin_audit_logs ENABLE ROW LEVEL SECURITY;
-- No policies = deny all from anon/authenticated; service_role bypasses RLS


-- ════════════════════════════════════════════════════════════
-- AUTO-PROVISION PROFILE ON SIGNUP
-- Trigger: when a new user is created in auth.users, create
-- a matching row in public.profiles automatically.
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  INSERT INTO public.profiles (id, name, email, preferences)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'name', ''),
    COALESCE(NEW.email, ''),
    COALESCE(NEW.raw_user_meta_data, '{}'::jsonb)
  )
  ON CONFLICT (id) DO NOTHING;  -- idempotent in case of retries
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


-- ════════════════════════════════════════════════════════════
-- SUMMARY OF TABLE CREATION ORDER
-- ════════════════════════════════════════════════════════════
-- 000_baseline_schema.sql  (THIS FILE)
--   profiles, vehicles, vehicle_templates, charging_stations,
--   saved_routes, charging_sessions, community_posts, post_likes,
--   sos_alerts, trip_logs, user_blocks, user_reports,
--   direct_messages, admin_audit_logs
--
-- 001_create_station_checkins.sql
--   station_checkins  (+  ALTER profiles ADD points)
--
-- 002_create_saved_chargers.sql
--   saved_chargers
--
-- 003_create_ev_news.sql
--   ev_news
--
-- 004_create_gamification.sql
--   user_stats, badges, user_badges, weekly_leaderboard (view)
--
-- 005_create_nearby_stations_rpc.sql
--   nearby_stations RPC function
--
-- 006_add_voting_to_checkins.sql
--   ALTER station_checkins (upvotes, downvotes)
--
-- 007_fix_station_id_type.sql
--   Coerces station_id to text-compatible
--
-- 008_add_trip_context.sql
--   ALTER station_checkins (weather, trip_type, passenger_count, drive_mode)
--
-- 009_align_live_schema.sql
--   ALTER vehicles (range_efficiency, is_primary) + sync triggers
--   Recreates user_stats, badges, user_badges if missing
--
-- 010_content_catalog.sql
--   app_resources, app_resource_sections + seed data
--
-- 011_create_obd_sessions.sql
--   obd_sessions
--
-- 012_create_canonical_chargers.sql
--   canonical_chargers, charger_source_records (PostGIS-backed)
--
-- 013_add_private_charger_requests.sql
--   charger_requests
--   ALTER charging_stations (host fields, pricing, availability)
--
-- 014_expand_vehicle_templates.sql
--   Seeds vehicle_templates with 70+ Indian EV models
--
-- 015_hosted_charger_safety_and_trust.sql
--   ALTER charging_stations (safety checks, declarations, badges)
--
-- 015_add_checkin_charging_details.sql
--   ALTER station_checkins (battery_start/end %, cost_paid, slip_url)
--
-- 016_admin_metrics_tables.sql
--   api_daily_stats, external_api_daily_stats, user_daily_stats
--   + atomic tracking functions
--
-- supabase/migrations/20260501_create_obd_sessions.sql
--   (duplicate / superset of 011 — apply only if 011 not run)
--
-- supabase/migrations/20260506_charger_pricing.sql
--   ALTER charging_stations (electricity_cost, host_margin)
--
-- supabase/migrations/20260507_hosted_charger_safety_and_trust.sql
--   (mirrors backend/015)
--
-- supabase/migrations/20260521_storage_buckets.sql
--   vehicle-photos bucket, checkin-images bucket + RLS policies
-- ════════════════════════════════════════════════════════════
