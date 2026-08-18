-- Запусти це один раз у Supabase Dashboard → SQL Editor. Безпечно запускати
-- повторно (create or replace / drop trigger if exists перед створенням).
-- ВАЖЛИВО: виконуй ПІСЛЯ future-letters-recipient-fk-fix-migration.sql.
--
-- Той фікс замінив on delete cascade на on delete set null для
-- future_letters.recipient_id — правильно рятує лист автора від видалення,
-- коли ОТРИМУВАЧ видаляє акаунт. Але сам по собі recipient_id = null уже
-- означає "лист собі" по всьому клієнтському коду (_letterLabel,
-- timeCapsuleToSelfLabel) — тобто автор побачив би свій лист другові
-- переписаним, ніби він завжди був собі. Це вводить в оману сильніше, ніж
-- здавалось спочатку: спотворює факт того, що автор сам реально зробив.
--
-- Фікс: окрема колонка-прапорець, яку виставляє тригер САМЕ в момент
-- видалення отримувача (до того, як FK встигне про це подбати) — так
-- клієнт може відрізнити "завжди був собі" від "був другові, той видалив
-- акаунт".

alter table public.future_letters
  add column if not exists recipient_account_deleted boolean not null default false;

create or replace function public.mark_future_letters_recipient_deleted()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.future_letters
  set recipient_id = null, recipient_account_deleted = true
  where recipient_id = old.id;
  return old;
end;
$$;

drop trigger if exists future_letters_recipient_deleted on auth.users;
create trigger future_letters_recipient_deleted
before delete on auth.users
for each row
execute function public.mark_future_letters_recipient_deleted();
