-- Запусти це один раз у Supabase Dashboard → SQL Editor. Безпечно запускати
-- повторно.
--
-- Реальна прогалина, знайдена наживо: `profiles_select_friends`
-- (friends-migration.sql) дозволяє бачити чийсь display_name лише прямим
-- друзям. Але коментарі бачать усі, кому дозволено сам тред
-- (can_comment_on_checkin/can_comment_on_subject_checkin) — а це ширше
-- коло, ніж "прямі друзі": наприклад, два різні друзі однієї людини не
-- обов'язково друзі одне одному, але обидва можуть лишати коментарі під
-- її днем і бачити коментарі одне одного. Ім'я автора такого коментаря
-- не резолвилось — CommentsSection показувало порожній рядок замість
-- імені.
--
-- Фікс: додаткова, вузько специфічна SELECT-політика — бачиш display_name
-- людини рівно тоді, коли вона лишила коментар у треді, який ти сам маєш
-- право коментувати/бачити. Не ширше цього — не відкриває display_name
-- взагалі всім автентифікованим юзерам, лише в межах уже наявного кола
-- довіри навколо конкретного коментаря.

drop policy if exists "profiles_select_co_commenters" on public.profiles;
create policy "profiles_select_co_commenters"
on public.profiles for select
using (
  exists (
    select 1 from public.checkin_comments c
    where c.author_id = profiles.user_id
      and public.can_comment_on_checkin(c.checkin_id)
  )
  or exists (
    select 1 from public.subject_checkin_comments c
    where c.author_id = profiles.user_id
      and public.can_comment_on_subject_checkin(c.subject_checkin_id)
  )
);
