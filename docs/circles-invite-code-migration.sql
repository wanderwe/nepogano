-- Запусти це один раз у Supabase Dashboard → SQL Editor.
-- Додає запрошення в коло за посиланням/кодом замість введення email вручну:
-- у кожного кола є свій invite_code, і будь-хто з кодом може приєднатись сам
-- через join_circle_by_code (без окремого кроку "прийняти запрошення").

alter table public.circles add column if not exists invite_code text;

update public.circles
set invite_code = substr(md5(random()::text || id::text), 1, 8)
where invite_code is null;

alter table public.circles alter column invite_code set not null;
alter table public.circles alter column invite_code
  set default substr(md5(random()::text), 1, 8);

create unique index if not exists circles_invite_code_idx
  on public.circles (invite_code);

-- security definer: приєднання йде в обхід RLS всередині функції, бо той, хто
-- ще не є членом кола, і так не має права ні бачити рядок circles (крім як за
-- невідомим наперед id), ні вставляти рядок у circle_members напряму.
create or replace function public.join_circle_by_code(code text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  target_circle_id uuid;
  my_email text;
begin
  select id into target_circle_id
  from public.circles
  where invite_code = lower(trim(code));

  if target_circle_id is null then
    raise exception 'invalid_code';
  end if;

  my_email := auth.jwt() ->> 'email';

  insert into public.circle_members (circle_id, user_id, invited_email, status)
  values (target_circle_id, auth.uid(), my_email, 'accepted')
  on conflict (circle_id, invited_email)
  do update set user_id = excluded.user_id, status = 'accepted';

  return target_circle_id;
end;
$$;

grant execute on function public.join_circle_by_code(text) to authenticated;
