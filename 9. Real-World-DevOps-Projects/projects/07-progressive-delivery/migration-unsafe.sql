-- Deliberately unsafe review fixture. Do not execute against a live database.
ALTER TABLE orders DROP COLUMN amount_cents;
