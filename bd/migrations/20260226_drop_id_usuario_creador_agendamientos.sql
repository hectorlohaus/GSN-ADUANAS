-- Migración: Eliminar campo id_usuario_creador de la tabla agendamientos
-- Fecha: 2026-02-26
-- Descripción: Se elimina el campo id_usuario_creador (uuid, NOT NULL) junto con su
--              foreign key constraint hacia la tabla usuarios.
--              La eliminación se hace en cascada a nivel de constraint/columna.

-- Paso 1: Eliminar la foreign key constraint
ALTER TABLE public.agendamientos
  DROP CONSTRAINT IF EXISTS agendamientos_creador_fkey CASCADE;

-- Paso 2: Eliminar la columna
ALTER TABLE public.agendamientos
  DROP COLUMN IF EXISTS id_usuario_creador CASCADE;
