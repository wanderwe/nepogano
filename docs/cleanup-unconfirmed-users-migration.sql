-- Запусти це один раз у Supabase Dashboard → SQL Editor. Безпечно запускати
-- повторно.
--
-- Реальний сценарій, знайдений наживо: юзер вводить email вручну, лист
-- підтвердження приходить, але юзер його не підтверджує — і одразу заходить
-- через Google/Apple. Оскільки перший акаунт лишається непідтвердженим,
-- Supabase НЕ з'єднує його з OAuth-входом (анти-захоплення акаунту), а
-- створює другий, окремий auth.users-рядок. Перший назавжди лишається
-- покинутим сміттям — залогінитись у нього без підтвердження неможливо,
-- тож видаляти такі акаунти завжди безпечно (жодних даних там бути не може:
-- checkins/friendships/subjects прив'язуються тільки після входу).
--
-- Це не запобігає самому дублюванню (для цього юзер мав би підтвердити
-- лист до OAuth-входу) — лише не дає покинутим акаунтам накопичуватись.

create or replace function public.cleanup_unconfirmed_users()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from auth.users
  where email_confirmed_at is null
    and created_at < now() - interval '48 hours';
end;
$$;

-- pg_cron — стандартне розширення Supabase, увімкнути можна і тут, і через
-- Dashboard → Database → Extensions.
create extension if not exists pg_cron with schema extensions;

select cron.schedule(
  'cleanup-unconfirmed-users-daily',
  '0 3 * * *', -- щодня о 03:00 UTC
  $$select public.cleanup_unconfirmed_users();$$
);
