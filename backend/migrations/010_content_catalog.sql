create table if not exists public.vehicle_templates (
  id text primary key,
  brand text not null,
  model text not null,
  variant text not null,
  range_efficiency double precision not null default 0.85,
  image_url text,
  preferred_charging_networks text[] not null default '{}',
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.app_resource_sections (
  id text primary key,
  title text not null,
  description text,
  icon text not null default 'book-open',
  tone text not null default 'primary',
  sort_order integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.app_resources (
  id text primary key,
  section_id text not null references public.app_resource_sections(id) on delete cascade,
  title text not null,
  subtitle text,
  url text not null,
  sort_order integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into public.vehicle_templates (id, brand, model, variant, range_efficiency, image_url, preferred_charging_networks, sort_order)
values
  ('tata-nexon-ev-max', 'Tata', 'Nexon EV', 'Max', 0.85, 'https://imgd.aeplcdn.com/1056x594/n/cw/ec/141867/nexon-ev-exterior-right-front-three-quarter-3.jpeg?isig=0&q=80', array['Tata Power','Statiq'], 1),
  ('tata-tiago-ev', 'Tata', 'Tiago EV', 'Long Range', 0.82, 'https://imgd.aeplcdn.com/1056x594/n/cw/ec/131129/tiago-ev-exterior-right-front-three-quarter-14.jpeg?isig=0&q=80', array['Tata Power'], 2),
  ('mg-zs-ev', 'MG', 'ZS EV', 'Exclusive', 0.90, 'https://imgd.aeplcdn.com/1056x594/n/cw/ec/113531/zs-ev-exterior-right-front-three-quarter-2.jpeg?isig=0&q=80', array['Fortum','Tata Power'], 3),
  ('mg-comet', 'MG', 'Comet EV', 'Plush', 0.75, 'https://imgd.aeplcdn.com/1056x594/n/cw/ec/146499/comet-ev-exterior-right-front-three-quarter-2.jpeg?isig=0&q=80', array['Fortum'], 4),
  ('hyundai-kona', 'Hyundai', 'Kona Electric', 'Premium', 0.88, 'https://imgd.aeplcdn.com/1056x594/n/cw/ec/40530/kona-electric-exterior-right-front-three-quarter-16.jpeg?isig=0&q=80', array['ChargeZone','Statiq'], 5),
  ('hyundai-ioniq-5', 'Hyundai', 'Ioniq 5', 'RWD', 0.92, 'https://imgd.aeplcdn.com/1056x594/n/cw/ec/136217/ioniq-5-exterior-right-front-three-quarter-4.jpeg?isig=0&q=80', array['ChargeZone','Shell Recharge'], 6)
on conflict (id) do update set
  brand = excluded.brand,
  model = excluded.model,
  variant = excluded.variant,
  range_efficiency = excluded.range_efficiency,
  image_url = excluded.image_url,
  preferred_charging_networks = excluded.preferred_charging_networks,
  sort_order = excluded.sort_order,
  updated_at = now();

insert into public.app_resource_sections (id, title, description, icon, tone, sort_order)
values
  ('before-you-charge', 'Before You Charge', 'Quick prep before you pull into a station.', 'lightning', 'amber', 1),
  ('battery-care', 'Battery & Ownership', 'Habits that keep range and battery health strong.', 'car', 'blue', 2),
  ('policies', 'Policies & Incentives', 'Subsidies, policies, and tax benefits worth checking.', 'bank', 'green', 3),
  ('emergency-help', 'Emergency Help', 'Brand hotlines you can call when a trip goes sideways.', 'phone', 'red', 4)
on conflict (id) do update set
  title = excluded.title,
  description = excluded.description,
  icon = excluded.icon,
  tone = excluded.tone,
  sort_order = excluded.sort_order,
  updated_at = now();

insert into public.app_resources (id, section_id, title, subtitle, url, sort_order)
values
  ('connector-types', 'before-you-charge', 'Understanding Connector Types', 'CCS, CHAdeMO, Type 2 explained', 'https://evraahein.app/charging-connectors', 1),
  ('charging-etiquette', 'before-you-charge', 'Charging Etiquette', 'Best practices at public chargers', 'https://evraahein.app/charging-etiquette', 2),
  ('ac-dc', 'before-you-charge', 'AC vs DC Charging', 'Speed differences and when to use', 'https://evraahein.app/ac-vs-dc', 3),
  ('battery-care-guide', 'battery-care', 'Battery Care Guide', 'Maximize battery life and health', 'https://evraahein.app/battery-care', 1),
  ('range-optimization', 'battery-care', 'Range Optimization', 'Get the most out of every charge', 'https://evraahein.app/range-tips', 2),
  ('seasonal-driving', 'battery-care', 'Seasonal Driving Tips', 'Winter and summer best practices', 'https://evraahein.app/seasonal-tips', 3),
  ('fame-ii', 'policies', 'FAME II Subsidy', 'Central government EV incentives', 'https://fame2.heavyindustries.gov.in/', 1),
  ('state-policies', 'policies', 'State EV Policies', 'State-specific benefits and subsidies', 'https://evraahein.app/state-policies', 2),
  ('tax-benefits', 'policies', 'Tax Benefits', 'Income tax deductions for EV owners', 'https://evraahein.app/tax-benefits', 3),
  ('tata-support', 'emergency-help', 'Tata Motors EV Support', 'Tap to call: 1800-209-7979', 'tel:18002097979', 1),
  ('mg-support', 'emergency-help', 'MG Motor Support', 'Tap to call: 1800-102-4644', 'tel:18001024644', 2),
  ('hyundai-support', 'emergency-help', 'Hyundai EV Helpline', 'Tap to call: 1800-11-4645', 'tel:1800114645', 3)
on conflict (id) do update set
  section_id = excluded.section_id,
  title = excluded.title,
  subtitle = excluded.subtitle,
  url = excluded.url,
  sort_order = excluded.sort_order,
  updated_at = now();
