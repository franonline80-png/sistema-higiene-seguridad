alter table public.personas
  add column if not exists fecha_nacimiento date,
  add column if not exists genero text,
  add column if not exists domicilio text,
  add column if not exists localidad text,
  add column if not exists provincia text,
  add column if not exists telefono text,
  add column if not exists email text,
  add column if not exists contacto_emergencia_nombre text,
  add column if not exists contacto_emergencia_telefono text,
  add column if not exists observaciones text;
