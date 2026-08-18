-- Запусти це один раз у Supabase Dashboard → SQL Editor. Безпечно запускати
-- повторно (drop policy if exists / revoke, потім create/grant заново).
--
-- Три незалежні, суто адитивні виправлення з повного передрелізного аудиту
-- безпеки. Кожне звужує існуючий доступ, нічого не розширює.

-- 1) checkin_photos_select_friends давала другу доступ до ВСІЄЇ папки
-- {user_id}/ у сховищі checkin-photos — включно з фото приватних щоденників
-- (subject_checkins), не лише власних чек-інів. Табличний RLS на
-- subject_checkins і так ховає сам рядок (і photo_path) від неавторизованого
-- друга, тож зараз це не одноклікова діра через сам застосунок — але це
-- той самий клас бага, що вже двічі траплявся (правила 4 і 23 в
-- ARCHITECTURE.md): storage-політика побудована на "чия це папка", а не на
-- "чи справді це фото належить рядку, який другу видно". Звужуємо: друг
-- бачить фото лише якщо воно справді прив'язане до checkins.photo_path
-- ВЛАСНИКА цієї папки — той самий патерн, що вже використаний у
-- checkin_photos_select_subject_shared для сутностей.
drop policy if exists "checkin_photos_select_friends" on storage.objects;

create policy "checkin_photos_select_friends"
on storage.objects for select
using (
  bucket_id = 'checkin-photos'
  and (
    (storage.foldername(name))[1] = auth.uid()::text
    or exists (
      select 1 from public.checkins c
      where c.photo_path = storage.objects.name
        and (
          c.user_id in (
            select addressee_id from public.friendships
            where requester_id = auth.uid() and status = 'accepted' and addressee_id is not null
            union
            select requester_id from public.friendships
            where addressee_id = auth.uid() and status = 'accepted'
          )
        )
    )
  )
);

-- 2) resolve_friend_code навмисно не перевіряє auth.uid() (щоб показати ім'я
-- ще до прийняття запиту в друзі), тому будь-яке обмеження доступу мало
-- прийти виключно з GRANT-рівня — а grant execute ... to authenticated в
-- friends-migration.sql не прибирав дефолтний PUBLIC-грант, який Postgres
-- ставить автоматично при створенні функції. Тобто повністю неавтентифікований
-- виклик (лише публічний anon-ключ, без входу) міг підбирати display_name
-- за 8-символьним кодом. Прибираємо PUBLIC, лишаємо тільки authenticated.
revoke execute on function public.resolve_friend_code(text) from public;
grant execute on function public.resolve_friend_code(text) to authenticated;

-- 3) cleanup_unconfirmed_users взагалі не мала жодного grant-рядка — тобто
-- теж лишалась на дефолтному PUBLIC. Вона призначена виключно для pg_cron
-- (див. cleanup-unconfirmed-users-migration.sql), клієнт її ніколи не має
-- викликати напряму. Прибираємо доступ повністю, без повторного гранту —
-- cron виконує функції від імені власника бази, GRANT для цього не потрібен.
revoke execute on function public.cleanup_unconfirmed_users() from public;
