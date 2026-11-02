-- Each dated preventive action is reflected in the organization's Vencimientos module.
-- The action and its due date are linked without reusing riesgos.riesgo_id's one-per-risk unique slot.
alter table public.acciones_preventivas_riesgo
 add column if not exists vencimiento_id uuid references public.vencimientos(id) on delete set null;
create index if not exists acciones_preventivas_riesgo_vencimiento_id_idx
 on public.acciones_preventivas_riesgo(vencimiento_id);

create or replace function public.sync_accion_preventiva_vencimiento()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
 v_org uuid;
 v_establecimiento uuid;
 v_puesto text;
 v_riesgo text;
 v_due uuid;
 v_estado text;
begin
 if tg_op = 'DELETE' then
   if old.vencimiento_id is not null then
     delete from public.vencimientos where id = old.vencimiento_id;
   end if;
   return old;
 end if;

 select er.organizacion_id, s.establecimiento_id, p."Nombre", r.descripcion
 into v_org, v_establecimiento, v_puesto, v_riesgo
 from public.riesgos r
 join public.evaluaciones_riesgos er on er.id = r.evaluacion_id
 join public.puestos p on p.id = r.puesto_id
 join public.sectores s on s.id = p.sector_id
 where r.id = new.riesgo_id;

 if v_org is null then
   raise exception 'No se pudo resolver organización/establecimiento del riesgo vinculado';
 end if;

 if new.fecha_compromiso is null or new.estado = 'Cancelada' then
   if new.vencimiento_id is not null then
     delete from public.vencimientos where id = new.vencimiento_id;
     update public.acciones_preventivas_riesgo set vencimiento_id = null where id = new.id;
   end if;
   return new;
 end if;

 v_estado := case when new.estado in ('Implementada','Verificada') then 'Cumplido'
                  when new.estado = 'En ejecución' then 'En curso'
                  when new.estado = 'No eficaz' then 'Pendiente'
                  else 'Pendiente' end;

 if new.vencimiento_id is not null then
   update public.vencimientos
   set organizacion_id = v_org,
       establecimiento_id = v_establecimiento,
       tipo = 'Medida preventiva de riesgo',
       concepto = new.medida,
       descripcion = concat_ws(E'\n',
          'Puesto: ' || coalesce(v_puesto,'—'),
          'Riesgo: ' || coalesce(v_riesgo,'—'),
          'Fundamentación: ' || coalesce(new.fundamentacion,'—'),
          'Responsable: ' || coalesce(new.responsable,'—')),
       fecha_vencimiento = new.fecha_compromiso,
       responsable_id = new.responsable_id,
       estado = v_estado,
       prioridad = case when v_estado = 'Cumplido' then 'Baja' else 'Media' end,
       observaciones = concat_ws(E'\n', 'Estado plan preventivo: ' || new.estado, new.verificacion)
   where id = new.vencimiento_id
   returning id into v_due;
 else
   insert into public.vencimientos
     (organizacion_id, establecimiento_id, tipo, concepto, descripcion,
      fecha_vencimiento, responsable_id, estado, prioridad, observaciones, riesgo_id)
   values
     (v_org, v_establecimiento, 'Medida preventiva de riesgo', new.medida,
      concat_ws(E'\n',
        'Puesto: ' || coalesce(v_puesto,'—'),
        'Riesgo: ' || coalesce(v_riesgo,'—'),
        'Fundamentación: ' || coalesce(new.fundamentacion,'—'),
        'Responsable: ' || coalesce(new.responsable,'—')),
      new.fecha_compromiso, new.responsable_id, v_estado,
      case when v_estado = 'Cumplido' then 'Baja' else 'Media' end,
      concat_ws(E'\n', 'Estado plan preventivo: ' || new.estado, new.verificacion),
      null)
   returning id into v_due;
   update public.acciones_preventivas_riesgo set vencimiento_id = v_due where id = new.id;
 end if;
 return new;
end;
$function$;

drop trigger if exists acciones_preventivas_sync_vencimiento on public.acciones_preventivas_riesgo;
create trigger acciones_preventivas_sync_vencimiento
after insert or update of riesgo_id, medida, fundamentacion, responsable_id, responsable,
 fecha_compromiso, estado, verificacion, fecha_verificacion, evidencia_url
or delete on public.acciones_preventivas_riesgo
for each row execute function public.sync_accion_preventiva_vencimiento();

revoke all on function public.sync_accion_preventiva_vencimiento() from public, anon, authenticated;
