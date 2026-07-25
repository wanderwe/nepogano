-- Запусти це один раз у Supabase Dashboard → SQL Editor.
-- ВАЖЛИВО: виконуй ПІСЛЯ subjects-migration.sql — цей файл змінює також
-- таблицю subject_checkins, якої без неї ще не існує.
--
-- Додає масштаб (zoom) фото при кадруванні — доповнює photo_align_y
-- (вертикальне зміщення) можливістю наблизити фото пінчем, а не лише
-- зсунути видиму частину вгору/вниз. 1 = без зуму (як BoxFit.cover за
-- замовчуванням), більше — наближено.

alter table public.checkins add column if not exists photo_scale double precision not null default 1;
alter table public.subject_checkins add column if not exists photo_scale double precision not null default 1;
