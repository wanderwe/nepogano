-- Запусти це один раз у Supabase Dashboard → SQL Editor. Безпечно запускати
-- повторно (drop constraint if exists перед створенням заново).
--
-- Реальний баг, знайдений через повний перелік FK на auth.users (частина
-- передрелізного аудиту, checkins-user-fk-migration.sql): future_letters
-- мала on delete cascade і на author_id, і на recipient_id. Для author_id
-- це правильно (лист належить авторові — видаляється разом з його
-- акаунтом). Для recipient_id — ні: якщо ОТРИМУВАЧ листа видалить свій
-- акаунт, лист автора (чий акаунт лишається живим і не має до цього
-- стосунку) видалявся б повністю, хоча це контент автора, не отримувача.
--
-- recipient_id вже nullable (null = "собі", дефолт при написанні), тож
-- заміна на set null нічого не ламає схемно — просто лист втрачає
-- прив'язку до вже неіснуючого отримувача, а не зникає сам.
--
-- Той самий принцип, що вже коректно застосований у
-- subject_checkins.author_id (set null, не cascade) — щоденник лишається,
-- губиться лише атрибуція "хто написав".

alter table public.future_letters
  drop constraint if exists future_letters_recipient_id_fkey;

alter table public.future_letters
  add constraint future_letters_recipient_id_fkey
  foreign key (recipient_id) references auth.users(id) on delete set null;
