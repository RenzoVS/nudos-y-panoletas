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


-- ---------------------------------------------------------------------
-- 3. LIMPIEZA AUTOMÁTICA (agregada el 2026-11-25)
-- ---------------------------------------------------------------------
-- Antes de guardar o editar un juego, la base de datos ordena los textos:
-- quita espacios de más, pone mayúscula inicial y escribe siempre igual
-- los países ("peru" -> "Perú") y las instrucciones ("topografia" -> "Topografía").
-- Si agregas un país aquí, agrégalo también al menú "País" de index.html.

-- Extensión para comparar textos sin tildes ("Perú" = "peru").
create extension if not exists unaccent with schema extensions;


-- Quita espacios de más. Un texto vacío se vuelve null.
create or replace function public.limpiar_texto(t text)
returns text
language sql
immutable
set search_path = ''
as $$
  select nullif(regexp_replace(btrim(t), '\s+', ' ', 'g'), '')
$$;


-- Pone en mayúscula solo la primera letra ("conos" -> "Conos").
create or replace function public.mayuscula_inicial(t text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case when t is null then null else upper(left(t, 1)) || substr(t, 2) end
$$;


-- Convierte un texto en una "clave" para comparar: sin tildes, en
-- minúsculas y sin puntos ni signos ("EE.UU." -> "eeuu").
create or replace function public.clave_texto(t text)
returns text
language sql
stable
set search_path = ''
as $$
  select btrim(regexp_replace(lower(extensions.unaccent(coalesce(t, ''))), '[^a-z0-9 ]', '', 'g'))
$$;


-- Devuelve el nombre del país bien escrito.
create or replace function public.normalizar_pais(t text)
returns text
language sql
stable
set search_path = ''
as $$
  select case
    when public.limpiar_texto(t) is null then null
    else coalesce(
      -- 1. ¿Coincide con un país de la lista?
      (select p from unnest(array[
         'Alemania', 'Andorra', 'Argentina', 'Australia', 'Bolivia', 'Brasil',
         'Canadá', 'Chile', 'Colombia', 'Costa Rica', 'Cuba', 'Ecuador',
         'El Salvador', 'España', 'Estados Unidos', 'Filipinas', 'Francia',
         'Guatemala', 'Guinea Ecuatorial', 'Honduras', 'Italia', 'Japón',
         'México', 'Nicaragua', 'Panamá', 'Paraguay', 'Perú', 'Portugal',
         'Puerto Rico', 'Reino Unido', 'República Dominicana', 'Suiza',
         'Uruguay', 'Venezuela', 'Otro'
       ]) as p
       where public.clave_texto(p) = public.clave_texto(t)
       limit 1),
      -- 2. ¿Es una forma corta o común de escribirlo?
      case public.clave_texto(t)
        when 'eeuu' then 'Estados Unidos'
        when 'ee uu' then 'Estados Unidos'
        when 'usa' then 'Estados Unidos'
        when 'us' then 'Estados Unidos'
        when 'estados unidos de america' then 'Estados Unidos'
        when 'rd' then 'República Dominicana'
        when 'dominicana' then 'República Dominicana'
        when 'uk' then 'Reino Unido'
        when 'inglaterra' then 'Reino Unido'
        when 'mejico' then 'México'
        when 'brazil' then 'Brasil'
        when 'otro pais' then 'Otro'
      end,
      -- 3. Si no lo conocemos, solo ordenamos mayúsculas ("nueva zelanda" -> "Nueva Zelanda").
      initcap(public.limpiar_texto(t))
    )
  end
$$;


-- Devuelve el nombre de la instrucción bien escrito, si es una conocida.
create or replace function public.normalizar_instruccion(t text)
returns text
language sql
stable
set search_path = ''
as $$
  select case
    when public.limpiar_texto(t) is null then null
    else coalesce(
      (select i from unnest(array[
         'Nudos', 'Cabuyería', 'Orientación', 'Topografía', 'Primeros auxilios',
         'Campismo', 'Señales', 'Morse', 'Fuego', 'Cocina', 'Naturaleza',
         'Observación', 'Rastreo', 'Expresión', 'Liderazgo', 'Trabajo en equipo'
       ]) as i
       where public.clave_texto(i) = public.clave_texto(t)
       limit 1),
      public.mayuscula_inicial(public.limpiar_texto(t))
    )
  end
$$;


-- La función que ordena cada juego antes de guardarlo.
create or replace function public.normalizar_juego()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.titulo           := public.mayuscula_inicial(public.limpiar_texto(new.titulo));
  new.descripcion      := public.mayuscula_inicial(btrim(new.descripcion));
  new.cantidad         := public.limpiar_texto(new.cantidad);
  new.autor            := public.limpiar_texto(new.autor);
  new.grupo_scout      := public.limpiar_texto(new.grupo_scout);
  new.pais             := public.normalizar_pais(new.pais);
  new.tipo_instruccion := public.normalizar_instruccion(new.tipo_instruccion);

  -- Materiales: solo si la lista tiene el formato correcto (si no, la
  -- regla "materiales_validos" de la tabla la rechaza igual).
  if public.materiales_validos(new.materiales) then
    new.materiales := coalesce(
      (select jsonb_agg(jsonb_build_object(
                'material', public.mayuscula_inicial(public.limpiar_texto(e ->> 'material')),
                'cantidad', public.limpiar_texto(e ->> 'cantidad')))
         from jsonb_array_elements(new.materiales) as e),
      '[]'::jsonb);
  end if;

  return new;
end;
$$;

drop trigger if exists juegos_normalizar on public.juegos;
create trigger juegos_normalizar
  before insert or update on public.juegos
  for each row execute function public.normalizar_juego();
