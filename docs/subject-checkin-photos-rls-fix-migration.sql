-- Запусти це один раз у Supabase Dashboard → SQL Editor. Безпечно запускати
-- повторно (drop policy if exists перед create).
--
-- Реальний баг: фото сутностей (subjects-migration.sql) свідомо покладались
-- на наявну checkin_photos_select_friends — вона дозволяє select лише
-- власнику папки в шляху АБО його друзям. Це працювало, поки сутності були
-- повністю приватні: єдиний, хто міг щось завантажити, — сам власник, і він
-- завжди бачить власні файли.
--
-- Але відтоді з'явились співавтори (subject-coauthors-migration.sql,
-- subject_checkins.author_id) і перегляд колом (subject-sharing-migration.sql).
-- uploadCheckinPhoto будує шлях від auth.uid() того, хто РЕАЛЬНО завантажив
-- фото, — тобто для чек-іну, який лишив співавтор, це його власний user_id,
-- не власника сутності. Учасник кола, якому власник відкрив щоденник на
-- перегляд, майже напевно НЕ друг конкретно з тим співавтором (лише з
-- власником) — тож checkin_photos_select_friends його блокує: сам рядок
-- subject_checkins юзер бачить (текст/настрій), а фото — ні.
--
-- Фікс: окрема адитивна SELECT-політика, що дзеркалить точно ту саму
-- видимість, яку вже має сам рядок subject_checkins (власник/співавтор/
-- учасник кола, яким відкрито перегляд) — не через friendships, а напряму
-- через subject_checkins.photo_path.

drop policy if exists "checkin_photos_select_subject_shared" on storage.objects;
create policy "checkin_photos_select_subject_shared"
on storage.objects for select
using (
  bucket_id = 'checkin-photos'
  and exists (
    select 1 from public.subject_checkins sc
    where sc.photo_path = storage.objects.name
      and (
        public.owns_subject(sc.subject_id)
        or public.is_subject_coauthor(sc.subject_id)
        or public.subject_shared_with_me(sc.subject_id)
      )
  )
);
