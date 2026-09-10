-- Інформування ініціатора дружби про те, ХТО прийняв запрошення. Три
-- існуючі шляхи додавання в друзі (код, лінк-код, email-інвайт) лишаються
-- геть без змін — це лише пасивний шар "бачив/не бачив" над уже готовим
-- результатом 'accepted', без втручання в сам процес прийняття.
--
-- Модель: два прапорці-таймстемпи, по одному на кожну сторону пари. Той,
-- хто ВИКОНУЄ дію підтвердження (ввів код друга, чи натиснув "Прийняти"
-- на email-інвайт), одразу бачить результат сам — тож його прапорець
-- виставляється в момент підтвердження автоматично, без окремого кроку.
-- Інша сторона дізнається лише пізніше, з нової секції на сторінці
-- друзів — її прапорець лишається null, доки вона сама не гляне.
--
-- requester_seen_confirmed_at не можна виставити прямим UPDATE через RLS
-- (friendship-consent-security-fix/rls-followup вже звужили
-- friendships_update: requester може міняти свій рядок лише доки він
-- 'pending' — інакше це та сама діра самопідтвердження, яку ми щойно
-- закрили). Тому позначку "я побачив" для БУДЬ-ЯКОЇ сторони робить окрема
-- SECURITY DEFINER функція нижче — вона звіряє, що викликач і справді
-- requester_id чи addressee_id ЦЬОГО рядка, і торкається лише свого
-- власного прапорця, більше нічого в рядку.

alter table public.friendships
  add column if not exists requester_seen_confirmed_at timestamptz,
  add column if not exists addressee_seen_confirmed_at timestamptz;

-- Уже існуючі 'accepted' дружби зі старих версій застосунку: без цього
-- backfill'у обидві сторони кожної старої пари побачили б нову секцію
-- "прийняв дружбу" одноразовим спамом при першому відкритті сторінки
-- друзів після оновлення. Позначаємо їх як "уже бачені" з обох боків.
update public.friendships
set requester_seen_confirmed_at = now(), addressee_seen_confirmed_at = now()
where status = 'accepted'
  and requester_seen_confirmed_at is null
  and addressee_seen_confirmed_at is null;

-- add_friend_by_code сам є SECURITY DEFINER (обходить RLS) — тож може
-- напряму виставити прапорець сторони, яка щойно виконала дію, без
-- окремого дозволу.
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
    -- Я (той, хто вводить код) є addressee цього зустрічного рядка —
    -- я щойно підтвердив, тож саме мій прапорець ("addressee") стає
    -- побаченим; протилежна сторона (requester, автор коду) дізнається
    -- через нову секцію.
    update public.friendships
    set status = 'accepted', addressee_id = my_id, addressee_seen_confirmed_at = now()
    where id = reverse_id;
    return reverse_id;
  end if;

  -- Свіжий запис: я requester (ввів чужий код) — мій прапорець ("requester")
  -- стає побаченим одразу, власник коду (addressee) дізнається пізніше.
  insert into public.friendships (
    requester_id, requester_email, addressee_id, addressee_email, status,
    requester_seen_confirmed_at
  )
  values (my_id, my_email, target_user_id, target_email, 'accepted', now())
  on conflict (requester_id, addressee_email)
  do update set
    status = 'accepted',
    addressee_id = excluded.addressee_id,
    requester_seen_confirmed_at = now()
  returning id into new_id;

  return new_id;
end;
$$;

revoke execute on function public.add_friend_by_code(text) from public;
grant execute on function public.add_friend_by_code(text) to authenticated;

-- Позначити "я побачив, що дружбу прийняли" для рядка, де я requester
-- або addressee. Окрема функція, а не пряме розширення friendships_update,
-- саме щоб не чіпати той запис знову — WITH CHECK там навмисно не
-- відрізняє "рядок уже був accepted" від "я сам щойно зробив його
-- accepted", тож будь-яке послаблення для requester_id знову відкрило б
-- самопідтвердження дружби. SECURITY DEFINER-функція, натомість, сама
-- звіряє належність рядка викликачу і пише лише В ЙОГО ВЛАСНИЙ прапорець.
create or replace function public.mark_friendship_confirmed_seen(friendship_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  my_id uuid := auth.uid();
  row_data record;
begin
  select requester_id, addressee_id into row_data
  from public.friendships
  where id = friendship_id and status = 'accepted';

  if row_data is null then
    return;
  end if;

  if row_data.requester_id = my_id then
    update public.friendships
    set requester_seen_confirmed_at = now()
    where id = friendship_id;
  elsif row_data.addressee_id = my_id then
    update public.friendships
    set addressee_seen_confirmed_at = now()
    where id = friendship_id;
  end if;
end;
$$;

revoke execute on function public.mark_friendship_confirmed_seen(uuid) from public;
grant execute on function public.mark_friendship_confirmed_seen(uuid) to authenticated;
