-- Запусти це один раз у Supabase Dashboard → SQL Editor. Безпечно запускати
-- повторно.
--
-- "Поштовх" — друг дає знати, що йому не байдуже, що давно не було записів.
-- Свідомо НЕ push-сповіщення (немає такої інфраструктури, і уникали цього
-- свідомо) — юзер бачить це пасивно, коли сам наступного разу відкриє
-- застосунок (той самий принцип, що hasUnseenComments/hasUnseenFriendActivity).
-- Rate-limit "раз на тиждень на пару друзів" — свідомо на клієнті, не в БД
-- (той самий підхід, що й до інших м'яких обмежень у цьому застосунку),
-- клієнт перевіряє власні nudges за останні 7 днів перед показом кнопки.

create table if not exists public.friend_nudges (
  id uuid primary key default gen_random_uuid(),
  from_user_id uuid not null references auth.users(id) on delete cascade,
  to_user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

alter table public.friend_nudges enable row level security;

-- надіслати можна лише прямому другу (той самий парний friendships-принцип,
-- що скрізь у застосунку)
drop policy if exists "friend_nudges_insert" on public.friend_nudges;
create policy "friend_nudges_insert"
on public.friend_nudges for insert
with check (
  from_user_id = auth.uid()
  and exists (
    select 1 from public.friendships f
    where f.status = 'accepted'
      and (
        (f.requester_id = auth.uid() and f.addressee_id = to_user_id)
        or (f.addressee_id = auth.uid() and f.requester_id = to_user_id)
      )
  )
);

-- отримувач бачить вхідні поштовхи (для банера на головному екрані)
drop policy if exists "friend_nudges_select_received" on public.friend_nudges;
create policy "friend_nudges_select_received"
on public.friend_nudges for select
using (to_user_id = auth.uid());

-- відправник бачить власні надіслані (клієнту потрібно для перевірки
-- rate-limit "раз на тиждень" перед показом кнопки)
drop policy if exists "friend_nudges_select_sent" on public.friend_nudges;
create policy "friend_nudges_select_sent"
on public.friend_nudges for select
using (from_user_id = auth.uid());
