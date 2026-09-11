-- A NOT NULL column constraint with a name.
CREATE TABLE t (
    id integer CONSTRAINT id_required NOT NULL,
    v text
);

-- Was the table created?
SELECT table_name FROM information_schema.tables
WHERE table_name = 't';
