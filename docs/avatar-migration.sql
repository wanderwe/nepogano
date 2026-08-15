-- Запусти це один раз у Supabase Dashboard → SQL Editor.
-- Додає аватарку профілю: колонку avatar_path у profiles, приватний
-- storage-бакет і політики видимості, що дзеркалять
-- checkin_photos_select_friends (власник + друзі) — але БЕЗ гейту
-- вгадування: аватарка не частина гри, видно одразу, як і display_name.

alter table public.profiles add column if not exists avatar_path text;
-- Те саме кадрування, що фото чек-іну (photo_align_y/photo_scale) —
-- PhotoRepositionScreen перевикористовується один в один, тож і формат
-- збереження той самий.
alter table public.profiles add column if not exists avatar_align_y double precision not null default 0;
alter table public.profiles add column if not exists avatar_scale double precision not null default 1;

insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', false)
on conflict (id) do nothing;

-- Шлях у бакеті: {user_id}/avatar.jpg — завжди той самий файл (на відміну
-- від checkin-photos, де кожне фото унікальне): заміна аватарки просто
-- перезаписує той самий об'єкт, історія старих не потрібна.
create policy "avatars_insert"
on storage.objects for insert
with check (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = auth.uid()::text
);

create policy "avatars_update"
on storage.objects for update
using (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = auth.uid()::text
);

create policy "avatars_select_friends"
on storage.objects for select
using (
  bucket_id = 'avatars'
  and (
    (storage.foldername(name))[1] = auth.uid()::text
    or (storage.foldername(name))[1] in (
      select addressee_id::text from public.friendships
      where requester_id = auth.uid() and status = 'accepted' and addressee_id is not null
      union
      select requester_id::text from public.friendships
      where addressee_id = auth.uid() and status = 'accepted'
    )
  )
);

create policy "avatars_delete"
on storage.objects for delete
using (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = auth.uid()::text
);

-- Розширюємо чистку акаунта (delete-account-function.sql) на новий бакет —
-- та сама причина, що й для checkin-photos: видалення рядків storage.objects
-- прибирає й самі файли, інакше лишаються осиротілими.
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

  delete from storage.objects
  where bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text;

  delete from public.checkins where user_id = auth.uid();
  delete from auth.users where id = auth.uid();
end;
$$;

grant execute on function public.delete_own_account() to authenticated;
