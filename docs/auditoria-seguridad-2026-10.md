# Revisión de seguridad — Sistema de Higiene y Seguridad

Fecha de revisión: 21 de octubre de 2026  
Repositorio revisado: `franonline80-png/sistema-higiene-seguridad`

## Alcance y limitaciones

Se inspeccionaron el código cliente `index.html`, el inicio de sesión, la carga de organizaciones y la migración disponible para el historial de sesiones. Esta revisión estática no equivale a una prueba de penetración ni permite certificar la configuración activa de Supabase. No se dispone de acceso administrativo al proyecto para inspeccionar las políticas RLS desplegadas, secretos, configuración de autenticación, registros ni estado de las migraciones.

## Controles observados

- El inicio de sesión utiliza Supabase Auth (`signInWithPassword`) y la sesión se consulta con `auth.getUser()`.
- La aplicación obtiene las organizaciones asociadas al usuario a través de `usuarios_organizaciones` y filtra las membresías por `usuario_id` y `activo = true`.
- Las consultas de negocio usan `organizacion_id` en distintos flujos de cliente; esto es útil como filtro funcional, pero no sustituye las políticas RLS de la base.
- La clave publicada en el frontend tiene formato de clave publicable de Supabase. Una clave publicable puede estar en el navegador; la protección de datos depende de RLS y de que nunca se exponga una clave `service_role`.
- La migración incluida para `sesiones_usuario` habilita RLS y limita las filas al usuario autenticado mediante `auth.uid() = usuario_id`.

## Riesgos y verificaciones pendientes (bloqueantes para una aprobación completa)

1. **RLS de las tablas de negocio no verificable desde el repositorio.** No se encontraron en el árbol revisado migraciones que permitan confirmar las políticas de las tablas principales. Debe verificarse que cada tabla con datos de organizaciones aplica RLS y que SELECT/INSERT/UPDATE/DELETE se limitan a organizaciones a las que pertenece el usuario activo.
2. **Permisos de membresía.** Debe comprobarse que un usuario normal no puede agregarse a otra organización, cambiar su propio rol ni reactivar su membresía modificando `usuarios_organizaciones`.
3. **Prueba entre organizaciones.** Se necesita una prueba autenticada con dos cuentas de organizaciones diferentes, intentando leer y modificar IDs ajenos directamente, no solo desde la interfaz.
4. **Configuración Supabase no disponible.** No se pudieron verificar MFA/confirmación de correo, restricciones de contraseña, rate limits, logs, políticas Storage existentes, backups ni exposición de tablas/vistas.
5. **Revisión de entradas y renderizado.** El código usa `innerHTML` en distintos módulos. Se observa una función `escapeHtml`, pero cada dato dinámico debe revisarse para asegurar que se escapa en todos los puntos de inserción.
6. **Pruebas de despliegue.** No se ejecutaron pruebas dinámicas de autenticación, autorización, XSS ni aislamiento en el sitio de producción.

## Resultado

**Estado: revisión parcial; no corresponde declarar “auditoría aprobada” todavía.** No se realizó ningún cambio en la base de datos de producción. Antes de aprobar, hay que inspeccionar las políticas RLS reales y ejecutar pruebas de aislamiento entre organizaciones con cuentas de prueba.

## Recomendación operativa

Mantener el acceso solo para usuarios conocidos, no publicar datos sensibles de prueba y no agregar secretos de servidor al frontend. Aplicar nuevas migraciones en un entorno de prueba primero y comprobar que las políticas no bloquean las operaciones legítimas ni permiten accesos cruzados.
