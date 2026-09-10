-- КРИТИЧНО: запусти це в Supabase Dashboard → SQL Editor якнайшвидше —
-- закриває реальну діру, яку відкрив мій ЩОЙНО застосований
-- friends-decline-invite-rls-fix-migration.sql (уже виконаний).
--
-- Той файл додав до friendships_delete гілку
-- `addressee_email = auth.jwt() ->> 'email'`, щоб адресат міг видалити
-- (відхилити) pending email-запрошення, де addressee_id ще null.
-- Але гілку не звузили до status = 'pending' — а `addressee_email`
-- ніде в коді не оновлюється ПІСЛЯ створення рядка (write-once).
--
-- Наслідок: якщо юзер D (реальний адресат уже ПРИЙНЯТОЇ дружби з
-- C) колись змінить свій auth-email на щось інше, старий email
-- лишається "замороженим" у friendships.addressee_email на тому
-- рядку. Якщо згодом хтось СТОРОННІЙ, E, зареєструє новий акаунт
-- саме на цю стару адресу (Supabase дозволяє це — унікальність email
-- перевіряється лише проти ПОТОЧНИХ акаунтів, не історичних), JWT
-- юзера E тепер збігається з цим застарілим addressee_email — і E,
-- не будучи ні requester_id, ні addressee_id цього рядка, може
-- видалити чужу вже прийняту дружбу між C і D прямим REST DELETE.
--
-- Той самий клас діри, що вже двічі закривався в цьому проєкті
-- (friendship-consent-security-fix, rls-followup-audit-fix): permissive
-- гілка на застиглому/денормалізованому полі замість живого стану
-- рядка. Фікс — точно той, що й планувався спочатку (сам коментар у
-- попередній міграції казав "pending-запрошень на мою адресу"), просто
-- забули дописати умову.
drop policy if exists "friendships_delete" on public.friendships;
create policy "friendships_delete"
on public.friendships for delete
using (
  requester_id = auth.uid()
  or addressee_id = auth.uid()
  or (addressee_email = auth.jwt() ->> 'email' and status = 'pending')
);
