-- Запусти це один раз у Supabase Dashboard → SQL Editor (повторний запуск
-- безпечний — create or replace просто оновить існуючу функцію).
-- Дозволяє юзеру видалити ВЛАСНИЙ акаунт (checkins, фото в Storage і сам
-- auth-користувач) через RPC-виклик з застосунку, без service role key
-- на клієнті.

create or replace function public.delete_own_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Фото лежать у бакеті checkin-photos за шляхом {user_id}/... — видалення
  -- рядків з storage.objects прибирає й самі файли з бекенду (не тільки
  -- метадані), інакше вони лишаються осиротілими навіть після видалення
  -- акаунта й усіх його checkins.
  delete from storage.objects
  where bucket_id = 'checkin-photos'
    and (storage.foldername(name))[1] = auth.uid()::text;

  delete from public.checkins where user_id = auth.uid();
  delete from auth.users where id = auth.uid();
end;
$$;

grant execute on function public.delete_own_account() to authenticated;
