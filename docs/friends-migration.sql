-- Запусти це один раз у Supabase Dashboard → SQL Editor.
-- Замінює модель "кола" (спільний контейнер із транзитивною видимістю) на
-- симетричну дружбу (парна видимість) + приватні особисті папки для
-- сортування. Причина: тестування показало, що коли друг додає у СВОЄ коло
-- інших людей, я теж бачу і вгадую їхній настрій, хоч я їх не додавав і
-- можу навіть не знати. Старі таблиці circles/circle_members СВІДОМО не
-- видаляються цією міграцією (закрите тестування вже почалось) — лишаються
-- в БД невикористаними, приберемо окремо пізніше.

-- profiles: персональний код для додавання в друзі (аналог invite_code
-- у circles, тільки на людину, не на коло).
create table public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  friend_code text not null unique default substr(md5(random()::text), 1, 8)
);

alter table public.profiles enable row level security;

create policy "profiles_select_own"
on public.profiles for select
using (user_id = auth.uid());

create policy "profiles_insert_own"
on public.profiles for insert
with check (user_id = auth.uid());

-- backfill для вже існуючих акаунтів
insert into public.profiles (user_id)
select id from auth.users
on conflict (user_id) do nothing;

-- автостворення профілю для нових реєстрацій
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (user_id) values (new.id) on conflict do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

-- friendships: одна пара = один рядок. Видимість парна, обчислюється по
-- обох напрямках (requester_id = я АБО addressee_id = я), без спільного
-- контейнера — саме це прибирає витік до незнайомців. Email обох сторін
-- зберігається прямо в рядку (requester_email/addressee_email), бо
-- auth.users недоступна клієнту напряму — інакше адресат не зміг би
-- дізнатись email того, хто його додав.
create table public.friendships (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references auth.users(id) on delete cascade,
  requester_email text not null,
  addressee_id uuid references auth.users(id) on delete cascade,
  addressee_email text not null,
  status text not null default 'pending' check (status in ('pending', 'accepted')),
  created_at timestamptz not null default now(),
  unique (requester_id, addressee_email)
);

alter table public.friendships enable row level security;

create policy "friendships_select"
on public.friendships for select
using (
  requester_id = auth.uid()
  or addressee_id = auth.uid()
  or addressee_email = auth.jwt() ->> 'email'
);

create policy "friendships_insert"
on public.friendships for insert
with check (requester_id = auth.uid());

-- прийняти запрошення може сам запрошений (за email з JWT), або вже сам
-- requester через RPC (add_friend_by_code підтверджує зустрічний запит)
create policy "friendships_update"
on public.friendships for update
using (addressee_email = auth.jwt() ->> 'email' or requester_id = auth.uid())
with check (addressee_email = auth.jwt() ->> 'email' or requester_id = auth.uid());

-- видалити з друзів може будь-яка сторона пари
create policy "friendships_delete"
on public.friendships for delete
using (requester_id = auth.uid() or addressee_id = auth.uid());

-- додавання за особистим кодом: одразу 'accepted' в обидва боки (поділився
-- кодом = дав згоду, той самий принцип, що join_circle_by_code). Якщо вже
-- є вхідний pending-запит від цієї людини (email-інвайт раніше) — просто
-- підтверджує його замість дубліката.
create or replace function public.add_friend_by_code(code text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  target_user_id uuid;
  my_id uuid := auth.uid();
  my_email text := auth.jwt() ->> 'email';
  target_email text;
  reverse_id uuid;
  new_id uuid;
begin
  select user_id into target_user_id
  from public.profiles
  where friend_code = lower(trim(code));

  if target_user_id is null then
    raise exception 'invalid_code';
  end if;

  if target_user_id = my_id then
    raise exception 'cannot_add_self';
  end if;

  select email into target_email from auth.users where id = target_user_id;

  select id into reverse_id
  from public.friendships
  where requester_id = target_user_id and addressee_email = my_email;

  if reverse_id is not null then
    update public.friendships
    set status = 'accepted', addressee_id = my_id
    where id = reverse_id;
    return reverse_id;
  end if;

  insert into public.friendships (requester_id, requester_email, addressee_id, addressee_email, status)
  values (my_id, my_email, target_user_id, target_email, 'accepted')
  on conflict (requester_id, addressee_email)
  do update set status = 'accepted', addressee_id = excluded.addressee_id
  returning id into new_id;

  return new_id;
end;
$$;

grant execute on function public.add_friend_by_code(text) to authenticated;

-- friend_folders / friend_folder_members: суто приватне групування, без
-- прав запрошення і без спільного членства — друг ніколи не бачить чужі
-- папки, це лише персональний фільтр перегляду власника.
create table public.friend_folders (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  created_at timestamptz not null default now()
);

create table public.friend_folder_members (
  folder_id uuid not null references public.friend_folders(id) on delete cascade,
  friend_user_id uuid not null references auth.users(id) on delete cascade,
  primary key (folder_id, friend_user_id)
);

alter table public.friend_folders enable row level security;
alter table public.friend_folder_members enable row level security;

create policy "friend_folders_all"
on public.friend_folders for all
using (owner_id = auth.uid())
with check (owner_id = auth.uid());

create policy "friend_folder_members_all"
on public.friend_folder_members for all
using (
  exists (
    select 1 from public.friend_folders f
    where f.id = folder_id and f.owner_id = auth.uid()
  )
)
with check (
  exists (
    select 1 from public.friend_folders f
    where f.id = folder_id and f.owner_id = auth.uid()
  )
);

-- checkins: заміна витікаючої політики circle-видимості на парну
-- friends-видимість. Це єдина частина міграції, що змінює поведінку для
-- будь-кого, хто зараз реально користується колами — свідомо, бо це і є
-- витік приватності, який весь цей редизайн покликаний закрити.
drop policy if exists "checkins_select_circle_mates" on public.checkins;

create policy "checkins_select_friends"
on public.checkins for select
using (
  user_id in (
    select addressee_id from public.friendships
    where requester_id = auth.uid() and status = 'accepted' and addressee_id is not null
    union
    select requester_id from public.friendships
    where addressee_id = auth.uid() and status = 'accepted'
  )
);

-- circle_guesses лишається без змін — таблиця й так оперує парою
-- (guesser_id, target_user_id) напряму, ніколи не посилалась на коло.

-- delete_own_account: додати очищення нових таблиць. Старі circle_members/
-- circles рядки ця функція й зараз не чіпає — не чіпаємо і ми.
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
  delete from public.friendships
  where requester_id = auth.uid() or addressee_id = auth.uid();
  delete from public.friend_folders where owner_id = auth.uid();
  delete from public.profiles where user_id = auth.uid();
  delete from auth.users where id = auth.uid();
end;
$$;
