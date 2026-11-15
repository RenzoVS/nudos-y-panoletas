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
-- 0. FUNCIÓN QUE REVISA LA LISTA DE MATERIALES
-- ---------------------------------------------------------------------
-- Los materiales se guardan como una lista (formato JSON):
--   [{"material": "Conos", "cantidad": "4"}, {"material": "Soga", "cantidad": "1 de 5 m"}]
-- Esta función devuelve "true" solo si la lista tiene ese formato:
-- máximo 30 materiales, cada uno con material (1 a 80 letras) y
-- cantidad (1 a 30 letras), y nada más.
create or replace function public.materiales_validos(m jsonb)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select jsonb_typeof(m) = 'array'
     and jsonb_array_length(m) <= 30
     and not exists (
       select 1
       from jsonb_array_elements(m) as e
       where jsonb_typeof(e) <> 'object'
          or coalesce(jsonb_typeof(e -> 'material'), '') <> 'string'
          or coalesce(jsonb_typeof(e -> 'cantidad'), '') <> 'string'
          or char_length(trim(e ->> 'material')) not between 1 and 80
          or char_length(trim(e ->> 'cantidad')) not between 1 and 30
          or (select count(*) from jsonb_object_keys(e)) <> 2
     )
$$;


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

  -- Lista de materiales con su cantidad (ver la función de arriba).
  -- Una lista vacía significa que el juego no necesita materiales.
  materiales      jsonb not null default '[]'::jsonb
                  check (public.materiales_validos(materiales)),

  -- Para qué ramas sirve: una lista con al menos una rama, y solo
  -- ramas de estas cuatro. Si agregas una rama nueva, cámbiala
  -- aquí y también en la lista RAMAS de js/app.js.
  ramas           text[] not null
                  check (cardinality(ramas) between 1 and 4
                         and ramas <@ array['lobatos', 'scouts', 'caminantes', 'rovers']::text[]),

  riesgo          text not null check (riesgo in ('bajo', 'medio', 'alto')),
  tipo            text not null check (tipo in ('activo', 'semiactivo', 'pasivo')),
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
