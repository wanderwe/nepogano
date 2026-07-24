-- Запусти це один раз у Supabase Dashboard → SQL Editor. Безпечно запускати
-- повторно (create table if not exists + drop policy if exists скрізь).
-- Дозволяє власнику сутності (дитина/улюбленець) відкрити її щоденник на
-- ПЕРЕГЛЯД (без гри-вгадування) конкретному колу — тій самій таблиці
-- friend_folders, яку користувач уже бачить в застосунку як "коло". Нового
-- поняття кола/папки тут не з'являється, лише зв'язок "щоденник ↔ коло".

create table if not exists public.subject_folder_shares (
  subject_id uuid not null references public.subjects(id) on delete cascade,
  folder_id uuid not null references public.friend_folders(id) on delete cascade,
  primary key (subject_id, folder_id)
);

alter table public.subject_folder_shares enable row level security;

-- security definer helpers: обходять RLS зсередини, щоб політики
-- subjects/subject_folder_shares/friend_folder_members не запитували одна
-- одну напряму — інакше Postgres кидає "infinite recursion detected in
-- policy" (42P17), той самий гачок, що вже був із circles/circle_members.
create or replace function public.owns_subject(target_subject_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.subjects s
    where s.id = target_subject_id and s.owner_id = auth.uid()
  );
$$;

create or replace function public.owns_folder(target_folder_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.friend_folders f
    where f.id = target_folder_id and f.owner_id = auth.uid()
  );
$$;

create or replace function public.is_folder_member(target_folder_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.friend_folder_members ffm
    where ffm.folder_id = target_folder_id and ffm.friend_user_id = auth.uid()
  );
$$;

create or replace function public.subject_shared_with_me(target_subject_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.subject_folder_shares sfs
    where sfs.subject_id = target_subject_id
      and public.is_folder_member(sfs.folder_id)
  );
$$;

-- керує лише власник (і сутність, і коло мають належати йому)
drop policy if exists "subject_folder_shares_owner_all" on public.subject_folder_shares;
create policy "subject_folder_shares_owner_all"
on public.subject_folder_shares for all
using (public.owns_subject(subject_id) and public.owns_folder(folder_id))
with check (public.owns_subject(subject_id) and public.owns_folder(folder_id));

-- учасник кола має бачити, що йому щось відкрили
drop policy if exists "subject_folder_shares_select_member" on public.subject_folder_shares;
create policy "subject_folder_shares_select_member"
on public.subject_folder_shares for select
using (public.is_folder_member(folder_id));

-- прогалина, яку це виявило: учасник кола досі не міг побачити навіть факт
-- свого членства (єдина наявна політика на friend_folder_members пускала
-- тільки власника кола) — без цього він не дізнається, в яких колах він є,
-- і секція "Спільні щоденники" не змогла б порахувати доступні їй sharing-рядки.
drop policy if exists "friend_folder_members_select_self" on public.friend_folder_members;
create policy "friend_folder_members_select_self"
on public.friend_folder_members for select
using (friend_user_id = auth.uid());

-- read-only доступ до самої сутності й до її чек-інів для учасників кіл,
-- яким власник щось відкрив. Адитивно поруч із наявними "for all" (власник),
-- нічого не забирає.
drop policy if exists "subjects_select_shared" on public.subjects;
create policy "subjects_select_shared"
on public.subjects for select
using (public.subject_shared_with_me(subjects.id));

drop policy if exists "subject_checkins_select_shared" on public.subject_checkins;
create policy "subject_checkins_select_shared"
on public.subject_checkins for select
using (public.subject_shared_with_me(subject_checkins.subject_id));
