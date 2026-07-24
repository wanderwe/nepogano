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

-- керує лише власник (і сутність, і коло мають належати йому)
drop policy if exists "subject_folder_shares_owner_all" on public.subject_folder_shares;
create policy "subject_folder_shares_owner_all"
on public.subject_folder_shares for all
using (
  exists (select 1 from public.subjects s where s.id = subject_id and s.owner_id = auth.uid())
  and exists (select 1 from public.friend_folders f where f.id = folder_id and f.owner_id = auth.uid())
)
with check (
  exists (select 1 from public.subjects s where s.id = subject_id and s.owner_id = auth.uid())
  and exists (select 1 from public.friend_folders f where f.id = folder_id and f.owner_id = auth.uid())
);

-- учасник кола має бачити, що йому щось відкрили
drop policy if exists "subject_folder_shares_select_member" on public.subject_folder_shares;
create policy "subject_folder_shares_select_member"
on public.subject_folder_shares for select
using (
  exists (
    select 1 from public.friend_folder_members ffm
    where ffm.folder_id = subject_folder_shares.folder_id
      and ffm.friend_user_id = auth.uid()
  )
);

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
using (
  exists (
    select 1 from public.subject_folder_shares sfs
    join public.friend_folder_members ffm on ffm.folder_id = sfs.folder_id
    where sfs.subject_id = subjects.id and ffm.friend_user_id = auth.uid()
  )
);

drop policy if exists "subject_checkins_select_shared" on public.subject_checkins;
create policy "subject_checkins_select_shared"
on public.subject_checkins for select
using (
  exists (
    select 1 from public.subject_folder_shares sfs
    join public.friend_folder_members ffm on ffm.folder_id = sfs.folder_id
    where sfs.subject_id = subject_checkins.subject_id and ffm.friend_user_id = auth.uid()
  )
);
