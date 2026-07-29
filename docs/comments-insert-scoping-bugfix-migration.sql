-- Запусти це один раз у Supabase Dashboard → SQL Editor. Безпечно запускати
-- повторно.
--
-- РЕАЛЬНИЙ баг, знайдений через прямий запит до pg_policies (не здогад):
-- усередині EXISTS-підзапиту політики *_insert неквалiфіковані parent_id/
-- checkin_id (і subject_checkin_id) мали посилатись на НОВИЙ рядок, що
-- вставляється, — але підзапит сам обирає з тієї самої таблиці під
-- псевдонімом p, тож Postgres резолвив ці імена до p.parent_id/p.checkin_id
-- (найближча область видимості), а не до зовнішнього рядка. Через це:
--   - `p.checkin_id = checkin_id` ставало `p.checkin_id = p.checkin_id`
--     (тавтологія, завжди true, не перевіряла належність до того самого дня);
--   - `p.id = parent_id` ставало `p.id = p.parent_id`, що для кореневого
--     коментаря (p.parent_id IS NULL) ніколи не true.
-- Наслідок: EXISTS завжди повертав false, і ЖОДНА відповідь ніколи не
-- проходила RLS — не тільки зараз, а відколи ця модель вперше з'явилась
-- (checkin-comments-simplify-migration.sql / subject-guessing-comments-migration.sql).
-- Перевірено буквальним текстом деплойнутої політики через
-- `select with_check from pg_policies where policyname = 'checkin_comments_insert'`.
--
-- Фікс: явно кваліфікувати посилання на зовнішній (новий) рядок іменем
-- таблиці без псевдоніма — усередині підзапиту це лишається однозначним,
-- бо підзапит використовує ІНШИЙ псевдонім (p).

drop policy if exists "checkin_comments_insert" on public.checkin_comments;
create policy "checkin_comments_insert"
on public.checkin_comments for insert
with check (
  author_id = auth.uid()
  and public.can_comment_on_checkin(checkin_id)
  and (
    parent_id is null
    or exists (
      select 1 from public.checkin_comments p
      where p.id = checkin_comments.parent_id
        and p.checkin_id = checkin_comments.checkin_id
        and p.parent_id is null
        and p.author_id <> auth.uid()
    )
  )
);

drop policy if exists "subject_checkin_comments_insert" on public.subject_checkin_comments;
create policy "subject_checkin_comments_insert"
on public.subject_checkin_comments for insert
with check (
  author_id = auth.uid()
  and public.can_comment_on_subject_checkin(subject_checkin_id)
  and (
    parent_id is null
    or exists (
      select 1 from public.subject_checkin_comments p
      where p.id = subject_checkin_comments.parent_id
        and p.subject_checkin_id = subject_checkin_comments.subject_checkin_id
        and p.parent_id is null
        and p.author_id <> auth.uid()
    )
  )
);
