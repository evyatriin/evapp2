-- Migration: Create canonical charger tables backed by Postgres/PostGIS
-- Description: Adds a self-hosted source of truth for charger aggregation and
-- geospatial lookup helpers for nearby canonical stations.

create extension if not exists postgis with schema extensions;
create extension if not exists "uuid-ossp";

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create table if not exists public.canonical_chargers (
  id uuid primary key default uuid_generate_v4(),
  name text not null,
  normalized_name text not null,
  address text,
  latitude double precision not null,
  longitude double precision not null,
  location geography(Point, 4326)
    generated always as (
      st_setsrid(st_makepoint(longitude, latitude), 4326)::geography
    ) stored,
  provider text,
  connector_types text[] not null default '{}',
  power_kw double precision,
  status text not null default 'Operational',
  availability_status text not null default 'Unknown',
  amenities text[] not null default '{}',
  access_type text not null default 'Public',
  access_instructions text,
  is_private boolean not null default false,
  verified_by text not null default 'EVraahein',
  freshness_score integer,
  last_verified_at timestamptz,
  average_rating double precision,
  total_reviews integer not null default 0,
  total_checkins integer not null default 0,
  source_count integer not null default 0,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_canonical_chargers_location
  on public.canonical_chargers using gist (location);

create index if not exists idx_canonical_chargers_normalized_name
  on public.canonical_chargers (normalized_name);

create table if not exists public.charger_source_records (
  id uuid primary key default uuid_generate_v4(),
  canonical_charger_id uuid not null references public.canonical_chargers(id) on delete cascade,
  source_name text not null,
  source_station_id text not null,
  name text not null,
  normalized_name text not null,
  address text,
  latitude double precision not null,
  longitude double precision not null,
  location geography(Point, 4326)
    generated always as (
      st_setsrid(st_makepoint(longitude, latitude), 4326)::geography
    ) stored,
  provider text,
  connector_types text[] not null default '{}',
  power_kw double precision,
  status text not null default 'Operational',
  availability_status text not null default 'Unknown',
  amenities text[] not null default '{}',
  access_type text not null default 'Public',
  access_instructions text,
  is_private boolean not null default false,
  freshness_score integer,
  last_verified_at timestamptz,
  raw_payload jsonb not null default '{}'::jsonb,
  distance_m double precision,
  confidence_score double precision,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  unique (source_name, source_station_id)
);

create index if not exists idx_charger_source_records_location
  on public.charger_source_records using gist (location);

create index if not exists idx_charger_source_records_canonical
  on public.charger_source_records (canonical_charger_id);

drop trigger if exists trg_canonical_chargers_updated_at on public.canonical_chargers;
create trigger trg_canonical_chargers_updated_at
before update on public.canonical_chargers
for each row
execute function public.set_updated_at();

drop trigger if exists trg_charger_source_records_updated_at on public.charger_source_records;
create trigger trg_charger_source_records_updated_at
before update on public.charger_source_records
for each row
execute function public.set_updated_at();

create or replace function public.nearby_canonical_chargers(
  lat double precision,
  long double precision,
  radius_km double precision default 10
)
returns table (
  id uuid,
  name text,
  address text,
  latitude double precision,
  longitude double precision,
  provider text,
  connector_types text[],
  power_kw double precision,
  status text,
  availability_status text,
  amenities text[],
  access_type text,
  access_instructions text,
  is_private boolean,
  verified_by text,
  freshness_score integer,
  last_verified_at timestamptz,
  average_rating double precision,
  total_reviews integer,
  total_checkins integer,
  source_count integer,
  metadata jsonb,
  distance_m double precision
)
language sql
stable
as $$
  select
    c.id,
    c.name,
    c.address,
    c.latitude,
    c.longitude,
    c.provider,
    c.connector_types,
    c.power_kw,
    c.status,
    c.availability_status,
    c.amenities,
    c.access_type,
    c.access_instructions,
    c.is_private,
    c.verified_by,
    c.freshness_score,
    c.last_verified_at,
    c.average_rating,
    c.total_reviews,
    c.total_checkins,
    c.source_count,
    c.metadata,
    st_distance(
      c.location,
      st_setsrid(st_makepoint(long, lat), 4326)::geography
    ) as distance_m
  from public.canonical_chargers c
  where st_dwithin(
    c.location,
    st_setsrid(st_makepoint(long, lat), 4326)::geography,
    radius_km * 1000
  )
  order by distance_m asc;
$$;

alter table public.canonical_chargers enable row level security;
alter table public.charger_source_records enable row level security;

drop policy if exists "Canonical chargers are viewable by everyone" on public.canonical_chargers;
create policy "Canonical chargers are viewable by everyone"
  on public.canonical_chargers for select
  using (true);

drop policy if exists "Charger source records are viewable by everyone" on public.charger_source_records;
create policy "Charger source records are viewable by everyone"
  on public.charger_source_records for select
  using (true);

grant select on public.canonical_chargers to anon, authenticated;
grant select on public.charger_source_records to anon, authenticated;
grant execute on function public.nearby_canonical_chargers(double precision, double precision, double precision)
  to anon, authenticated;
