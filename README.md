# DoltgreSQL 1.3.1: a named NOT NULL column constraint refuses the whole table

On DoltgreSQL 1.3.1, a `CREATE TABLE` fails when a column's NOT NULL constraint has a name, as in
`id integer CONSTRAINT id_required NOT NULL`, and the table is not created:

```
ERROR:  non-foreign key column constraint names are not yet supported
```

PostgreSQL 18.6 creates the table and keeps the constraint under that name.

## Reproduce it

You need Docker and a POSIX shell: Linux, macOS, or Windows with WSL. The first run downloads the images.

```sh
git clone https://github.com/Reliable-Collaboration/repro-doltgresql-bug-named-not-null.git
cd repro-doltgresql-bug-named-not-null
./repro.sh
```

`repro.sh` starts PostgreSQL 18.6 and DoltgreSQL 1.3.1 in throwaway containers, waits until both accept
connections, runs [`repro.sql`](repro.sql) on each with the `psql` client inside its container, prints the
two outputs side by side, and removes the containers. It exits 0 when DoltgreSQL's output is identical to
PostgreSQL's and 1 when it differs; with DoltgreSQL 1.3.1 it exits 1.

To try another DoltgreSQL release, name its image (`POSTGRES_IMAGE` does the same for PostgreSQL):

```sh
DOLTGRESQL_IMAGE=dolthub/doltgresql:latest ./repro.sh
```

### Without the script

The same steps by hand, from the repository directory:

```sh
docker run -d --name repro-doltgresql-bug-named-not-null-postgres -e POSTGRES_PASSWORD=password postgres:18.6-bookworm
docker run -d --name repro-doltgresql-bug-named-not-null-doltgresql -e DOLTGRES_PASSWORD=password dolthub/doltgresql:1.3.1
docker cp repro.sql repro-doltgresql-bug-named-not-null-postgres:/tmp/repro.sql
docker cp repro.sql repro-doltgresql-bug-named-not-null-doltgresql:/tmp/repro.sql
docker exec -t -e PGPASSWORD=password repro-doltgresql-bug-named-not-null-postgres psql -X -P pager=off -h 127.0.0.1 -U postgres -d postgres --echo-all -f /tmp/repro.sql
docker exec -t -e PGPASSWORD=password repro-doltgresql-bug-named-not-null-doltgresql psql -X -P pager=off -h 127.0.0.1 -U postgres -d postgres --echo-all -f /tmp/repro.sql
docker rm -f repro-doltgresql-bug-named-not-null-postgres repro-doltgresql-bug-named-not-null-doltgresql
```

If `docker exec` answers that the connection was refused, the server is still starting: wait a few seconds
and run it again.

## The test

[`repro.sql`](repro.sql):

```sql
-- A NOT NULL column constraint with a name.
CREATE TABLE t (
    id integer CONSTRAINT id_required NOT NULL,
    v text
);

-- Was the table created?
SELECT table_name FROM information_schema.tables
WHERE table_name = 't';
```

## Expected behavior

The table is created, and the query finds it. This is what PostgreSQL 18.6 prints:

```
-- A NOT NULL column constraint with a name.
CREATE TABLE t (
    id integer CONSTRAINT id_required NOT NULL,
    v text
);
CREATE TABLE
-- Was the table created?
SELECT table_name FROM information_schema.tables
WHERE table_name = 't';
 table_name 
------------
 t
(1 row)
```

## Actual behavior

The `CREATE TABLE` fails, and the query finds no table. This is what DoltgreSQL 1.3.1 prints:

```
-- A NOT NULL column constraint with a name.
CREATE TABLE t (
    id integer CONSTRAINT id_required NOT NULL,
    v text
);
psql:/tmp/repro.sql:5: ERROR:  non-foreign key column constraint names are not yet supported
-- Was the table created?
SELECT table_name FROM information_schema.tables
WHERE table_name = 't';
 table_name 
------------
(0 rows)
```

## Side by side

The output of `./repro.sh`. The view cuts long lines at the width of their column, so DoltgreSQL's error
is shortened here; the two sections above show both outputs whole.

