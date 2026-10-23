-- Hallazgos y seguimiento de inspecciones.
-- Aplicar en Supabase SQL Editor antes de habilitar el módulo actualizado.
create table if not exists public.inspeccion_hallazgos (
  id uuid primary key default gen_random_uuid(),
  organizacion_id uuid not null references public.organizaciones(id) on delete cascade,
  inspeccion_id uuid not null references public.inspecciones(id) on delete cascade,
  descripcion text not null,
  nivel_riesgo text not null default 'Moderado' check (nivel_riesgo in ('Bajo','Moderado','Alto','Crítico')),
  accion_correctiva text,
  responsable text,
  fecha_compromiso date,
  estado text not null default 'Pendiente' check (estado in ('Pendiente','En curso','Verificación','Cerrado')),
  seguimiento text,
  fecha_cierre date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists inspeccion_hallazgos_inspeccion_idx on public.inspeccion_hallazgos(inspeccion_id);
create index if not exists inspeccion_hallazgos_org_estado_idx on public.inspeccion_hallazgos(organizacion_id, estado);
alter table public.inspeccion_hallazgos enable row level security;
revoke all on public.inspeccion_hallazgos from anon;
grant select, insert, update, delete on public.inspeccion_hallazgos to authenticated;

drop policy if exists "Members read inspection findings" on public.inspeccion_hallazgos;
create policy "Members read inspection findings" on public.inspeccion_hallazgos for select to authenticated using (
 exists (select 1 from public.inspecciones i join public.usuarios_organizaciones uo on uo.organizacion_id=i.organizacion_id
 where i.id=inspeccion_hallazgos.inspeccion_id and i.organizacion_id=inspeccion_hallazgos.organizacion_id
 and uo.usuario_id=auth.uid() and uo.activo=true)
);
drop policy if exists "Members insert inspection findings" on public.inspeccion_hallazgos;
create policy "Members insert inspection findings" on public.inspeccion_hallazgos for insert to authenticated with check (
 exists (select 1 from public.inspecciones i join public.usuarios_organizaciones uo on uo.organizacion_id=i.organizacion_id
 where i.id=inspeccion_hallazgos.inspeccion_id and i.organizacion_id=inspeccion_hallazgos.organizacion_id
 and uo.usuario_id=auth.uid() and uo.activo=true)
);
drop policy if exists "Members update inspection findings" on public.inspeccion_hallazgos;
create policy "Members update inspection findings" on public.inspeccion_hallazgos for update to authenticated using (
 exists (select 1 from public.inspecciones i join public.usuarios_organizaciones uo on uo.organizacion_id=i.organizacion_id
 where i.id=inspeccion_hallazgos.inspeccion_id and i.organizacion_id=inspeccion_hallazgos.organizacion_id
 and uo.usuario_id=auth.uid() and uo.activo=true)
) with check (
 exists (select 1 from public.inspecciones i join public.usuarios_organizaciones uo on uo.organizacion_id=i.organizacion_id
 where i.id=inspeccion_hallazgos.inspeccion_id and i.organizacion_id=inspeccion_hallazgos.organizacion_id
 and uo.usuario_id=auth.uid() and uo.activo=true)
);
drop policy if exists "Members delete inspection findings" on public.inspeccion_hallazgos;
create policy "Members delete inspection findings" on public.inspeccion_hallazgos for delete to authenticated using (
 exists (select 1 from public.inspecciones i join public.usuarios_organizaciones uo on uo.organizacion_id=i.organizacion_id
 where i.id=inspeccion_hallazgos.inspeccion_id and i.organizacion_id=inspeccion_hallazgos.organizacion_id
 and uo.usuario_id=auth.uid() and uo.activo=true)
);
