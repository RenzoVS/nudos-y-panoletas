-- =====================================================================
-- NUDOS Y PAÑOLETAS · Esquema de la base de datos (Supabase / PostgreSQL)
-- =====================================================================
-- Este archivo crea la tabla donde se guardan los juegos y las reglas
-- de seguridad que deciden quién puede leer y quién puede escribir.
--
-- Cómo usarlo a mano (si algún día lo necesitas):
--   Supabase > tu proyecto > SQL Editor > New query > pega todo > Run.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. TABLA "juegos"
-- ---------------------------------------------------------------------
-- Cada fila es un juego publicado por un dirigente.
-- Los "check" son validaciones: si un dato no cumple, la base de datos
-- lo rechaza aunque alguien intente saltarse el formulario de la página.
create table if not exists public.juegos (
  -- Identificador único, se genera solo.
  id              uuid primary key default gen_random_uuid(),

  -- Fecha y hora en que se envió el juego, se llena sola.
  creado_en       timestamptz not null default now(),

  -- Datos del juego (los campos que pide el formulario).
  titulo          text not null check (char_length(titulo) between 3 and 120),
  descripcion     text not null check (char_length(descripcion) between 10 and 5000),
  materiales      text not null check (char_length(materiales) between 1 and 1000),

  -- Para qué rama es. Si agregas una rama nueva, cámbiala aquí
  -- y también en la lista RAMAS de js/app.js.
  rama            text not null check (rama in ('lobatos', 'scouts', 'caminantes', 'rovers', 'todas')),

  riesgo          text not null check (riesgo in ('bajo', 'medio', 'alto')),
  tipo            text not null check (tipo in ('activo', 'pasivo')),
  cantidad        text not null check (char_length(cantidad) between 1 and 60),

  -- Juego aplicativo: si es "true", hay que indicar la instrucción
  -- (nudos, orientación, primeros auxilios, etc.).
  aplicativo      boolean not null default false,
  tipo_instruccion text check (tipo_instruccion is null or char_length(tipo_instruccion) <= 120),

  -- Quién lo comparte (opcional). Nunca se piden datos de menores.
  autor           text check (autor is null or char_length(autor) <= 80),
  grupo_scout     text check (grupo_scout is null or char_length(grupo_scout) <= 120),
  pais            text check (pais is null or char_length(pais) <= 60),

  -- Moderación: todo juego nuevo entra como "pendiente" y solo
  -- aparece en la página cuando un moderador lo cambia a "aprobado".
  estado          text not null default 'pendiente'
                  check (estado in ('pendiente', 'aprobado', 'rechazado')),

  -- Regla extra: un juego aplicativo debe decir qué instrucción aplica.
  constraint aplicativo_requiere_instruccion
    check (not aplicativo or (tipo_instruccion is not null and char_length(trim(tipo_instruccion)) > 0))
);

-- Índice para que la página cargue rápido los juegos aprobados más nuevos.
create index if not exists juegos_estado_creado_idx
  on public.juegos (estado, creado_en desc);


-- ---------------------------------------------------------------------
-- 2. SEGURIDAD (Row Level Security)
-- ---------------------------------------------------------------------
-- La página usa una clave pública (la "publishable key"), así que
-- cualquiera podría intentar usarla. Por eso la seguridad vive aquí,
-- en la base de datos, y no en la página.
alter table public.juegos enable row level security;

-- Regla de lectura: los visitantes solo ven juegos aprobados.
drop policy if exists "Visitantes ven juegos aprobados" on public.juegos;
create policy "Visitantes ven juegos aprobados"
  on public.juegos
  for select
  to anon, authenticated
  using (estado = 'aprobado');

-- Regla de escritura: cualquiera puede proponer un juego,
-- pero solo con estado "pendiente" (no puede autoaprobarse).
drop policy if exists "Visitantes proponen juegos" on public.juegos;
create policy "Visitantes proponen juegos"
  on public.juegos
  for insert
  to anon, authenticated
  with check (estado = 'pendiente');

-- No hay reglas para editar ni borrar: los visitantes no pueden hacerlo.
-- Los moderadores (Renzo y Ale) aprueban, rechazan o borran juegos desde
-- Supabase > Table Editor > juegos, que no pasa por estas reglas.
