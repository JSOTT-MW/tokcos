insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('store-assets', 'store-assets', true, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists store_assets_public_read on storage.objects;
create policy store_assets_public_read
  on storage.objects for select
  using (bucket_id = 'store-assets');

drop policy if exists store_assets_owner_upload on storage.objects;
create policy store_assets_owner_upload
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'store-assets'
    and (storage.foldername(name))[1] in (
      select sm.store_id::text
      from public.store_members sm
      where sm.user_id = auth.uid()
        and sm.role in ('owner', 'admin')
    )
    and (storage.foldername(name))[2] in ('logo', 'banner')
  );

drop policy if exists store_assets_owner_update on storage.objects;
create policy store_assets_owner_update
  on storage.objects for update to authenticated
  using (
    bucket_id = 'store-assets'
    and (storage.foldername(name))[1] in (
      select sm.store_id::text
      from public.store_members sm
      where sm.user_id = auth.uid()
        and sm.role in ('owner', 'admin')
    )
    and (storage.foldername(name))[2] in ('logo', 'banner')
  )
  with check (
    bucket_id = 'store-assets'
    and (storage.foldername(name))[1] in (
      select sm.store_id::text
      from public.store_members sm
      where sm.user_id = auth.uid()
        and sm.role in ('owner', 'admin')
    )
    and (storage.foldername(name))[2] in ('logo', 'banner')
  );

drop policy if exists store_assets_owner_delete on storage.objects;
create policy store_assets_owner_delete
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'store-assets'
    and (storage.foldername(name))[1] in (
      select sm.store_id::text
      from public.store_members sm
      where sm.user_id = auth.uid()
        and sm.role in ('owner', 'admin')
    )
    and (storage.foldername(name))[2] in ('logo', 'banner')
  );
