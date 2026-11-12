-- Correlativo permanente de legajos, administrado exclusivamente por trigger.
create table if not exists public.personas_legajo_contadores (
  organizacion_id uuid primary key,
  ultimo_numero bigint not null check (ultimo_numero >= 0)
);
alter table public.personas_legajo_contadores enable row level security;
revoke all on public.personas_legajo_contadores from public, anon, authenticated;
insert into public.personas_legajo_contadores(organizacion_id,ultimo_numero)
select organizacion_id,max(("Legajo")::bigint)
from public.personas
where "Legajo" ~ '^[0-9]+$' and organizacion_id is not null
group by organizacion_id
on conflict (organizacion_id) do update
set ultimo_numero=greatest(public.personas_legajo_contadores.ultimo_numero,excluded.ultimo_numero);
create unique index if not exists personas_legajo_unico_por_organizacion
on public.personas (organizacion_id, "Legajo") where "Legajo" is not null;
create or replace function public.personas_asignar_legajo()
returns trigger language plpgsql security definer set search_path=pg_catalog
as $$
declare numero bigint;
begin
  if TG_OP='UPDATE' then
    if NEW.organizacion_id is distinct from OLD.organizacion_id then
      raise exception 'No se permite cambiar la organización de un legajo existente';
    end if;
    if NEW."Legajo" is distinct from OLD."Legajo" then
      raise exception 'El legajo asignado es permanente y no se puede modificar';
    end if;
    return NEW;
  end if;
  if NEW.organizacion_id is null then
    raise exception 'Se requiere una organización para asignar el legajo';
  end if;
  insert into public.personas_legajo_contadores(organizacion_id,ultimo_numero)
  values(NEW.organizacion_id,1)
  on conflict (organizacion_id) do update
  set ultimo_numero=public.personas_legajo_contadores.ultimo_numero+1
  returning ultimo_numero into numero;
  NEW."Legajo" := lpad(numero::text,2,'0');
  return NEW;
end;
$$;
revoke all on function public.personas_asignar_legajo() from public, anon, authenticated;
drop trigger if exists personas_legajo_asignacion on public.personas;
create trigger personas_legajo_asignacion
before insert or update of "Legajo",organizacion_id on public.personas
for each row execute function public.personas_asignar_legajo();