-- Migration: 001_create_get_bloques_disponibles
-- Descripción: Crea la función que retorna los bloques horarios disponibles para una fecha dada.

CREATE OR REPLACE FUNCTION public.get_bloques_disponibles(fecha_seleccionada date)
RETURNS TABLE (
  id_bloque   integer,
  descripcion text,
  hora_inicio time,
  hora_fin    time
)
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
  RETURN QUERY
  SELECT
    b.id_bloque,
    b.descripcion,
    b.hora_inicio,
    b.hora_fin
  FROM
    public.bloques_horarios b
  WHERE
    b.id_bloque NOT IN (
      SELECT a.id_bloque
      FROM public.agendamientos a
      WHERE a.fecha_agendada = fecha_seleccionada
    );
END;
$$;

-- Concede permisos de ejecución a los roles de Supabase
GRANT EXECUTE ON FUNCTION public.get_bloques_disponibles(date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_bloques_disponibles(date) TO anon;
GRANT EXECUTE ON FUNCTION public.get_bloques_disponibles(date) TO service_role;
