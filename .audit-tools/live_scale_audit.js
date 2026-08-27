const { Client } = require(
  `${process.env.TEMP}\\travel-pg-audit\\node_modules\\pg`,
);

async function main() {
  const client = new Client({
    connectionString: process.env.TRAVEL_AUDIT_DB_URL,
    ssl: { rejectUnauthorized: false },
  });
  await client.connect();
  const columns = await client.query(
    `select column_name, data_type, udt_name, is_nullable
       from information_schema.columns
      where table_schema = $1 and table_name = $2
      order by ordinal_position`,
    ['public', 'locations'],
  );
  const indexes = await client.query(
    `select indexname, indexdef
       from pg_indexes
      where schemaname = $1 and tablename = $2
      order by indexname`,
    ['public', 'locations'],
  );
  const functions = await client.query(
    `select p.proname,
            pg_get_function_identity_arguments(p.oid) as args,
            pg_get_function_result(p.oid) as result,
            pg_get_functiondef(p.oid) as definition
       from pg_proc p
       join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = $1 and p.proname = any($2)
      order by p.proname`,
    ['public', ['locations_in_bounds', 'nearby_discovery_candidates']],
  );
  const explain = await client.query(
    `explain (format json)
     select id, owner_id, name, description, position, created_at,
            status, visibility, moderation
       from public.locations
      where status = $1
        and visibility = $2
        and position && ST_MakeEnvelope($3, $4, $5, $6, 4326)::geography
      order by created_at desc
      limit 300`,
    ['approved', 'public', 30, 40, 31, 51],
  );
  process.stdout.write(
    JSON.stringify(
      {
        columns: columns.rows,
        indexes: indexes.rows,
        functions: functions.rows,
        explain: explain.rows,
      },
      null,
      2,
    ),
  );
  await client.end();
}

main().catch((error) => {
  process.stderr.write(`${error.message}\n`);
  process.exitCode = 1;
});
