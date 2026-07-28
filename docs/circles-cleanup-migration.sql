-- Запусти це один раз у Supabase Dashboard → SQL Editor.
-- ВАЖЛИВО: виконуй ПІСЛЯ friends-migration.sql.
--
-- Прибирає стару модель "кола" (circles/circle_members), яку замінили на
-- friendships ще в friends-migration.sql і про яку код більше нічого не
-- знає (перевірено: жодного посилання в lib/, жодного виклику
-- join_circle_by_code). НЕ чіпає circle_guesses — це окрема, повністю жива
-- таблиця гри-вгадування, просто випадково лежала в тому самому старому
-- файлі circles-migration.sql; friends-migration.sql явно лишає її без змін.
--
-- Разом з цим виправляє реальну прогалину, яку виявила ця перевірка:
-- політика checkin_photos_select (доступ до чужих фото чек-інів у сховищі)
-- досі була побудована на circle_members і НІКОЛИ не була замінена на
-- friendships, коли решта застосунку перейшла (friends-migration.sql
-- замінив аналогічну checkins_select_circle_mates на checkins_select_friends,
-- але про фото-політику тоді забули). Тобто фото між друзями фактично не
-- мали захищеного доступу через нову модель дружби — лишалось видно тільки
-- тим, хто випадково лишився членом старого кола ще з часів до дружби.

-- 1) Фото: замінити circle_members-політику на friendships-версію,
-- що дзеркалить уже наявну checkins_select_friends.
drop policy if exists "checkin_photos_select" on storage.objects;
drop policy if exists "checkin_photos_select_friends" on storage.objects;

create policy "checkin_photos_select_friends"
on storage.objects for select
using (
  bucket_id = 'checkin-photos'
  and (
    (storage.foldername(name))[1] = auth.uid()::text
    or (storage.foldername(name))[1] in (
      select addressee_id::text from public.friendships
      where requester_id = auth.uid() and status = 'accepted' and addressee_id is not null
      union
      select requester_id::text from public.friendships
      where addressee_id = auth.uid() and status = 'accepted'
    )
  )
);

-- 2) Прибрати саму стару модель кіл — RPC, таблиці (з їхніми політиками й
-- унікальним індексом circles_invite_code_idx через CASCADE), helper-функції.
drop function if exists public.join_circle_by_code(text);
drop table if exists public.circle_members cascade;
drop table if exists public.circles cascade;
drop function if exists public.is_circle_member(uuid);
drop function if exists public.is_circle_owner(uuid);
drop function if exists public.is_circle_invitee(uuid);
