-- Mantener vencimientos preventivos consistentes ante modificaciones de riesgo.
create or replace function public.sync_riesgo_vencimiento()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_establecimiento_id uuid;
  v_organizacion_id uuid;
  v_prioridad text;
  v_puesto_nombre text;
begin
  if new.fecha_vencimiento is null then
    delete from public.vencimientos
    where riesgo_id = new.id and tipo = 'Corrección de riesgo';
    return new;
  end if;

  select s.establecimiento_id, e.organizacion_id, p."Nombre"
    into v_establecimiento_id, v_organizacion_id, v_puesto_nombre
  from public.puestos p
  left join public.sectores s on s.id = p.sector_id
  left join public.establecimientos e on e.id = s.establecimiento_id
  where p.id = new.puesto_id;

  v_prioridad := case
    when coalesce(new.nivel_riesgo,0) >= 15 then 'Crítica'
    when coalesce(new.nivel_riesgo,0) >= 10 then 'Alta'
    when coalesce(new.nivel_riesgo,0) >= 5 then 'Media'
    else 'Baja'
  end;

  insert into public.vencimientos
    (riesgo_id, organizacion_id, establecimiento_id, tipo, concepto, descripcion,
     fecha_vencimiento, estado, prioridad, observaciones)
  values
    (new.id, v_organizacion_id, v_establecimiento_id, 'Corrección de riesgo',
     coalesce(nullif(new.descripcion,''),'Acción correctiva de riesgo'),
     concat_ws(E'\n',
       case when v_puesto_nombre is not null then 'Puesto: '||v_puesto_nombre end,
       case when new.medidas_propuestas is not null then 'Acción correctiva: '||new.medidas_propuestas end,
       case when new.recomendaciones is not null then 'Recomendaciones: '||new.recomendaciones end),
     new.fecha_vencimiento, 'Pendiente', v_prioridad, new.responsable)
  on conflict (riesgo_id) where riesgo_id is not null
  do update set
    organizacion_id = excluded.organizacion_id,
    establecimiento_id = excluded.establecimiento_id,
    tipo = excluded.tipo,
    concepto = excluded.concepto,
    descripcion = excluded.descripcion,
    fecha_vencimiento = excluded.fecha_vencimiento,
    prioridad = excluded.prioridad,
    observaciones = excluded.observaciones,
    estado = case when public.vencimientos.estado = 'Cumplido'
                  then 'Cumplido' else 'Pendiente' end;

  return new;
end;
$$;

-- Mantener cumplidos al sincronizar cambios en planes preventivos; el estado "Verificada"
-- continúa siendo la fuente para establecer el vencimiento como Cumplido.
create or replace function public.sync_accion_preventiva_vencimiento()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
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
$$;
