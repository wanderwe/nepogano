-- Запусти це один раз у Supabase Dashboard → SQL Editor.
-- Дозволяє юзеру видалити ВЛАСНИЙ акаунт (checkins + сам auth-користувач)
-- через RPC-виклик з застосунку, без потреби в service role key на клієнті.

create or replace function public.delete_own_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.checkins where user_id = auth.uid();
  delete from auth.users where id = auth.uid();
end;
$$;

grant execute on function public.delete_own_account() to authenticated;
