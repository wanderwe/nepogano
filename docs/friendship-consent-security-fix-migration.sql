-- КРИТИЧНО: запусти це в Supabase Dashboard → SQL Editor якнайшвидше,
-- незалежно від того, коли вийде наступний білд застосунку — діра на
-- рівні бази, старі версії застосунку на неї так само вразливі.
--
-- Знайдено при security-аудиті 2026-09-05. Два незалежні реальні способи
-- прочитати чужий приватний щоденник (настрій/нотатку/фото) чи коментарі
-- без будь-якого дозволу власника, знаючи лише його UUID (не email, не
-- friend_code — сам UUID уже "витікає" в кількох місцях, напр. як
-- author_id чужого коментаря під спільним записом).
--
-- 1) friendships_insert (friends-migration.sql) перевіряла лише
--    `requester_id = auth.uid()` — нічого не забороняло одразу вставити
--    рядок зі status='accepted' і будь-яким addressee_id, минаючи весь
--    цикл "pending → приймає адресат". checkins_select_friends довіряє
--    ЦЬОМУ ЖЕ рядку без жодної додаткової перевірки з боку адресата.
--    Легітимний шлях (`add_friend_by_code`) і так завжди створює
--    status='accepted' напряму через SECURITY DEFINER (обхід RLS) — тому
--    звуження RLS-політики до status='pending' НЕ ламає add_friend_by_code,
--    лише закриває обхідний прямий INSERT через REST/клієнт.
--
-- 2) circle_guesses_insert (circles-migration.sql) перевіряла лише
--    `guesser_id = auth.uid()` — узагалі не гейтилась дружбою, залишок
--    ще з до-friendships моделі (коментар "лишається без змін" тоді
--    мав на увазі форму таблиці, не безпеку). can_comment_on_checkin
--    довіряє БУДЬ-ЯКОМУ рядку circle_guesses для потрібної пари
--    (guesser, target, date) — без перевірки на дружбу і без перевірки
--    correct=true (яке й так рахується клієнтом, тож нічого не гарантує).
--    Наслідок: хтось, хто знає чужий UUID і дату, вставляє один рядок
--    circle_guesses з довільним guessed_mood — і одразу отримує доступ
--    читати/писати в приватний тред коментарів під тим днем, не будучи
--    другом.
--
-- 3-4) add_friend_by_code і delete_own_account (SECURITY DEFINER) ніколи
--    не мали `revoke ... from public` — той самий клас, який
--    security-audit-fixes-migration.sql уже закривав для
--    resolve_friend_code/cleanup_unconfirmed_users, просто пропущений тоді
--    для цих двох. delete_own_account зараз нешкідливий без сесії (усі
--    WHERE проти auth.uid() дають null), але add_friend_by_code читає
--    auth.users.email під SECURITY DEFINER до провалу — анонімний виклик
--    з чужим дійсним friend_code міг би розкрити email власника коду
--    через DETAIL у помилці "requester_id not null violation".

-- 1. friendships_insert: прямий INSERT з клієнта може створити лише
-- 'pending' — 'accepted' лишається доступним тільки через
-- add_friend_by_code (SECURITY DEFINER, обходить RLS) чи через
-- friendships_update, коли реальний адресат (за email з JWT) сам
-- підтверджує зустрічний запит.
drop policy if exists "friendships_insert" on public.friendships;
create policy "friendships_insert"
on public.friendships for insert
with check (requester_id = auth.uid() and status = 'pending');

-- 2. circle_guesses_insert: вгадувати можна тільки того, з ким я вже
-- прийнятий друг — той самий вимір видимості, що вже й так дає
-- checkins_select_friends, просто дзеркалений тут явно замість мовчазної
-- довіри "раз він угадав — значить, мав право".
drop policy if exists "circle_guesses_insert" on public.circle_guesses;
create policy "circle_guesses_insert"
on public.circle_guesses for insert
with check (
  guesser_id = auth.uid()
  and exists (
    select 1 from public.friendships
    where status = 'accepted'
      and (
        (requester_id = auth.uid() and addressee_id = target_user_id)
        or (addressee_id = auth.uid() and requester_id = target_user_id)
      )
  )
);

-- 3-4. Той самий revoke-фікс, що вже застосований до
-- resolve_friend_code/cleanup_unconfirmed_users — просто пропущений тоді
-- для цих двох функцій.
revoke execute on function public.add_friend_by_code(text) from public;
grant execute on function public.add_friend_by_code(text) to authenticated;

revoke execute on function public.delete_own_account() from public;
grant execute on function public.delete_own_account() to authenticated;
