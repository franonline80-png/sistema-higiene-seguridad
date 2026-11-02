-- Allow organization/platform administrators to delete risk assessment headers.
-- Risk records remain protected by their existing organization-scoped RLS policy.
create policy "evaluaciones_riesgos_delete_org_admin"
on public.evaluaciones_riesgos
for delete
to authenticated
using (
  usuario_rol_organizacion(organizacion_id) = any (
    array['administrador_plataforma'::text, 'administrador_organizacion'::text]
  )
);
