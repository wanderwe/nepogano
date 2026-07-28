-- Запусти це один раз у Supabase Dashboard → SQL Editor.
-- ВАЖЛИВО: виконуй ПІСЛЯ subject-coauthors-migration.sql.
--
-- Дозволяє співавтору самому прибрати себе зі списку співавторів ("вийти").
-- Раніше цим міг керувати лише власник (subject_coauthors_owner_all) — тобто
-- щоденник, доданий власником, назавжди лишався б у перемикача сутностей
-- співавтора без жодної можливості його прибрати. Реальна прогалина,
-- знайдена одразу після живого тестування.

drop policy if exists "subject_coauthors_delete_self" on public.subject_coauthors;
create policy "subject_coauthors_delete_self"
on public.subject_coauthors for delete
using (coauthor_user_id = auth.uid());
