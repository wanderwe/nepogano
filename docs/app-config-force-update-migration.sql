-- Запусти це один раз у Supabase Dashboard → SQL Editor.
--
-- Мінімальна підтримувана версія застосунку по платформі — основа для
-- жорсткого force-update: якщо білд-номер юзера нижчий за це число,
-- застосунок показує блокуючий екран "онови, щоб продовжити" без
-- можливості обійти. Причина, чому це саме таблиця в базі, а не
-- захардкожене число в коді: нове мінімальне значення можна підняти
-- одразу для всіх юзерів без нового білда й ревʼю в сторі — сам факт
-- випуску нового білда сам по собі НІКОГО не змушує оновитись, юзер
-- лишається на старій версії, доки сам не оновить чи ми не піднімемо
-- поріг тут.
--
-- Окремі рядки на платформу (не одне спільне число) — бо номери білдів
-- iOS і Android вже розійшлись один раз (1.7.0+21 не пройшов review на
-- iOS і замінений на 1.7.1+22, тоді як на Android 1.7.0+21 уже живий) і
-- можуть розійтись знову.

create table if not exists public.app_config (
  platform text primary key check (platform in ('android', 'ios')),
  min_build_number int not null,
  updated_at timestamptz not null default now()
);

alter table public.app_config enable row level security;

-- Читати може будь-хто, навіть неавторизований — перевірка версії
-- відбувається одразу при старті застосунку, ще до входу в акаунт.
-- Змінювати може лише сам розробник напряму через Dashboard (service
-- role обходить RLS) — свідомо жодної insert/update-політики для
-- authenticated/anon немає.
drop policy if exists "app_config_select_all" on public.app_config;
create policy "app_config_select_all"
on public.app_config for select
using (true);

-- Стартові значення = поточний зібраний білд (1.7.1+22) — тобто ніхто не
-- заблокований одразу після виконання цієї міграції. Піднімай
-- min_build_number вручну в Dashboard, коли захочеш форсувати оновлення
-- до конкретного білда.
insert into public.app_config (platform, min_build_number) values
  ('android', 22),
  ('ios', 22)
on conflict (platform) do nothing;
