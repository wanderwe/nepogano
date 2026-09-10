-- Фікс: "Відхилити" на вхідному email-запрошенні мовчки не працював.
--
-- friendships_select і friendships_update вже давно мають гілку
-- `addressee_email = auth.jwt() ->> 'email'` — саме тому адресат взагалі
-- БАЧИТЬ pending-запрошення (SELECT) і може його ПРИЙНЯТИ (UPDATE, addressee_id
-- ще null на цей момент, підтягується лише в момент прийняття). Але
-- friendships_delete цю саму гілку так і не отримав — лишився з
-- friends-migration.sql у первісному вигляді (`requester_id = auth.uid() or
-- addressee_id = auth.uid()`). DELETE під RLS без відповідного рядка не
-- падає помилкою, просто видаляє 0 рядків — тому клік "Відхилити" (новий
-- код, docs/friend-accepted-notice-migration.sql) рефрешив екран, а
-- запрошення лишалось на місці.
--
-- Безпечно розширювати так само, як SELECT/UPDATE вже розширені: для
-- ПРИЙНЯТОЇ дружби addressee_id вже виставлений на власний auth.uid()
-- адресата (і той шлях видалення вже й так працює через наявну гілку) —
-- ця добавка відкриває видалення ЛИШЕ для рядків, де я значусь як
-- addressee_email, тобто саме pending-запрошень на мою адресу.
drop policy if exists "friendships_delete" on public.friendships;
create policy "friendships_delete"
on public.friendships for delete
using (
  requester_id = auth.uid()
  or addressee_id = auth.uid()
  or addressee_email = auth.jwt() ->> 'email'
);
