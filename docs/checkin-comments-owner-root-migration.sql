-- Запусти це один раз у Supabase Dashboard → SQL Editor. Безпечно запускати
-- повторно. ВАЖЛИВО: виконуй ПІСЛЯ checkin-comments-simplify-migration.sql.
--
-- Продуктове рішення (обговорено з користувачем, услід за тим самим
-- рішенням для subject_checkin_comments —
-- subject-comments-owner-root-migration.sql): якщо власник щоденника
-- сутності вже може лишати собі кореневий коментар, а не тільки
-- відповідати, то й на власному дні реальної людини це так само доречно —
-- не тільки друг, а й сам власник дня може лишити кореневий коментар
-- (напр. запізнілий допис-уточнення до вже збереженого дня), не тільки
-- відповідати на чужі. Знімаємо ту саму асиметрію "власник — лише
-- відповідь", яку `checkin-comments-simplify-migration.sql` свідомо
-- закладав — тепер обидві таблиці (`checkin_comments` і
-- `subject_checkin_comments`) працюють за однаковим симетричним правилом:
-- будь-хто, кому можна коментувати, лишає і корінь, і відповідь; єдине
-- спільне обмеження — максимум одна відповідь на коментар (уже є,
-- checkin_comments_parent_unique) і заборона відповідати самому собі.

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
      where p.id = parent_id
        and p.checkin_id = checkin_id
        and p.parent_id is null
        and p.author_id <> auth.uid()
    )
  )
);
