-- Host charger: store electricity cost and margin separately so the
-- platform can compute price_per_kwh and audit host earnings.
ALTER TABLE charging_stations
  ADD COLUMN IF NOT EXISTS electricity_cost_per_kwh NUMERIC(10, 2),
  ADD COLUMN IF NOT EXISTS host_margin_per_kwh      NUMERIC(10, 2);

-- Charger requests: settlement fields written when host enters actual kWh.
ALTER TABLE charger_requests
  ADD COLUMN IF NOT EXISTS kwh_delivered  NUMERIC(10, 3),
  ADD COLUMN IF NOT EXISTS energy_cost    NUMERIC(10, 2),
  ADD COLUMN IF NOT EXISTS platform_fee   NUMERIC(10, 2),
  ADD COLUMN IF NOT EXISTS final_amount   NUMERIC(10, 2),
  ADD COLUMN IF NOT EXISTS settled_at     TIMESTAMPTZ;
