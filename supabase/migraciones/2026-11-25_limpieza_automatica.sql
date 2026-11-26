-- =====================================================================
-- 2026-11-25 · Limpieza automática de los juegos que llegan
-- =====================================================================
-- Antes de guardar (o editar) un juego, la base de datos ordena los textos:
--   * Quita espacios de más al inicio, al final y en medio.
--   * Pone mayúscula inicial al título, la descripción, la instrucción
--     y cada material.
--   * Escribe el país siempre igual: "peru", "PERU" o "Peru" -> "Perú";
--     "eeuu" o "usa" -> "Estados Unidos".
--   * Escribe igual las instrucciones conocidas: "topografia" -> "Topografía".
-- Así la página se ve ordenada aunque alguien escriba con prisa.
--
-- Si agregas un país a la lista de abajo, agrégalo también al menú
-- desplegable de index.html (campo "País").
-- =====================================================================

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
