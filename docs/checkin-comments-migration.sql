-- Запусти це один раз у Supabase Dashboard → SQL Editor. Безпечно запускати
-- повторно (create table if not exists + drop policy if exists скрізь).
-- Коментарі під конкретним днем реальної людини — продовження гри-вгадування,
-- тому та сама межа приватності: власник дня бачить і коментує завжди, друг —
-- тільки після того, як уже вгадав саме цей день (той самий принцип, що
-- ховає настрій/нотатку в UI до вгадування). Свідомо НЕ для subject_checkins —
-- сутності не підключені до вгадування (ARCHITECTURE.md, правило №3), тож і
-- коментарі, які є продовженням цієї гри, туди не йдуть.

create table if not exists public.checkin_comments (
  id uuid primary key default gen_random_uuid(),
  checkin_id uuid not null references public.checkins(id) on delete cascade,
  author_id uuid not null references auth.users(id) on delete cascade,
  parent_id uuid references public.checkin_comments(id) on delete cascade,
  body text not null,
  created_at timestamptz not null default now(),
  edited_at timestamptz,
  deleted_at timestamptz
);

alter table public.checkin_comments enable row level security;

-- Один хелпер на SELECT і INSERT: власник дня — завжди; друг — тільки якщо
-- вже вгадував саме цей день. security definer, щоб не чіпляти окрему
-- select-політику на circle_guesses/checkins зсередини цієї ж політики.
create or replace function public.can_comment_on_checkin(target_checkin_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.checkins c
    where c.id = target_checkin_id
      and (
        c.user_id = auth.uid()
        or exists (
          select 1 from public.circle_guesses g
          where g.guesser_id = auth.uid()
            and g.target_user_id = c.user_id
            and g.target_date = c.created_at::date
        )
      )
  );
$$;

drop policy if exists "checkin_comments_select" on public.checkin_comments;
create policy "checkin_comments_select"
on public.checkin_comments for select
using (public.can_comment_on_checkin(checkin_id));

drop policy if exists "checkin_comments_insert" on public.checkin_comments;
create policy "checkin_comments_insert"
on public.checkin_comments for insert
with check (author_id = auth.uid() and public.can_comment_on_checkin(checkin_id));

-- Редагування і "видалення" (насправді soft-delete через deleted_at на
-- клієнті, щоб не ламати структуру відповідей під видаленим коментарем) —
-- тільки автор.
drop policy if exists "checkin_comments_update" on public.checkin_comments;
create policy "checkin_comments_update"
on public.checkin_comments for update
using (author_id = auth.uid())
with check (author_id = auth.uid());

-- delete_own_account() явних правок не потребує: checkin_id/author_id мають
-- on delete cascade, рядки приберуться самі, коли функція видаляє checkins
-- цього юзера і зрештою сам рядок auth.users.
