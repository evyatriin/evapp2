-- Function to find nearby stations using PostGIS
-- Assumes charging_stations has latitude and longitude columns

create or replace function nearby_stations(
  lat float,
  long float,
  radius_km float
)
returns setof charging_stations
language sql
as $$
  select *
  from charging_stations
  where (
    6371 * acos(
      cos(radians(lat)) * cos(radians(latitude)) * cos(radians(longitude) - radians(long)) +
      sin(radians(lat)) * sin(radians(latitude))
    )
  ) <= radius_km;
$$;
