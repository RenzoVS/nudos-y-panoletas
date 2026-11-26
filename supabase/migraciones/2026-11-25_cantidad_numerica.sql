-- =====================================================================
-- 2026-11-25 · "¿Para cuántos scouts?" con números en vez de texto libre
-- =====================================================================
-- Antes: una columna de texto ("cantidad") donde se podía escribir cualquier cosa.
-- Ahora: dos números.
--   cantidad_min: mínimo de scouts (obligatorio, de 1 a 300).
--   cantidad_max: máximo de scouts (opcional; vacío = sin máximo).
--                 Si se llena, no puede ser menor que el mínimo.
-- =====================================================================

alter table public.juegos
  add column if not exists cantidad_min smallint,
  add column if not exists cantidad_max smallint;

-- Pasar los juegos que ya existían al formato nuevo.
update public.juegos set cantidad_min = 10, cantidad_max = 16
  where cantidad_min is null and cantidad = 'de 10 a 16';
update public.juegos set cantidad_min = 2, cantidad_max = null
  where cantidad_min is null and cantidad = 'indefinido';
-- Cualquier otro caso (no debería haber): mínimo 1, sin máximo.
update public.juegos set cantidad_min = 1 where cantidad_min is null;

alter table public.juegos alter column cantidad_min set not null;

alter table public.juegos drop constraint if exists juegos_cantidad_valida;
alter table public.juegos add constraint juegos_cantidad_valida check (
  cantidad_min between 1 and 300
  and (cantidad_max is null or cantidad_max between cantidad_min and 300)
);

-- La limpieza automática ya no toca la columna de texto (se elimina abajo).
create or replace function public.normalizar_juego()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.titulo           := public.mayuscula_inicial(public.limpiar_texto(new.titulo));
  new.descripcion      := public.mayuscula_inicial(btrim(new.descripcion));
  new.autor            := public.limpiar_texto(new.autor);
  new.grupo_scout      := public.limpiar_texto(new.grupo_scout);
  new.pais             := public.normalizar_pais(new.pais);
  new.tipo_instruccion := public.normalizar_instruccion(new.tipo_instruccion);

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

alter table public.juegos drop column if exists cantidad;
