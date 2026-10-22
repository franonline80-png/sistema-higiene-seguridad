-- Fotografia de personal: columna de referencia, bucket privado y control por organizacion.
alter table public.personas add column if not exists foto_path text;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('personas-fotos', 'personas-fotos', false, 5242880, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set
  public = false,
  file_size_limit = 5242880,
  allowed_mime_types = array['image/jpeg','image/png','image/webp'];

-- Las fotos se guardan en {organizacion_id}/{persona_id}/{archivo}.
-- Cada operacion verifica que el usuario pertenezca a la organizacion de la persona.
drop policy if exists "personas_fotos_select_authenticated" on storage.objects;
drop policy if exists "personas_fotos_insert_authenticated" on storage.objects;
drop policy if exists "personas_fotos_update_authenticated" on storage.objects;
drop policy if exists "personas_fotos_delete_authenticated" on storage.objects;

create policy "personas_fotos_select_authenticated"
on storage.objects for select to authenticated
using (
  bucket_id = 'personas-fotos'
  and exists (
    select 1 from public.personas p
    where p.id::text = (storage.foldername(name))[2]
      and p.organizacion_id::text = (storage.foldername(name))[1]
      and public.usuario_pertenece_organizacion(p.organizacion_id)
  )
);

create policy "personas_fotos_insert_authenticated"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'personas-fotos'
  and exists (
    select 1 from public.personas p
    where p.id::text = (storage.foldername(name))[2]
      and p.organizacion_id::text = (storage.foldername(name))[1]
      and public.usuario_pertenece_organizacion(p.organizacion_id)
  )
);

create policy "personas_fotos_update_authenticated"
on storage.objects for update to authenticated
using (
  bucket_id = 'personas-fotos'
  and exists (
    select 1 from public.personas p
    where p.id::text = (storage.foldername(name))[2]
      and p.organizacion_id::text = (storage.foldername(name))[1]
      and public.usuario_pertenece_organizacion(p.organizacion_id)
  )
)
with check (
  bucket_id = 'personas-fotos'
  and exists (
    select 1 from public.personas p
    where p.id::text = (storage.foldername(name))[2]
      and p.organizacion_id::text = (storage.foldername(name))[1]
      and public.usuario_pertenece_organizacion(p.organizacion_id)
  )
);

create policy "personas_fotos_delete_authenticated"
on storage.objects for delete to authenticated
using (
  bucket_id = 'personas-fotos'
  and exists (
    select 1 from public.personas p
    where p.id::text = (storage.foldername(name))[2]
      and p.organizacion_id::text = (storage.foldername(name))[1]
      and public.usuario_pertenece_organizacion(p.organizacion_id)
  )
);
