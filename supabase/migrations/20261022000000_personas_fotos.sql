-- Fotografía de personal: columna de referencia y bucket privado.
-- Aplicar en Supabase SQL Editor (o ejecutar como migración).
alter table public.personas add column if not exists foto_path text;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('personas-fotos', 'personas-fotos', false, 5242880, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set
  public = false,
  file_size_limit = 5242880,
  allowed_mime_types = array['image/jpeg','image/png','image/webp'];

-- Las políticas se limitan al bucket específico y a sesiones autenticadas.
drop policy if exists "personas_fotos_select_authenticated" on storage.objects;
create policy "personas_fotos_select_authenticated"
on storage.objects for select to authenticated
using (bucket_id = 'personas-fotos');

drop policy if exists "personas_fotos_insert_authenticated" on storage.objects;
create policy "personas_fotos_insert_authenticated"
on storage.objects for insert to authenticated
with check (bucket_id = 'personas-fotos');

drop policy if exists "personas_fotos_update_authenticated" on storage.objects;
create policy "personas_fotos_update_authenticated"
on storage.objects for update to authenticated
using (bucket_id = 'personas-fotos')
with check (bucket_id = 'personas-fotos');

drop policy if exists "personas_fotos_delete_authenticated" on storage.objects;
create policy "personas_fotos_delete_authenticated"
on storage.objects for delete to authenticated
using (bucket_id = 'personas-fotos');
