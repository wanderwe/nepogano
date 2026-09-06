-- КРИТИЧНО: запусти це в Supabase Dashboard → SQL Editor якнайшвидше —
-- чотири незалежні реальні способи для одного юзера прочитати чи змінити
-- чужі дані, знайдені повторним аудитом УСІЄЇ міграційної історії
-- 2026-09-06 (фонові агенти прогнали всі 39 SQL-файлів заново, шукаючи,
-- що міг пропустити попередній аудит 2026-09-05).
--
-- 1) friendships_update дозволяла requester_id теж міняти status на
--    'accepted' напряму — той самий клас діри, що вже закрили для
--    friendships_insert учора, лишився відкритим через UPDATE. Юзер
--    вставляє pending-рядок на себе як requester (це й далі дозволено —
--    так і має бути), а тоді сам собі підтверджує його як 'accepted' без
--    жодної згоди адресата — і одразу отримує читання чужого щоденника
--    через checkins_select_friends. Коментар над самою політикою вже й
--    тоді описував намір "прийняти може лише адресат" — просто with
--    check ніколи фактично цього не забезпечував.
--
-- 2) checkin_comments_update / subject_checkin_comments_update
--    перевіряли лише author_id — легітимний коментар (залишений під
--    днем, який юзер чесно вгадав) можна ПОТІМ перенести на чужий
--    checkin_id через прямий UPDATE, і він з'явиться в приватному треді,
--    до якого юзер ніколи не мав доступу. Insert-політики вже мають
--    can_comment_on_checkin/can_comment_on_subject_checkin — update
--    просто ніколи не звіряв те саме після зміни checkin_id.
--
-- 3) future_letters має ТРИ окремі UPDATE-політики (soft-delete/opened/
--    recipient_seen), а Postgres об'єднує кілька permissive-політик через
--    OR НА РІВНІ РЯДКА, не колонки — досить пройти НАЙСЛАБШУ з трьох
--    (soft-delete, узагалі без перевірки unlock_at), щоб отримати право
--    змінити БУДЬ-ЯКУ колонку рядка, включно з unlock_at. Отримувач
--    листа міг сам собі поставити unlock_at у минуле і прочитати
--    запечатаний текст задовго до дати — сама суть "капсули часу"
--    ламається. Автор так само міг переставити recipient_id на будь-кого,
--    минаючи перевірку дружби, яку insert-політика робить лише при
--    створенні. Фікс через колонкові GRANT, не ще одну RLS-політику —
--    єдиний спосіб реально обмежити update, коли кілька permissive-
--    політик уже об'єднані через OR.
--
-- 4) avatars_update (Storage) мала using, але не мала with check — юзер
--    міг ПЕРЕЙМЕНУВАТИ власний файл аватарки на шлях {чужий_id}/avatar.jpg,
--    зайнявши чи перезаписавши слот іншого юзера, що ще не завантажив
--    свою аватарку.

-- 1. friendships_update: лише адресат (за email з JWT) може міняти статус
-- запиту (прийняти/відхилити). Requester і далі може оновлювати СВІЙ
-- рядок, доки статус лишається 'pending', але вже не може сам собі
-- підтвердити дружбу.
drop policy if exists "friendships_update" on public.friendships;
create policy "friendships_update"
on public.friendships for update
using (addressee_email = auth.jwt() ->> 'email' or requester_id = auth.uid())
with check (
  addressee_email = auth.jwt() ->> 'email'
  or (requester_id = auth.uid() and status = 'pending')
);

-- 2. checkin_comments_update / subject_checkin_comments_update:
-- перевіряємо той самий гейт доступу, що вже є на insert, ЗАНОВО проти
-- (можливо зміненого) checkin_id/subject_checkin_id — інакше автор може
-- "перенести" вже існуючий свій коментар у чужий приватний тред.
drop policy if exists "checkin_comments_update" on public.checkin_comments;
create policy "checkin_comments_update"
on public.checkin_comments for update
using (author_id = auth.uid())
with check (author_id = auth.uid() and public.can_comment_on_checkin(checkin_id));

drop policy if exists "subject_checkin_comments_update" on public.subject_checkin_comments;
create policy "subject_checkin_comments_update"
on public.subject_checkin_comments for update
using (author_id = auth.uid())
with check (
  author_id = auth.uid()
  and public.can_comment_on_subject_checkin(subject_checkin_id)
);

-- 3. future_letters: колонковий GRANT замість ще однієї RLS-політики.
-- Юзер і далі може позначати листи прочитаними/побаченими/видаленими зі
-- свого боку (саме ці 5 колонок і пише застосунок, звірено з
-- lib/time_capsules_screen.dart) — але вже фізично не може навіть
-- спробувати змінити unlock_at, author_id чи recipient_id через прямий
-- REST UPDATE, незалежно від того, яка з трьох row-політик спрацювала.
revoke update on public.future_letters from authenticated;
grant update (
  author_deleted_at,
  recipient_deleted_at,
  author_opened_at,
  recipient_opened_at,
  recipient_seen_at
) on public.future_letters to authenticated;

-- 4. avatars_update (Storage): with check дзеркалить using — файл можна
-- переміщати/оновлювати лише В МЕЖАХ власної теки, не лише читати ЗВІДКИ
-- береться вихідний об'єкт.
drop policy if exists "avatars_update" on storage.objects;
create policy "avatars_update"
on storage.objects for update
using (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = auth.uid()::text
)
with check (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = auth.uid()::text
);
