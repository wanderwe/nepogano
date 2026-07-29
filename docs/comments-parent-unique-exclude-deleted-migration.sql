-- Запусти це один раз у Supabase Dashboard → SQL Editor. Безпечно запускати
-- повторно.
--
-- Реальна прогалина, знайдена під час тестування: унікальний індекс
-- "максимум одна відповідь на коментар" (checkin_comments_parent_unique /
-- subject_checkin_comments_parent_unique) не враховував soft-delete —
-- видалення коментаря лише проставляє deleted_at, сам рядок і його
-- parent_id лишаються в таблиці. Тобто якщо відповідь видалили, слот
-- parent_id лишався зайнятим НАЗАВЖДИ — ніхто більше не міг відповісти на
-- той самий кореневий коментар, і INSERT просто відхилявся з
-- "duplicate key value violates unique constraint" (в застосунку це
-- виглядало як загальне "Не вдалось надіслати коментар" без пояснення).
--
-- Перебудовуємо обидва індекси так, щоб видалені відповіді більше не
-- займали слот — тред знову відкритий для нової відповіді після видалення
-- старої.

drop index if exists checkin_comments_parent_unique;
create unique index if not exists checkin_comments_parent_unique
on public.checkin_comments (parent_id)
where parent_id is not null and deleted_at is null;

drop index if exists subject_checkin_comments_parent_unique;
create unique index if not exists subject_checkin_comments_parent_unique
on public.subject_checkin_comments (parent_id)
where parent_id is not null and deleted_at is null;
