-- Запусти це один раз у Supabase Dashboard → SQL Editor.
-- Дозволяє юзеру бачити не тільки власні здогадки (guesser_id = я, вже
-- дозволено наявною політикою), а й ті, що зробили ПРО НЬОГО друзі
-- (target_user_id = я) — потрібно для статистики "скільки разів друзі
-- вгадали твій настрій" на екрані "Друзі".

create policy "circle_guesses_select_about_me"
on public.circle_guesses for select
using (target_user_id = auth.uid());
