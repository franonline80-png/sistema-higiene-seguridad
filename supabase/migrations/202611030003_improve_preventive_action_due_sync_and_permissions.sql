-- Keep the preventive-action deadline mirror aligned with qualitative IRAM / legacy scoring.
-- Only Verificada marks the deadline as fulfilled; Implementada remains under verification.
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
 v_prioridad text;
 v_nivel text;
 v_score numeric;
 v_descripcion text;
 v_observaciones text;
begin
 if tg_op = 'DELETE' then
   if old.vencimiento_id is not null then
     delete from public.vencimientos where id = old.vencimiento_id;
   end if;
   return old;
 end if;

 select er.organizacion_id, s.establecimiento_id, p."Nombre", r.descripcion,
        coalesce(nullif(r.nivel_residual_iram,''),nullif(r.nivel_iram,'')),
        coalesce(r.nivel_riesgo,(coalesce(r."Probabilidad",0)*coalesce(r.consecuencia,0)))
 into v_org, v_establecimiento, v_puesto, v_riesgo, v_nivel, v_score
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

 v_estado := case when new.estado = 'Verificada' then 'Cumplido'
                  when new.estado in ('Implementada','En ejecución') then 'En curso'
                  when new.estado = 'No eficaz' then 'Pendiente'
                  else 'Pendiente' end;
 v_prioridad := case
   when v_nivel = 'Intolerable' or coalesce(v_score,0) >= 15 then 'Crítica'
   when v_nivel = 'Significativo' or coalesce(v_score,0) >= 10 then 'Alta'
   when v_nivel = 'Moderado' or coalesce(v_score,0) >= 5 then 'Media'
   else 'Baja' end;
 v_descripcion := concat_ws(E'\n',
   'Puesto: ' || coalesce(v_puesto,'—'),
   'Riesgo identificado: ' || coalesce(v_riesgo,'—'),
   'Fundamentación: ' || coalesce(new.fundamentacion,'—'),
   'Tipo de control: ' || coalesce(new.tipo_control,'—'),
   'Capacitación: ' || coalesce(new.capacitacion,'—'),
   'Procedimiento: ' || coalesce(new.procedimiento,'—'),
   'Responsable: ' || coalesce(new.responsable,'—'));
 v_observaciones := concat_ws(E'\n',
   'Estado del plan preventivo: ' || new.estado,
   'Verificación: ' || coalesce(new.verificacion,'—'),
   'Fecha de verificación: ' || coalesce(new.fecha_verificacion::text,'—'),
   'Evidencia: ' || coalesce(new.evidencia_url,'—'));

 if new.vencimiento_id is not null then
   update public.vencimientos
   set organizacion_id = v_org,
       establecimiento_id = v_establecimiento,
       tipo = 'Medida preventiva de riesgo',
       concepto = new.medida,
       descripcion = v_descripcion,
       fecha_vencimiento = new.fecha_compromiso,
       responsable_id = new.responsable_id,
       estado = v_estado,
       prioridad = v_prioridad,
       observaciones = v_observaciones
   where id = new.vencimiento_id
   returning id into v_due;
 else
   insert into public.vencimientos
     (organizacion_id, establecimiento_id, tipo, concepto, descripcion,
      fecha_vencimiento, responsable_id, estado, prioridad, observaciones, riesgo_id)
   values
     (v_org, v_establecimiento, 'Medida preventiva de riesgo', new.medida,
      v_descripcion, new.fecha_compromiso, new.responsable_id, v_estado,
      v_prioridad, v_observaciones, null)
   returning id into v_due;
   update public.acciones_preventivas_riesgo set vencimiento_id = v_due where id = new.id;
 end if;
 return new;
end;
$function$;

revoke all on function public.sync_accion_preventiva_vencimiento() from public, anon, authenticated;

drop policy if exists acciones_preventivas_riesgo_delete_admin on public.acciones_preventivas_riesgo;
drop policy if exists acciones_preventivas_riesgo_delete_profesional on public.acciones_preventivas_riesgo;
create policy acciones_preventivas_riesgo_delete_profesional
on public.acciones_preventivas_riesgo for delete to authenticated
using (
 exists (
   select 1
   from public.riesgos r
   join public.evaluaciones_riesgos er on er.id = r.evaluacion_id
   where r.id = acciones_preventivas_riesgo.riesgo_id
     and public.usuario_rol_organizacion(er.organizacion_id)
       = any(array['administrador_plataforma','administrador_organizacion','profesional_hys']::text[])
 )
);
