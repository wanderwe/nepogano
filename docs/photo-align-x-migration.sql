-- Додає горизонтальне позиціювання фото (панорамування вліво/вправо) поруч
-- з уже наявним вертикальним (`photo_align_y`/`avatar_align_y`). Раніше
-- рамка позиціювання (`PhotoRepositionScreen`) вміла рухати фото лише по
-- вертикалі — для типового портретного фото це покриває майже всі випадки
-- (ширина й так точно збігається з рамкою при BoxFit.cover), АЛЕ:
--   (а) для горизонтального фото (панорама, груповий кадр) навпаки —
--       зайвий простір горизонтальний, а панорамувати нема чим;
--   (б) навіть для портретного фото, щойно юзер наближує пінчем
--       (`_scale` > 1), з'являється горизонтальний overflow, якого не було
--       при масштабі 1 — і керувати ним раніше було нічим.
--
-- Ідемпотентно, безпечно виконувати повторно.

alter table public.checkins
  add column if not exists photo_align_x double precision not null default 0;

alter table public.subject_checkins
  add column if not exists photo_align_x double precision not null default 0;

alter table public.profiles
  add column if not exists avatar_align_x double precision not null default 0;
