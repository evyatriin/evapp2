# Database Migrations

This directory contains SQL migration files for the EV-Ranger database.

## Running Migrations

### Option 1: Supabase Dashboard (Recommended)
1. Go to your Supabase project dashboard
2. Navigate to **SQL Editor**
3. Copy the contents of the migration file
4. Paste and execute

### Option 2: Supabase CLI
```bash
# Install Supabase CLI if not already installed
npm install -g supabase

# Link to your project
supabase link --project-ref your-project-ref

# Run migration
supabase db push
```

### Option 3: Direct PostgreSQL Connection
```bash
psql -h your-db-host -U postgres -d postgres -f migrations/001_create_station_checkins.sql
```

## Migration Files

- `001_create_station_checkins.sql` - Creates station_checkins table and adds points column to profiles

## Rollback

To rollback the station_checkins migration:

```sql
DROP TABLE IF EXISTS station_checkins CASCADE;
ALTER TABLE profiles DROP COLUMN IF EXISTS points;
```
