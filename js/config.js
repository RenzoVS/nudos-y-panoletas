// =====================================================================
// CONFIGURACIÓN · conexión con Supabase
// =====================================================================
// Aquí van los dos datos que conectan la página con la base de datos.
// Los encuentras en Supabase > tu proyecto > Project Settings > API Keys.
//
// ¿Es seguro que estén a la vista? Sí. La "publishable key" está hecha
// para usarse en páginas públicas. Lo que protege los datos son las
// reglas de seguridad del archivo supabase/esquema.sql.
//
// NUNCA pongas aquí la "secret key" (o "service_role"): esa da control
// total de la base de datos y no debe aparecer en ningún archivo público.
// =====================================================================

window.CONFIG = {
  SUPABASE_URL: "https://tgnhcxzyclcdzpyvrkip.supabase.co",
  SUPABASE_KEY: "sb_publishable__qTJJr6GddQJnif9owijzA_388biBQ8",
};
