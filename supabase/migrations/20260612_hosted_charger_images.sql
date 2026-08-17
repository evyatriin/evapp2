insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'hosted-charger-images',
  'hosted-charger-images',
  true,
  5242880,
  array['image/jpeg', 'image/jpg', 'image/png', 'image/webp']
)
on conflict (id) do update
set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'hosted-charger-images public read'
  ) then
    create policy "hosted-charger-images public read"
      on storage.objects for select
      using (bucket_id = 'hosted-charger-images');
  end if;

  if not exists (
    select 1
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'hosted-charger-images owner delete'
  ) then
    create policy "hosted-charger-images owner delete"
      on storage.objects for delete
      using (
        bucket_id = 'hosted-charger-images'
        and auth.uid()::text = (storage.foldername(name))[1]
      );
  end if;
end
$$;
