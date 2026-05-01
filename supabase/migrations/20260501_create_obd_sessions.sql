-- Create obd_sessions table for comprehensive OBD telemetry history
-- Captures all EV battery, GPS, driving, and SOC prediction data

CREATE TABLE IF NOT EXISTS public.obd_sessions (
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id         uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  session_id      text NOT NULL,
  started_at      timestamptz NOT NULL DEFAULT now(),
  session_updated_at timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),

  -- Device info
  device_name     text,
  device_id       text,

  -- Battery / EV metrics (from OBD + enhanced profiles)
  battery_percent       double precision,   -- SOC %
  soh_percent           double precision,   -- State of Health %
  voltage               double precision,   -- pack voltage or 12V module voltage
  battery_power_kw      double precision,   -- instantaneous power draw
  temperature_c         double precision,   -- battery or coolant temp
  battery_current_a     double precision,   -- battery current in amps
  cell_delta_mv         double precision,   -- cell voltage spread in millivolts
  ev_profile_name       text,               -- matched EV profile (e.g. 'Hyundai/Kia EV')

  -- Driving analytics
  average_speed_kph     double precision NOT NULL DEFAULT 0,
  peak_speed_kph        double precision NOT NULL DEFAULT 0,
  trip_distance_km      double precision NOT NULL DEFAULT 0,
  smooth_driving_score  double precision NOT NULL DEFAULT 100,
  efficiency_score      double precision NOT NULL DEFAULT 100,
  harsh_events          integer NOT NULL DEFAULT 0,

  -- GPS-derived fields
  elevation_m           double precision,   -- altitude from GPS
  grade_pct             double precision,   -- road grade %

  -- SOC prediction state
  charge_threshold_pct  double precision,   -- user's "charge at" threshold
  prediction_remaining_km   double precision,   -- predicted km to threshold
  prediction_rate_per_km    double precision,   -- SOC depletion rate %/km

  -- Constraints
  UNIQUE (user_id, session_id)
);

-- Index for fast user lookups ordered by time
CREATE INDEX IF NOT EXISTS idx_obd_sessions_user_updated
  ON public.obd_sessions (user_id, session_updated_at DESC);

-- Enable Row Level Security
ALTER TABLE public.obd_sessions ENABLE ROW LEVEL SECURITY;

-- RLS policies: users can only read/write their own sessions
CREATE POLICY "Users can view own OBD sessions"
  ON public.obd_sessions FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own OBD sessions"
  ON public.obd_sessions FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own OBD sessions"
  ON public.obd_sessions FOR UPDATE
  USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own OBD sessions"
  ON public.obd_sessions FOR DELETE
  USING (auth.uid() = user_id);

-- Allow service_role to bypass RLS (for backend upserts)
CREATE POLICY "Service role full access"
  ON public.obd_sessions FOR ALL
  USING (auth.role() = 'service_role');

-- Grant access to authenticated users
GRANT SELECT, INSERT, UPDATE, DELETE ON public.obd_sessions TO authenticated;
GRANT ALL ON public.obd_sessions TO service_role;
