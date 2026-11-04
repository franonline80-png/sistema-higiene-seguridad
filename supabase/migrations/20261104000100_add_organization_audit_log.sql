create table if not exists public.audit_log (
  id bigint generated always as identity primary key,
  organization_id uuid not null references public.organizaciones(id) on delete cascade,
  actor_id uuid null references auth.users(id) on delete set null,
  action text not null check (action in ('INSERT','UPDATE','DELETE')),
  table_name text not null,
  record_id text not null,
  changed_at timestamptz not null default now(),
  old_data jsonb,
  new_data jsonb
);

alter table public.audit_log enable row level security;

drop policy if exists audit_log_admin_read on public.audit_log;
create policy audit_log_admin_read
on public.audit_log for select to authenticated
using (
  exists (
    select 1 from public.usuarios_organizaciones uo
    where uo.usuario_id = auth.uid()
      and uo.organizacion_id = audit_log.organization_id
      and uo.activo = true
      and uo.rol in ('administrador_plataforma','administrador_organizacion')
  )
);

revoke all on public.audit_log from anon, authenticated;
grant select on public.audit_log to authenticated;

create or replace function public.log_organization_changes()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_old jsonb;
  v_new jsonb;
  v_org uuid;
  v_id text;
begin
  if TG_OP = 'DELETE' then
    v_old := to_jsonb(OLD);
    v_new := null;
    v_org := nullif(v_old->>'organizacion_id','')::uuid;
    v_id := coalesce(v_old->>'id', v_old->>'uuid');
  elsif TG_OP = 'UPDATE' then
    v_old := to_jsonb(OLD);
    v_new := to_jsonb(NEW);
    v_org := coalesce(nullif(v_new->>'organizacion_id','')::uuid, nullif(v_old->>'organizacion_id','')::uuid);
    v_id := coalesce(v_new->>'id', v_old->>'id', v_new->>'uuid', v_old->>'uuid');
  else
    v_old := null;
    v_new := to_jsonb(NEW);
    v_org := nullif(v_new->>'organizacion_id','')::uuid;
    v_id := coalesce(v_new->>'id', v_new->>'uuid');
  end if;

  if v_org is not null and v_id is not null then
    insert into public.audit_log (organization_id, actor_id, action, table_name, record_id, old_data, new_data)
    values (v_org, auth.uid(), TG_OP, TG_TABLE_NAME, v_id, v_old, v_new);
  end if;
  return case when TG_OP = 'DELETE' then OLD else NEW end;
end;
$$;

revoke all on function public.log_organization_changes() from public, anon, authenticated;

do $$
declare
  t text;
  tables text[] := array[
    'accidentes_incidentes','capacitaciones','documentacion','epp',
    'equipos_instalaciones','establecimientos','evaluaciones_riesgos',
    'inspecciones','mapas_riesgos','mediciones_ambientales','organizaciones',
    'personas','vencimientos'
  ];
begin
  foreach t in array tables loop
    execute format('drop trigger if exists audit_changes on public.%I', t);
    execute format('create trigger audit_changes after insert or update or delete on public.%I for each row execute function public.log_organization_changes()', t);
  end loop;
end;
$$;