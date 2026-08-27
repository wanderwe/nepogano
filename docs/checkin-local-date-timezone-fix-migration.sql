-- Виправляє реальний баг: право коментувати чужий день (can_comment_on_checkin/
-- can_comment_on_subject_checkin) звірялось з `created_at::date`, а це кастить
-- TIMESTAMPTZ у DATE за таймзоною сесії Postgres — типово UTC, не локальним
-- часом користувача. Клієнт же рахує дату вгадування (`target_date`) з
-- ЛОКАЛЬНОГО часу пристрою. Для чек-іну, зробленого вночі за київським часом
-- (приблизно 00:00-03:00, залежно від літнього/зимового часу) — це вже
-- "сьогодні" локально, але ще "вчора" за UTC. Клієнт пише вгадування з
-- сьогоднішньою (локальною) датою, RLS шукає збіг з учорашньою (UTC) —
-- не знаходить, і коментар відхиляється, хоч вгадування насправді відбулось
-- і інтерфейс чесно показав розкритий день.
--
-- Рішення: зберігати локальну дату явно в окремій колонці, заповнювану
-- клієнтом при СТВОРЕННІ запису (той самий спосіб, що вже рахує target_date
-- для вгадувань) — не виводити її з created_at на льоту. На UPDATE (редагування
-- вже існуючого запису) ця колонка не чіпається, лишається такою, якою була
-- зафіксована при створенні.
--
-- Ідемпотентно, безпечно виконувати повторно.

alter table public.checkins
  add column if not exists local_date date;

alter table public.subject_checkins
  add column if not exists local_date date;

-- Бекфіл для вже існуючих рядків: наближення через created_at::date (UTC) —
-- для старих записів немає способу дізнатись справжню локальну дату автора
-- заднім числом, тож це компроміс, який не гірший за попередню поведінку.
-- Нові записи від цього моменту клієнт заповнюватиме правильно.
update public.checkins
  set local_date = created_at::date
  where local_date is null;

update public.subject_checkins
  set local_date = created_at::date
  where local_date is null;

create or replace function public.can_comment_on_checkin(target_checkin_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.checkins c
    where c.id = target_checkin_id
      and (
        c.user_id = auth.uid()
        or exists (
          select 1 from public.circle_guesses g
          where g.guesser_id = auth.uid()
            and g.target_user_id = c.user_id
            and g.target_date = coalesce(c.local_date, c.created_at::date)
        )
      )
  );
$$;

create or replace function public.can_comment_on_subject_checkin(target_subject_checkin_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select public.owns_or_coauthors_subject_checkin(target_subject_checkin_id)
    or exists (
      select 1 from public.subject_checkins sc
      join public.subject_guesses g
        on g.subject_id = sc.subject_id
        and g.target_date = coalesce(sc.local_date, sc.created_at::date)
      where sc.id = target_subject_checkin_id and g.guesser_id = auth.uid()
    );
$$;
