-- Storage buckets for EVraahein app
-- vehicle-photos: user uploads vehicle photos (public read, owner write)
-- checkin-images: users upload station check-in photos (public read, authenticated write)

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('vehicle-photos', 'vehicle-photos', true, 5242880,
   array['image/jpeg','image/jpg','image/png','image/webp']),
  ('checkin-images', 'checkin-images', true, 5242880,
   array['image/jpeg','image/jpg','image/png','image/webp'])
on conflict (id) do nothing;

-- RLS: vehicle-photos
create policy "vehicle-photos public read"
  on storage.objects for select
  using (bucket_id = 'vehicle-photos');

create policy "vehicle-photos owner insert"
  on storage.objects for insert
  with check (
    bucket_id = 'vehicle-photos'
    and auth.uid() is not null
  );

create policy "vehicle-photos owner update"
  on storage.objects for update
  using (
    bucket_id = 'vehicle-photos'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

create policy "vehicle-photos owner delete"
  on storage.objects for delete
  using (
    bucket_id = 'vehicle-photos'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

-- RLS: checkin-images
create policy "checkin-images public read"
  on storage.objects for select
  using (bucket_id = 'checkin-images');

create policy "checkin-images authenticated insert"
  on storage.objects for insert
  with check (
    bucket_id = 'checkin-images'
    and auth.role() = 'authenticated'
  );

create policy "checkin-images owner delete"
  on storage.objects for delete
  using (
    bucket_id = 'checkin-images'
    and auth.uid()::text = (storage.foldername(name))[1]
  );
