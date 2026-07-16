-- Запусти це один раз у Supabase Dashboard → SQL Editor.
-- Додає: кола близьких (взаємне запрошення/приєднання), видимість чек-інів
-- членів кола (тільки настрій, без нотаток), і механіку "здогадайся".

create table public.circles (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  owner_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table public.circle_members (
  id uuid primary key default gen_random_uuid(),
  circle_id uuid not null references public.circles(id) on delete cascade,
  user_id uuid references auth.users(id) on delete cascade,
  invited_email text not null,
  status text not null default 'invited' check (status in ('invited', 'accepted')),
  created_at timestamptz not null default now(),
  unique (circle_id, invited_email)
);

create table public.circle_guesses (
  id uuid primary key default gen_random_uuid(),
  guesser_id uuid not null references auth.users(id) on delete cascade,
  target_user_id uuid not null references auth.users(id) on delete cascade,
  target_date date not null,
  guessed_mood text not null check (guessed_mood in ('niyak', 'nepogano', 'zbs')),
  correct boolean not null,
  created_at timestamptz not null default now(),
  unique (guesser_id, target_user_id, target_date)
);

alter table public.circles enable row level security;
alter table public.circle_members enable row level security;
alter table public.circle_guesses enable row level security;

-- security definer helpers: обходять RLS зсередини, щоб політики circles/circle_members
-- не запитували одна одну (і circle_members не запитувала саму себе) напряму —
-- інакше Postgres кидає "infinite recursion detected in policy" (42P17).
create or replace function public.is_circle_member(target_circle_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.circle_members
    where circle_id = target_circle_id
      and user_id = auth.uid()
      and status = 'accepted'
  );
$$;

create or replace function public.is_circle_owner(target_circle_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.circles
    where id = target_circle_id and owner_id = auth.uid()
  );
$$;

create or replace function public.is_circle_invitee(target_circle_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.circle_members
    where circle_id = target_circle_id and invited_email = auth.jwt() ->> 'email'
  );
$$;

-- circles: власник, прийнятий член, або запрошений (щоб бачити назву кола ще до прийняття)
create policy "circles_select"
on public.circles for select
using (
  owner_id = auth.uid()
  or public.is_circle_member(id)
  or public.is_circle_invitee(id)
);

create policy "circles_insert"
on public.circles for insert
with check (owner_id = auth.uid());

-- circle_members: власник кола, сам член, або запрошений (за email з JWT) бачить рядок
create policy "circle_members_select"
on public.circle_members for select
using (
  user_id = auth.uid()
  or invited_email = auth.jwt() ->> 'email'
  or public.is_circle_owner(circle_id)
  or public.is_circle_member(circle_id)
);

-- запрошувати може тільки власник кола
create policy "circle_members_insert"
on public.circle_members for insert
with check (public.is_circle_owner(circle_id));

-- прийняти запрошення може тільки сам запрошений (за email з JWT), або власник видаляє/оновлює
create policy "circle_members_update"
on public.circle_members for update
using (invited_email = auth.jwt() ->> 'email' or public.is_circle_owner(circle_id))
with check (invited_email = auth.jwt() ->> 'email' or public.is_circle_owner(circle_id));

-- відкликати запрошення / видалити себе з кола може власник кола, або сам член (вийти)
create policy "circle_members_delete"
on public.circle_members for delete
using (public.is_circle_owner(circle_id) or user_id = auth.uid());

-- checkins: додатковий permissive SELECT-policy — видно чек-іни (настрій і нотатку)
-- прийнятих спільних членів кола. Нотатка навмисно ховається в UI до моменту,
-- поки юзер не здогадається настрій — після цього доступна через "Показати деталі".
create policy "checkins_select_circle_mates"
on public.checkins for select
using (
  user_id in (
    select cm2.user_id
    from public.circle_members cm1
    join public.circle_members cm2 on cm1.circle_id = cm2.circle_id
    where cm1.user_id = auth.uid() and cm1.status = 'accepted'
      and cm2.status = 'accepted'
  )
);

-- circle_guesses: юзер бачить і створює тільки власні здогадки
create policy "circle_guesses_select"
on public.circle_guesses for select
using (guesser_id = auth.uid());

create policy "circle_guesses_insert"
on public.circle_guesses for insert
with check (guesser_id = auth.uid());
