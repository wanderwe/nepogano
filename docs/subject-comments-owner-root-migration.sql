-- Запусти це один раз у Supabase Dashboard → SQL Editor. Безпечно запускати
-- повторно. ВАЖЛИВО: виконуй ПІСЛЯ subject-guessing-comments-migration.sql.
--
-- Продуктове рішення (обговорено з користувачем): на відміну від коментарів
-- реальних людей (де день і так має нотатку від самого власника, тож
-- власник лише відповідає), у щоденнику сутності власник/співавтор часто
-- пише ЗАМІСТЬ дитини/улюбленця — і має так само природно хотіти лишити
-- власний кореневий коментар, не тільки відповідати комусь. Тому для
-- subject_checkin_comments знімаємо асиметрію "власник — тільки відповідь,
-- глядач — тільки корінь": тепер будь-хто, кому можна коментувати
-- (can_comment_on_subject_checkin), може лишити і корінь, і відповідь —
-- обмеження лишається тільки "максимум одна відповідь на коментар" (уже є,
-- subject_checkin_comments_parent_unique) і "не відповідати самому собі".
-- Коментарів реальних людей (checkin_comments) це не стосується — там
-- асиметрія лишається як є.

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
      where p.id = parent_id
        and p.subject_checkin_id = subject_checkin_id
        and p.parent_id is null
        and p.author_id <> auth.uid()
    )
  )
);