```
Starting postgres:18.6-bookworm@sha256:1c59e2c3c818eaa0f0628f695b36e7c9e362d6b219b36a54a32df645cbd7e1af
Starting dolthub/doltgresql:1.3.1@sha256:6c85cb1f35beabf47f094336a420255130b841b1645f36d79ef046276af36851

Left: PostgreSQL. Right: DoltgreSQL. Lines that differ are marked with |.

-- A NOT NULL column constraint with a name.                  -- A NOT NULL column constraint with a name.
CREATE TABLE t (                                              CREATE TABLE t (
    id integer CONSTRAINT id_required NOT NULL,                   id integer CONSTRAINT id_required NOT NULL,
    v text                                                        v text
);                                                            );
CREATE TABLE                                                | psql:/tmp/repro.sql:5: ERROR:  non-foreign key column const
-- Was the table created?                                     -- Was the table created?
SELECT table_name FROM information_schema.tables              SELECT table_name FROM information_schema.tables
WHERE table_name = 't';                                       WHERE table_name = 't';
 table_name                                                    table_name 
------------                                                  ------------
 t                                                          | (0 rows)
(1 row)                                                     <


Result: DoltgreSQL's output differs from PostgreSQL's on 2 line(s), marked with |.
```

## Other observations

Each was run on DoltgreSQL 1.3.1 and on PostgreSQL 18.6, which accepted every statement below.

- The same error, and no table, for other names on a NOT NULL column constraint: the default name
  (`id integer CONSTRAINT t_id_not_null NOT NULL` in table `t`), a quoted name
  (`id integer CONSTRAINT "Id Required" NOT NULL`), a later column (`v text CONSTRAINT v_required NOT NULL`),
  and a name after a default (`id integer DEFAULT 0 CONSTRAINT id_required NOT NULL`).
- `ALTER TABLE ... ADD COLUMN v text CONSTRAINT v_required NOT NULL` fails with the same error.
- Named `DEFAULT`, `UNIQUE`, `PRIMARY KEY` and `NULL` column constraints fail with the same error, for
  example `id integer CONSTRAINT id_default DEFAULT 0`.
- Accepted: a named `CHECK` column constraint (`id integer CONSTRAINT id_positive CHECK (id > 0)`), a named
  `REFERENCES` column constraint, a named generated column
  (`g integer CONSTRAINT g_generated GENERATED ALWAYS AS (id + 1) STORED`), and named `CHECK`, `UNIQUE` and
  `PRIMARY KEY` table constraints.
- Accepted without a name: `id integer NOT NULL`, and `ALTER TABLE ... ALTER COLUMN id SET NOT NULL`.
- The table-constraint forms of a named NOT NULL fail with a different error, `at or near "not": syntax error`:
  `CONSTRAINT id_required NOT NULL id` inside `CREATE TABLE`, and
  `ALTER TABLE ... ADD CONSTRAINT id_required NOT NULL id`.
- pg_dump 18.6 writes such a constraint the way this test does, `id integer CONSTRAINT id_required NOT NULL`,
  also when it was created with a table-constraint form; with the default name, `t_id_not_null`, it writes
  `id integer NOT NULL`.
- PostgreSQL 18.6 lists the constraint in `pg_constraint` as `id_required` with `contype` `n`; DoltgreSQL
  1.3.1 lists no NOT NULL constraint there, not even for `id integer NOT NULL`.

## Environment

- DoltgreSQL 1.3.1, the newest release when this was written: image `dolthub/doltgresql:1.3.1`, digest
  `sha256:6c85cb1f35beabf47f094336a420255130b841b1645f36d79ef046276af36851`. Its bundled `psql` is 17.11.
- PostgreSQL 18.6: image `postgres:18.6-bookworm`, digest
  `sha256:1c59e2c3c818eaa0f0628f695b36e7c9e362d6b219b36a54a32df645cbd7e1af`. Its `psql` is 18.6.
- Reproduced on 2026-09-11 (UTC) with Docker 29.7.2 on Linux x86_64 (Ubuntu 26.04.1 LTS under WSL 2).
