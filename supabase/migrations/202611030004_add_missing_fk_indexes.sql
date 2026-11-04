-- Índices de soporte para claves foráneas sin índice de cobertura.
do $$
declare
  fk record;
  idx_name text;
  cols text;
begin
  for fk in
    select c.oid,c.conname,c.conrelid,c.conkey,c.connamespace
    from pg_constraint c
    where c.contype='f'
      and c.connamespace='public'::regnamespace
      and not exists (
        select 1 from pg_index i
        where i.indrelid=c.conrelid and i.indisvalid and i.indpred is null
          and (select array_agg(i.indkey[k]::int order by k)
               from generate_series(0,cardinality(c.conkey)-1) k)=c.conkey::int[]
      )
  loop
    select string_agg(format('%I',a.attname),', ' order by u.ord)
      into cols
    from unnest(fk.conkey) with ordinality u(attnum,ord)
    join pg_attribute a on a.attrelid=fk.conrelid and a.attnum=u.attnum;
    idx_name := 'fkidx_' || substr(md5(fk.oid::text),1,12);
    execute format('create index if not exists %I on %s (%s)',idx_name,fk.conrelid::regclass,cols);
  end loop;
end;
$$;
