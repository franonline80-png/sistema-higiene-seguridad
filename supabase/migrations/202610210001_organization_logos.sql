-- Logos por establecimiento. Aplicar en Supabase SQL Editor antes de usar la función.
-- Los archivos son logos institucionales públicos; la escritura queda limitada a miembros activos de cada organización.
create table if not exists public.organizacion_logos (
  organizacion_id uuid primary key references public.organizaciones(id) on delete cascade,
  object_path text not null,
  updated_at timestamptz not null default now(),
  constraint organizacion_logos_path_matches_org
    check (object_path like organizacion_id::text || '/%')
);

alter table public.organizacion_logos enable row level security;
revoke all on public.organizacion_logos from anon;
grant select, insert, update, delete on public.organizacion_logos to authenticated;

drop policy if exists "Members read organization logos" on public.organizacion_logos;
create policy "Members read organization logos"
  on public.organizacion_logos for select to authenticated
  using (exists (
    select 1 from public.usuarios_organizaciones uo
    where uo.organizacion_id = organizacion_logos.organizacion_id
      and uo.usuario_id = auth.uid() and uo.activo = true
  ));

drop policy if exists "Members insert organization logos" on public.organizacion_logos;
create policy "Members insert organization logos"
  on public.organizacion_logos for insert to authenticated
  with check (exists (
    select 1 from public.usuarios_organizaciones uo
    where uo.organizacion_id = organizacion_logos.organizacion_id
      and uo.usuario_id = auth.uid() and uo.activo = true
  ));

drop policy if exists "Members update organization logos" on public.organizacion_logos;
create policy "Members update organization logos"
  on public.organizacion_logos for update to authenticated
  using (exists (
    select 1 from public.usuarios_organizaciones uo
    where uo.organizacion_id = organizacion_logos.organizacion_id
      and uo.usuario_id = auth.uid() and uo.activo = true
  ))
  with check (exists (
    select 1 from public.usuarios_organizaciones uo
    where uo.organizacion_id = organizacion_logos.organizacion_id
      and uo.usuario_id = auth.uid() and uo.activo = true
  ));

drop policy if exists "Members delete organization logos" on public.organizacion_logos;
create policy "Members delete organization logos"
  on public.organizacion_logos for delete to authenticated
  using (exists (
    select 1 from public.usuarios_organizaciones uo
    where uo.organizacion_id = organizacion_logos.organizacion_id
      and uo.usuario_id = auth.uid() and uo.activo = true
  ));

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('logos-establecimientos', 'logos-establecimientos', true, 2097152, array['image/png','image/jpeg','image/webp'])
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Organization members upload logos" on storage.objects;
create policy "Organization members upload logos"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'logos-establecimientos'
    and (storage.foldername(name))[1] = (
      select uo.organizacion_id::text from public.usuarios_organizaciones uo
      where uo.organizacion_id::text = (storage.foldername(name))[1]
        and uo.usuario_id = auth.uid() and uo.activo = true
      limit 1
    )
  );

drop policy if exists "Organization members update logos" on storage.objects;
create policy "Organization members update logos"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'logos-establecimientos'
    and exists (
      select 1 from public.usuarios_organizaciones uo
      where uo.organizacion_id::text = (storage.foldername(name))[1]
        and uo.usuario_id = auth.uid() and uo.activo = true
    )
  )
  with check (
    bucket_id = 'logos-establecimientos'
    and exists (
      select 1 from public.usuarios_organizaciones uo
      where uo.organizacion_id::text = (storage.foldername(name))[1]
        and uo.usuario_id = auth.uid() and uo.activo = true
    )
  );

drop policy if exists "Organization members delete logos" on storage.objects;
create policy "Organization members delete logos"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'logos-establecimientos'
    and exists (
      select 1 from public.usuarios_organizaciones uo
      where uo.organizacion_id::text = (storage.foldername(name))[1]
        and uo.usuario_id = auth.uid() and uo.activo = true
    )
  );
