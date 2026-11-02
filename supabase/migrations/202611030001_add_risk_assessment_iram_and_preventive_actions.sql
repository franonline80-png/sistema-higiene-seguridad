-- Methodology fields aligned with the user's thesis risk estimation matrix and an independent preventive-action ledger.
-- Existing risk rows are preserved; legacy 1–5 fields remain valid.
alter table public.riesgos
  add column if not exists actividad_tarea text,
  add column if not exists personal_expuesto integer,
  add column if not exists metodo_evaluacion text,
  add column if not exists probabilidad_iram text,
  add column if not exists gravedad_iram text,
  add column if not exists nivel_iram text,
  add column if not exists probabilidad_residual_iram text,
  add column if not exists gravedad_residual_iram text,
  add column if not exists nivel_residual_iram text;

alter table public.riesgos
  add constraint riesgos_personal_expuesto_check
  check (personal_expuesto is null or personal_expuesto >= 0);

create table if not exists public.acciones_preventivas_riesgo (
  id uuid primary key default gen_random_uuid(),
  riesgo_id uuid not null references public.riesgos(id) on delete cascade,
  medida text not null,
  fundamentacion text,
  capacitacion text,
  procedimiento text,
  tipo_control text,
  responsable_id uuid references public.personas(id) on delete set null,
  responsable text,
  fecha_compromiso date,
  estado text not null default 'Pendiente'
    check (estado in ('Pendiente','En ejecución','Implementada','Verificada','No eficaz','Cancelada')),
  verificacion text,
  fecha_verificacion date,
  evidencia_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists acciones_preventivas_riesgo_riesgo_id_idx
  on public.acciones_preventivas_riesgo(riesgo_id);
create index if not exists acciones_preventivas_riesgo_estado_fecha_idx
  on public.acciones_preventivas_riesgo(estado,fecha_compromiso);

alter table public.acciones_preventivas_riesgo enable row level security;

create policy acciones_preventivas_riesgo_select_org
on public.acciones_preventivas_riesgo for select to authenticated
using (
 exists (
   select 1
   from public.riesgos r
   join public.evaluaciones_riesgos er on er.id = r.evaluacion_id
   where r.id = acciones_preventivas_riesgo.riesgo_id
     and public.usuario_pertenece_organizacion(er.organizacion_id)
 )
);

create policy acciones_preventivas_riesgo_insert_profesional
on public.acciones_preventivas_riesgo for insert to authenticated
with check (
 exists (
   select 1
   from public.riesgos r
   join public.evaluaciones_riesgos er on er.id = r.evaluacion_id
   where r.id = acciones_preventivas_riesgo.riesgo_id
     and public.usuario_rol_organizacion(er.organizacion_id)
       = any(array['administrador_plataforma','administrador_organizacion','profesional_hys']::text[])
 )
);

create policy acciones_preventivas_riesgo_update_profesional
on public.acciones_preventivas_riesgo for update to authenticated
using (
 exists (
   select 1
   from public.riesgos r
   join public.evaluaciones_riesgos er on er.id = r.evaluacion_id
   where r.id = acciones_preventivas_riesgo.riesgo_id
     and public.usuario_rol_organizacion(er.organizacion_id)
       = any(array['administrador_plataforma','administrador_organizacion','profesional_hys']::text[])
 )
)
with check (
 exists (
   select 1
   from public.riesgos r
   join public.evaluaciones_riesgos er on er.id = r.evaluacion_id
   where r.id = acciones_preventivas_riesgo.riesgo_id
     and public.usuario_rol_organizacion(er.organizacion_id)
       = any(array['administrador_plataforma','administrador_organizacion','profesional_hys']::text[])
 )
);

create policy acciones_preventivas_riesgo_delete_admin
on public.acciones_preventivas_riesgo for delete to authenticated
using (
 exists (
   select 1
   from public.riesgos r
   join public.evaluaciones_riesgos er on er.id = r.evaluacion_id
   where r.id = acciones_preventivas_riesgo.riesgo_id
     and public.usuario_rol_organizacion(er.organizacion_id)
       = any(array['administrador_plataforma','administrador_organizacion']::text[])
 )
);

grant select, insert, update, delete on public.acciones_preventivas_riesgo to authenticated;
