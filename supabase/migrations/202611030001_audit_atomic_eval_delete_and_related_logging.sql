-- Correcciones de auditoría: eliminación transaccional y trazabilidad de riesgos/estructura.
create or replace function public.eliminar_evaluacion_riesgos(
  p_evaluacion_id uuid,
  p_organizacion_id uuid
) returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_user uuid := auth.uid();
  v_eval public.evaluaciones_riesgos;
begin
  if v_user is null or not public.usuario_pertenece_organizacion(p_organizacion_id) then
    raise exception 'No autorizado para esta organización';
  end if;

  select * into v_eval
  from public.evaluaciones_riesgos
  where id = p_evaluacion_id and organizacion_id = p_organizacion_id
  for update;

  if not found then
    raise exception 'Evaluación inexistente o fuera de la organización activa';
  end if;

  delete from public.riesgos where evaluacion_id = v_eval.id;
  delete from public.evaluaciones_riesgos
  where id = v_eval.id and organizacion_id = p_organizacion_id;

  if not found then
    raise exception 'No se pudo confirmar la eliminación de la evaluación';
  end if;

  return true;
end;
$$;

revoke all on function public.eliminar_evaluacion_riesgos(uuid, uuid) from public, anon;
grant execute on function public.eliminar_evaluacion_riesgos(uuid, uuid) to authenticated;

create or replace function public.log_related_organization_changes()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_old jsonb;
  v_new jsonb;
  v_org uuid;
  v_record text;
  v_related uuid;
begin
  if tg_op = 'DELETE' then
    v_old := to_jsonb(old); v_new := null;
  elsif tg_op = 'UPDATE' then
    v_old := to_jsonb(old); v_new := to_jsonb(new);
  else
    v_old := null; v_new := to_jsonb(new);
  end if;

  v_record := coalesce(v_new->>'id',v_old->>'id');
  if tg_table_name = 'riesgos' then
    v_related := coalesce(nullif(v_new->>'evaluacion_id','')::uuid,nullif(v_old->>'evaluacion_id','')::uuid);
    select organizacion_id into v_org from public.evaluaciones_riesgos where id=v_related;
  elsif tg_table_name = 'sectores' then
    v_related := coalesce(nullif(v_new->>'establecimiento_id','')::uuid,nullif(v_old->>'establecimiento_id','')::uuid);
    select organizacion_id into v_org from public.establecimientos where id=v_related;
  elsif tg_table_name = 'puestos' then
    v_related := coalesce(nullif(v_new->>'sector_id','')::uuid,nullif(v_old->>'sector_id','')::uuid);
    select e.organizacion_id into v_org from public.sectores s join public.establecimientos e on e.id=s.establecimiento_id where s.id=v_related;
  end if;

  if v_org is not null and v_record is not null then
    insert into public.audit_log(organization_id,actor_id,action,table_name,record_id,old_data,new_data)
    values(v_org,auth.uid(),tg_op,tg_table_name,v_record,v_old,v_new);
  end if;
  return case when tg_op='DELETE' then old else new end;
end;
$$;

drop trigger if exists audit_riesgos_related_changes on public.riesgos;
create trigger audit_riesgos_related_changes
after insert or update or delete on public.riesgos
for each row execute function public.log_related_organization_changes();

drop trigger if exists audit_sectores_related_changes on public.sectores;
create trigger audit_sectores_related_changes
after insert or update or delete on public.sectores
for each row execute function public.log_related_organization_changes();

drop trigger if exists audit_puestos_related_changes on public.puestos;
create trigger audit_puestos_related_changes
after insert or update or delete on public.puestos
for each row execute function public.log_related_organization_changes();
