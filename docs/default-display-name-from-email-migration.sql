-- Запусти це один раз у Supabase Dashboard → SQL Editor. Безпечно запускати
-- повторно.
--
-- display_name лишався NULL, якщо юзер жодного разу не заходив у Профіль і
-- не вводив ім'я вручну — і скрізь, де показується чуже ім'я (коментарі,
-- Друзі без email-фолбеку), був порожній рядок замість чогось людського.
-- Фолбек на email у Друзях працює лише тому, що email лежить прямо в рядку
-- friendships (записаний ще при запрошенні); для коментарів (ширше коло,
-- ніж прямі друзі — profiles_select_co_commenters) такого джерела нема.
--
-- Фікс — display_name більше ніколи не буває NULL: дефолт береться з
-- частини email до "@" одразу при створенні профілю. Форма в Профілі не
-- змінюється — юзер так само може замінити це на власне ім'я коли завгодно.
-- Безпечно щодо вже збережених імен: кнопка "Зберегти" в _editDisplayName
-- заблокована на порожньому полі, тож NULL завжди означає "ще не чіпав",
-- ніколи "свідомо очистив" — перезаписувати нічиєчий вибір тут нема ризику.

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (user_id, display_name)
  values (new.id, split_part(new.email, '@', 1))
  on conflict do nothing;
  return new;
end;
$$;

-- Бекфіл для вже існуючих акаунтів, які досі не заповнили ім'я самі.
update public.profiles p
set display_name = split_part(u.email, '@', 1)
from auth.users u
where p.user_id = u.id
  and p.display_name is null;
