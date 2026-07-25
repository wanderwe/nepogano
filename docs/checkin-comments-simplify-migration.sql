-- Запусти це один раз у Supabase Dashboard → SQL Editor (після
-- checkin-comments-migration.sql, яка вже виконана). Безпечно запускати
-- повторно.
--
-- Спрощення моделі коментарів: необмежена глибина відповідей на практиці
-- виглядає нечитабельно вже з 2-3 рівнями вкладеності. Нова модель:
--   - кореневий коментар лишає тільки друг (не власник дня);
--   - власник дня може відповісти на кожен кореневий коментар максимум
--     один раз — і все, без подальших відповідей на відповідь.

-- Гарантує максимум одну відповідь на будь-який коментар незалежно від
-- автора — той самий constraint заразом закриває "ланцюжок відповідей",
-- бо відповісти на вже наявну відповідь не вийде (parent_id для неї вже
-- зайнятий).
create unique index if not exists checkin_comments_parent_unique
on public.checkin_comments (parent_id)
where parent_id is not null;

-- Власник конкретного чек-іну — окремий хелпер, бо тепер потрібен і в
-- INSERT-політиці для розрізнення "друг" / "власник дня".
create or replace function public.owns_checkin(target_checkin_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.checkins c
    where c.id = target_checkin_id and c.user_id = auth.uid()
  );
$$;

drop policy if exists "checkin_comments_insert" on public.checkin_comments;
create policy "checkin_comments_insert"
on public.checkin_comments for insert
with check (
  author_id = auth.uid()
  and public.can_comment_on_checkin(checkin_id)
  and (
    (
      -- Власник дня: лише відповідь на чужий кореневий коментар.
      parent_id is not null
      and public.owns_checkin(checkin_id)
      and exists (
        select 1 from public.checkin_comments p
        where p.id = parent_id
          and p.checkin_id = checkin_id
          and p.parent_id is null
          and p.author_id <> auth.uid()
      )
    )
    or (
      -- Друг: лише кореневий коментар, не відповідь.
      parent_id is null
      and not public.owns_checkin(checkin_id)
    )
  )
);
