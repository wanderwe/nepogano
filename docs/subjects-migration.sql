-- Запусти це один раз у Supabase Dashboard → SQL Editor.
-- Додає "сутності" — окремі щоденники дитини/улюбленця/іншого, які веде
-- власник акаунту тим самим ритуалом чек-іну, що й для себе. Повністю
-- приватно: жодної видимості друзям чи колам, ніякого спільного доступу —
-- тому RLS тут простіша, ніж у friendships (є лише одна сторона — власник).

create table public.subjects (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  kind text not null check (kind in ('child', 'pet', 'other')),
  name text not null,
  created_at timestamptz not null default now()
);

create table public.subject_checkins (
  id uuid primary key default gen_random_uuid(),
  subject_id uuid not null references public.subjects(id) on delete cascade,
  mood text not null check (mood in ('niyak', 'nepogano', 'zbs')),
  note text,
  photo_path text,
  photo_align_y double precision not null default 0,
  created_at timestamptz not null default now()
);

alter table public.subjects enable row level security;
alter table public.subject_checkins enable row level security;

create policy "subjects_all"
on public.subjects for all
using (owner_id = auth.uid())
with check (owner_id = auth.uid());

create policy "subject_checkins_all"
on public.subject_checkins for all
using (
  exists (
    select 1 from public.subjects s
    where s.id = subject_id and s.owner_id = auth.uid()
  )
)
with check (
  exists (
    select 1 from public.subjects s
    where s.id = subject_id and s.owner_id = auth.uid()
  )
);

-- Фото сутностей не потребують окремого бакета чи політики: uploadCheckinPhoto
-- будує шлях від auth.uid() власника незалежно від того, чий це чек-ін, тож
-- вони й так підпадають під наявні checkin-photos + її RLS.

-- delete_own_account: додати очищення сутностей (каскадом прибирає
-- subject_checkins; фото й так покриті наявним видаленням по папці власника).
create or replace function public.delete_own_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from storage.objects
  where bucket_id = 'checkin-photos'
    and (storage.foldername(name))[1] = auth.uid()::text;

  delete from public.checkins where user_id = auth.uid();
  delete from public.subjects where owner_id = auth.uid();
  delete from public.friendships
  where requester_id = auth.uid() or addressee_id = auth.uid();
  delete from public.friend_folders where owner_id = auth.uid();
  delete from public.profiles where user_id = auth.uid();
  delete from auth.users where id = auth.uid();
end;
$$;
