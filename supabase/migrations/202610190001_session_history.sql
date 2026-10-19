-- Historial de sesiones del Sistema de Higiene y Seguridad
-- Ejecutar una sola vez en Supabase SQL Editor.
create table if not exists public.sesiones_usuario (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  inicio timestamptz not null default now(),
  fin timestamptz,
  duracion_segundos integer,
  estado text not null default 'abierta'
    check (estado in ('abierta','cerrada','interrumpida')),
  created_at timestamptz not null default now(),
  constraint sesiones_usuario_duracion_no_negativa
    check (duracion_segundos is null or duracion_segundos >= 0),
  constraint sesiones_usuario_fechas_validas
    check (fin is null or fin >= inicio)
);
create index if not exists sesiones_usuario_usuario_inicio_idx
  on public.sesiones_usuario (usuario_id, inicio desc);
alter table public.sesiones_usuario enable row level security;
revoke all on public.sesiones_usuario from anon;
grant select, insert, update on public.sesiones_usuario to authenticated;
drop policy if exists "Users read own sessions" on public.sesiones_usuario;
create policy "Users read own sessions"
  on public.sesiones_usuario for select to authenticated
  using (auth.uid() = usuario_id);
drop policy if exists "Users insert own sessions" on public.sesiones_usuario;
create policy "Users insert own sessions"
  on public.sesiones_usuario for insert to authenticated
  with check (auth.uid() = usuario_id);
drop policy if exists "Users update own sessions" on public.sesiones_usuario;
create policy "Users update own sessions"
  on public.sesiones_usuario for update to authenticated
  using (auth.uid() = usuario_id)
  with check (auth.uid() = usuario_id);
