-- Запусти це один раз у Supabase Dashboard → SQL Editor. Безпечно запускати
-- повторно (create table if not exists + drop policy if exists скрізь).
-- ВАЖЛИВО: виконуй ПІСЛЯ subject-sharing-migration.sql і
-- subject-coauthors-migration.sql — використовує owns_subject/is_subject_coauthor.
--
-- Продуктове рішення (обговорено з користувачем, скасовує стару заборону з
-- ARCHITECTURE.md правило №3): гра-вгадування і коментарі поширюються й на
-- щоденники сутностей — той самий принцип, що для реальних людей:
--   - учасник кола, якому відкрито щоденник (subject_folder_shares), спершу
--     вгадує настрій дня, тоді може лишити (кореневий) коментар;
--   - власник і співавтори сутності — як "власник дня" в моделі реальних
--     людей: вгадувати не треба (вони й так бачать усе одразу), можуть лише
--     ВІДПОВІСТИ на кореневий коментар глядача, максимум раз на коментар.
-- RLS на subject_checkins не змінюється: учасник кола й так має повний
-- read-доступ через subject_checkins_select_shared (той самий принцип, що
-- checkins_select_friends — приховування настрою до вгадування ніколи не
-- було обмеженням на рівні даних, лише клієнтський UI-ритуал).

create table if not exists public.subject_guesses (
  id uuid primary key default gen_random_uuid(),
  guesser_id uuid not null references auth.users(id) on delete cascade,
  subject_id uuid not null references public.subjects(id) on delete cascade,
  target_date date not null,
  guessed_mood text not null check (guessed_mood in ('niyak', 'nepogano', 'zbs')),
  correct boolean not null,
  created_at timestamptz not null default now(),
  unique (guesser_id, subject_id, target_date)
);

alter table public.subject_guesses enable row level security;

drop policy if exists "subject_guesses_select" on public.subject_guesses;
create policy "subject_guesses_select"
on public.subject_guesses for select
using (guesser_id = auth.uid());

-- вгадувати може лише той, кому справді відкрито щоденник цієї сутності
drop policy if exists "subject_guesses_insert" on public.subject_guesses;
create policy "subject_guesses_insert"
on public.subject_guesses for insert
with check (guesser_id = auth.uid() and public.subject_shared_with_me(subject_id));

-- Власник або співавтор — одна перевірка, обидва мають однакові права на
-- відповіді в коментарях (на відміну від решти дій, де лишається лише owner).
create or replace function public.owns_or_coauthors_subject_checkin(target_subject_checkin_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.subject_checkins sc
    where sc.id = target_subject_checkin_id
      and (public.owns_subject(sc.subject_id) or public.is_subject_coauthor(sc.subject_id))
  );
$$;

create or replace function public.can_comment_on_subject_checkin(target_subject_checkin_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select public.owns_or_coauthors_subject_checkin(target_subject_checkin_id)
    or exists (
      select 1 from public.subject_checkins sc
      join public.subject_guesses g
        on g.subject_id = sc.subject_id and g.target_date = sc.created_at::date
      where sc.id = target_subject_checkin_id and g.guesser_id = auth.uid()
    );
$$;

create table if not exists public.subject_checkin_comments (
  id uuid primary key default gen_random_uuid(),
  subject_checkin_id uuid not null references public.subject_checkins(id) on delete cascade,
  author_id uuid not null references auth.users(id) on delete cascade,
  parent_id uuid references public.subject_checkin_comments(id) on delete cascade,
  body text not null,
  created_at timestamptz not null default now(),
  edited_at timestamptz,
  deleted_at timestamptz
);

alter table public.subject_checkin_comments enable row level security;

-- Та сама межа "максимум одна відповідь", що checkin_comments_parent_unique
-- (checkin-comments-simplify-migration.sql) — узгоджена спрощена модель.
create unique index if not exists subject_checkin_comments_parent_unique
on public.subject_checkin_comments (parent_id)
where parent_id is not null;

drop policy if exists "subject_checkin_comments_select" on public.subject_checkin_comments;
create policy "subject_checkin_comments_select"
on public.subject_checkin_comments for select
using (public.can_comment_on_subject_checkin(subject_checkin_id));

drop policy if exists "subject_checkin_comments_insert" on public.subject_checkin_comments;
create policy "subject_checkin_comments_insert"
on public.subject_checkin_comments for insert
with check (
  author_id = auth.uid()
  and public.can_comment_on_subject_checkin(subject_checkin_id)
  and (
    (
      -- Власник/співавтор: лише відповідь на чужий кореневий коментар.
      parent_id is not null
      and public.owns_or_coauthors_subject_checkin(subject_checkin_id)
      and exists (
        select 1 from public.subject_checkin_comments p
        where p.id = parent_id
          and p.subject_checkin_id = subject_checkin_id
          and p.parent_id is null
          and p.author_id <> auth.uid()
      )
    )
    or (
      -- Глядач кола: лише кореневий коментар, не відповідь.
      parent_id is null
      and not public.owns_or_coauthors_subject_checkin(subject_checkin_id)
    )
  )
);

drop policy if exists "subject_checkin_comments_update" on public.subject_checkin_comments;
create policy "subject_checkin_comments_update"
on public.subject_checkin_comments for update
using (author_id = auth.uid())
with check (author_id = auth.uid());

-- delete_own_account() явних правок не потребує: усі FK (subject_id/guesser_id/
-- author_id/subject_checkin_id) мають on delete cascade, рядки приберуться самі.
