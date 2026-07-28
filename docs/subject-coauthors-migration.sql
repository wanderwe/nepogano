-- Запусти це один раз у Supabase Dashboard → SQL Editor. Безпечно запускати
-- повторно (create table if not exists + drop policy if exists скрізь).
-- ВАЖЛИВО: виконуй ПІСЛЯ subject-sharing-migration.sql — використовує ті самі
-- helper-функції (owns_subject).
--
-- Додає можливість власнику сутності (дитина/улюбленець) додати конкретних
-- друзів як СПІВАВТОРІВ щоденника — на відміну від subject_folder_shares
-- (перегляд усім колом), тут вужчий, свідомий список: лише обрані люди
-- можуть РЕДАГУВАТИ спільний чек-ін дня, решта кола (якщо є) й далі бачить
-- лише на перегляд. Один чек-ін на день лишається спільним записом — хто б
-- з співавторів не відкрив сьогоднішній день, він бачить і може оновити той
-- самий запис, а не створює власний паралельний.

create table if not exists public.subject_coauthors (
  subject_id uuid not null references public.subjects(id) on delete cascade,
  coauthor_user_id uuid not null references auth.users(id) on delete cascade,
  added_at timestamptz not null default now(),
  primary key (subject_id, coauthor_user_id)
);

alter table public.subject_coauthors enable row level security;

create or replace function public.is_subject_coauthor(target_subject_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.subject_coauthors sc
    where sc.subject_id = target_subject_id and sc.coauthor_user_id = auth.uid()
  );
$$;

-- керує лише власник сутності
drop policy if exists "subject_coauthors_owner_all" on public.subject_coauthors;
create policy "subject_coauthors_owner_all"
on public.subject_coauthors for all
using (public.owns_subject(subject_id))
with check (public.owns_subject(subject_id));

-- співавтор бачить факт свого додавання (і список інших співавторів поруч —
-- потрібно для атрибуції "хто ще веде цей щоденник")
drop policy if exists "subject_coauthors_select_coauthor" on public.subject_coauthors;
create policy "subject_coauthors_select_coauthor"
on public.subject_coauthors for select
using (public.is_subject_coauthor(subject_id));

-- співавтор бачить саму сутність — щоб вона з'явилась у перемикачі
-- щоденників на головному екрані, як і власні
drop policy if exists "subjects_select_coauthor" on public.subjects;
create policy "subjects_select_coauthor"
on public.subjects for select
using (public.is_subject_coauthor(subjects.id));

-- співавтор читає й пише чек-іни сутності — окремі політики поруч із
-- наявною subject_checkins_all (лише власник), нічого не забирають
drop policy if exists "subject_checkins_coauthor_select" on public.subject_checkins;
create policy "subject_checkins_coauthor_select"
on public.subject_checkins for select
using (public.is_subject_coauthor(subject_checkins.subject_id));

drop policy if exists "subject_checkins_coauthor_insert" on public.subject_checkins;
create policy "subject_checkins_coauthor_insert"
on public.subject_checkins for insert
with check (public.is_subject_coauthor(subject_checkins.subject_id));

drop policy if exists "subject_checkins_coauthor_update" on public.subject_checkins;
create policy "subject_checkins_coauthor_update"
on public.subject_checkins for update
using (public.is_subject_coauthor(subject_checkins.subject_id))
with check (public.is_subject_coauthor(subject_checkins.subject_id));

-- Атрибуція: хто написав/востаннє редагував конкретний запис. Nullable —
-- старі записи (до цієї фічі) лишаються без автора, UI просто не показує
-- підпис для них.
alter table public.subject_checkins add column if not exists author_id uuid references auth.users(id) on delete set null;
