-- =====================================================================
-- Cambio del 15 de noviembre de 2026
-- =====================================================================
-- 1. "rama" (una sola) pasa a ser "ramas" (lista: se pueden marcar varias).
-- 2. "materiales" pasa de texto libre a una lista de material + cantidad.
-- 3. "tipo" suma una tercera opción: semiactivo.
--
-- Se aplicó cuando la tabla todavía estaba vacía, por eso se pueden
-- borrar y crear las columnas sin convertir datos.
-- El archivo supabase/esquema.sql ya refleja el resultado final.
-- =====================================================================

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

alter table public.juegos drop column rama;
alter table public.juegos add column ramas text[] not null
  check (cardinality(ramas) between 1 and 4
         and ramas <@ array['lobatos', 'scouts', 'caminantes', 'rovers']::text[]);

alter table public.juegos drop column materiales;
alter table public.juegos add column materiales jsonb not null default '[]'::jsonb
  check (public.materiales_validos(materiales));

alter table public.juegos drop constraint juegos_tipo_check;
alter table public.juegos add constraint juegos_tipo_check
  check (tipo in ('activo', 'semiactivo', 'pasivo'));
