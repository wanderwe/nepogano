-- Запусти це один раз у Supabase Dashboard → SQL Editor. Безпечно запускати
-- повторно (перевіряє існування констрейнта перед додаванням).
--
-- checkins.user_id ніколи не мав foreign key на auth.users(id) — таблиця
-- передує цій історії міграцій і не в git. RLS (Users can insert own
-- checkins: with check auth.uid() = user_id) і так гарантує, що кожен
-- рядок належить справжньому юзеру на момент запису, а delete_own_account()
-- явно видаляє checkins окремим рядком коду до видалення auth.users, тож
-- сьогодні "осиротілих" рядків бути не повинно і функціонально нічого не
-- ламається. Це суто про консистентність з рештою таблиць (усі інші мають
-- on delete cascade) і страховку на майбутнє, якщо юзера колись видалять
-- НЕ через delete_own_account() (вручну з Dashboard, Admin API).
--
-- NOT VALID + окремий VALIDATE CONSTRAINT замість одного ADD CONSTRAINT:
-- каскад працює одразу для всіх НОВИХ операцій, а перевірка вже існуючих
-- рядків не тримає довгу блокуючу транзакцію на всій таблиці. Якщо
-- validate провалиться (тобто десь таки є рядок з user_id, якого нема
-- в auth.users) — сам констрейнт лишиться на місці й далі захищає нові
-- записи, просто повідомить, які саме старі рядки почистити вручну.

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.checkins'::regclass
      and conname = 'checkins_user_id_fkey'
  ) then
    alter table public.checkins
      add constraint checkins_user_id_fkey
      foreign key (user_id) references auth.users(id) on delete cascade
      not valid;
  end if;
end $$;

alter table public.checkins
  validate constraint checkins_user_id_fkey;
