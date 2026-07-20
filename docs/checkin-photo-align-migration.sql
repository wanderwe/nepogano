-- Запусти це один раз у Supabase Dashboard → SQL Editor.
-- Додає вертикальне зміщення кадрування фото (-1 = зверху, 0 = центр,
-- 1 = знизу) — щоб можна було підняти/опустити видиму частину фото,
-- якщо BoxFit.cover зрізав щось важливе (наприклад, голову).

alter table public.checkins
  add column if not exists photo_align_y double precision not null default 0;
