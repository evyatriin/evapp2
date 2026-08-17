  -- Migration: Expand vehicle template catalog fields for variant-level EV data.
  -- Description:
  -- Adds canonical per-variant fields used by catalog ingestion, admin review,
  -- and richer app UI display. This migration is idempotent and keeps the
  -- existing mobile contract fields intact.

  alter table if exists public.vehicle_templates
    add column if not exists battery_kwh double precision,
    add column if not exists certified_range_km double precision,
    add column if not exists range_cycle text,
    add column if not exists real_world_range_km double precision,
    add column if not exists dc_fast_charge_kw double precision,
    add column if not exists ac_charge_kw double precision,
    add column if not exists connector_type text,
    add column if not exists price_min numeric(14, 2),
    add column if not exists price_max numeric(14, 2),
    add column if not exists launch_status text not null default 'available',
    add column if not exists source_url text,
    add column if not exists last_seen_at timestamptz not null default now(),
    add column if not exists verified_at timestamptz,
    add column if not exists confidence_score double precision not null default 0.6,
    add column if not exists updated_at timestamptz not null default now();

  -- Backfill new canonical fields from older/temporary admin fields if they
  -- exist in a live database.
  do $$
  begin
    if exists (
      select 1
      from information_schema.columns
      where table_schema = 'public'
        and table_name = 'vehicle_templates'
        and column_name = 'battery_capacity_kwh'
    ) then
      execute 'update public.vehicle_templates set battery_kwh = coalesce(battery_kwh, battery_capacity_kwh)';
    end if;

    if exists (
      select 1
      from information_schema.columns
      where table_schema = 'public'
        and table_name = 'vehicle_templates'
        and column_name = 'range_wltp_km'
    ) then
      execute 'update public.vehicle_templates set certified_range_km = coalesce(certified_range_km, range_wltp_km), range_cycle = coalesce(range_cycle, ''WLTP'') where range_wltp_km is not null';
    end if;

    if exists (
      select 1
      from information_schema.columns
      where table_schema = 'public'
        and table_name = 'vehicle_templates'
        and column_name = 'max_charging_power_kw'
    ) then
      execute 'update public.vehicle_templates set dc_fast_charge_kw = coalesce(dc_fast_charge_kw, max_charging_power_kw)';
    end if;

    if exists (
      select 1
      from information_schema.columns
      where table_schema = 'public'
        and table_name = 'vehicle_templates'
        and column_name = 'connectors'
    ) then
      execute 'update public.vehicle_templates set connector_type = coalesce(connector_type, array_to_string(connectors, '', '')) where connectors is not null';
    end if;
  end $$;

  update public.vehicle_templates
  set
    certified_range_km = coalesce(certified_range_km, real_world_range_km),
    range_cycle = coalesce(range_cycle, 'ARAI'),
    launch_status = case
      when lower(coalesce(nullif(launch_status, ''), 'available')) in ('available', 'upcoming', 'discontinued')
        then lower(coalesce(nullif(launch_status, ''), 'available'))
      else 'available'
    end,
    last_seen_at = coalesce(last_seen_at, now()),
    confidence_score = least(1, greatest(0, coalesce(confidence_score, 0.6))),
    updated_at = coalesce(updated_at, now());

  do $$
  begin
    if not exists (
      select 1 from pg_constraint
      where conname = 'vehicle_templates_battery_kwh_positive'
    ) then
      alter table public.vehicle_templates
        add constraint vehicle_templates_battery_kwh_positive
        check (battery_kwh is null or battery_kwh > 0);
    end if;

    if not exists (
      select 1 from pg_constraint
      where conname = 'vehicle_templates_ranges_non_negative'
    ) then
      alter table public.vehicle_templates
        add constraint vehicle_templates_ranges_non_negative
        check (
          (certified_range_km is null or certified_range_km >= 0)
          and (real_world_range_km is null or real_world_range_km >= 0)
        );
    end if;

    if not exists (
      select 1 from pg_constraint
      where conname = 'vehicle_templates_charge_kw_non_negative'
    ) then
      alter table public.vehicle_templates
        add constraint vehicle_templates_charge_kw_non_negative
        check (
          (dc_fast_charge_kw is null or dc_fast_charge_kw >= 0)
          and (ac_charge_kw is null or ac_charge_kw >= 0)
        );
    end if;

    if not exists (
      select 1 from pg_constraint
      where conname = 'vehicle_templates_price_non_negative'
    ) then
      alter table public.vehicle_templates
        add constraint vehicle_templates_price_non_negative
        check (
          (price_min is null or price_min >= 0)
          and (price_max is null or price_max >= 0)
          and (
            price_min is null
            or price_max is null
            or price_max >= price_min
          )
        );
    end if;

    if not exists (
      select 1 from pg_constraint
      where conname = 'vehicle_templates_launch_status_valid'
    ) then
      alter table public.vehicle_templates
        add constraint vehicle_templates_launch_status_valid
        check (launch_status in ('available', 'upcoming', 'discontinued'));
    end if;

    if not exists (
      select 1 from pg_constraint
      where conname = 'vehicle_templates_confidence_score_range'
    ) then
      alter table public.vehicle_templates
        add constraint vehicle_templates_confidence_score_range
        check (confidence_score >= 0 and confidence_score <= 1);
    end if;
  end $$;

  create index if not exists idx_vehicle_templates_brand_model_variant
    on public.vehicle_templates (brand, model, variant);

  create index if not exists idx_vehicle_templates_launch_status
    on public.vehicle_templates (launch_status);

  create index if not exists idx_vehicle_templates_last_seen
    on public.vehicle_templates (last_seen_at desc);

  create or replace function public.update_vehicle_templates_updated_at()
  returns trigger
  language plpgsql
  as $$
  begin
    new.updated_at = now();
    return new;
  end;
  $$;

  drop trigger if exists trigger_vehicle_templates_updated_at
  on public.vehicle_templates;

  create trigger trigger_vehicle_templates_updated_at
    before update on public.vehicle_templates
    for each row
    execute function public.update_vehicle_templates_updated_at();
