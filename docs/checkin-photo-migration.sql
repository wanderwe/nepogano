-- Запусти це один раз у Supabase Dashboard → SQL Editor.
-- Додає опціональне фото до чек-іну: колонку photo_path у checkins,
-- приватний storage-бакет і політики, що дзеркалять видимість чек-інів
-- (власник + прийняті члени спільних кіл — та сама логіка, що вже є
-- в checkins_select_circle_mates).

alter table public.checkins add column if not exists photo_path text;

insert into storage.buckets (id, name, public)
values ('checkin-photos', 'checkin-photos', false)
on conflict (id) do nothing;

-- Шлях у бакеті: {user_id}/{щось унікальне}.jpg — перша "тека" в шляху
-- визначає власника фото.
create policy "checkin_photos_insert"
on storage.objects for insert
with check (
  bucket_id = 'checkin-photos'
  and (storage.foldername(name))[1] = auth.uid()::text
);

create policy "checkin_photos_select"
on storage.objects for select
using (
  bucket_id = 'checkin-photos'
  and (
    (storage.foldername(name))[1] = auth.uid()::text
    or exists (
      select 1
      from public.circle_members cm1
      join public.circle_members cm2 on cm1.circle_id = cm2.circle_id
      where cm1.user_id = auth.uid() and cm1.status = 'accepted'
        and cm2.status = 'accepted'
        and cm2.user_id::text = (storage.foldername(name))[1]
    )
  )
);

create policy "checkin_photos_delete"
on storage.objects for delete
using (
  bucket_id = 'checkin-photos'
  and (storage.foldername(name))[1] = auth.uid()::text
);
