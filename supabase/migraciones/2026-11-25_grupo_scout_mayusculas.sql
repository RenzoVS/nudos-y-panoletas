-- =====================================================================
-- 2026-11-25 · Grupo scout con mayúsculas
-- =====================================================================
-- Si el grupo scout llega todo en minúsculas ("san borja 99"), se guarda
-- con mayúscula en cada palabra ("San Borja 99"). Si ya trae mayúsculas
-- ("ASP Grupo 5"), se respeta tal cual.
-- =====================================================================

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
  if new.grupo_scout is not null and new.grupo_scout = lower(new.grupo_scout) then
    new.grupo_scout := initcap(new.grupo_scout);
  end if;
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

-- Vuelve a pasar los juegos existentes por la limpieza.
update public.juegos set grupo_scout = grupo_scout;
