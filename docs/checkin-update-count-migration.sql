-- Запусти це один раз у Supabase Dashboard → SQL Editor.
-- ВАЖЛИВО: виконуй ПІСЛЯ subjects-migration.sql — цей файл змінює також
-- таблицю subject_checkins, якої без неї ще не існує.
--
-- Додає лічильник, скільки разів людина сьогодні відредагувала вже
-- збережений запис (не рахує сам перший save — тільки повторні "Оновити").
-- Інкремент відбувається тригером у БД, а не з коду застосунку, щоб
-- рахунок був вірний навіть за паралельних чи повторних запитів.

alter table public.checkins add column if not exists update_count integer not null default 0;
alter table public.subject_checkins add column if not exists update_count integer not null default 0;

create or replace function public.increment_checkin_update_count()
returns trigger
language plpgsql
as $$
begin
  new.update_count := old.update_count + 1;
  return new;
end;
$$;

drop trigger if exists checkins_increment_update_count on public.checkins;
create trigger checkins_increment_update_count
before update on public.checkins
for each row execute function public.increment_checkin_update_count();

drop trigger if exists subject_checkins_increment_update_count on public.subject_checkins;
create trigger subject_checkins_increment_update_count
before update on public.subject_checkins
for each row execute function public.increment_checkin_update_count();
