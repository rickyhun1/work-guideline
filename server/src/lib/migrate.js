import { readdir, readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

import { existsSync } from 'node:fs';

// 소스: src/lib/../../migrations, 배포판(한 파일로 묶음): server/migrations
const here = path.dirname(fileURLToPath(import.meta.url));
const dir = [process.env.MIGRATIONS_DIR, path.join(here, '..', '..', 'migrations'), path.join(here, 'migrations')]
  .find((d) => d && existsSync(d));

/** migrations/ 폴더의 .sql 파일 중 아직 적용되지 않은 것을 이름순으로 적용한다. */
export async function migrate(pool, log = console.log) {
  await pool.query(`CREATE TABLE IF NOT EXISTS schema_migrations (
    name TEXT PRIMARY KEY, applied_at TIMESTAMPTZ NOT NULL DEFAULT now())`);
  const { rows } = await pool.query('SELECT name FROM schema_migrations');
  const done = new Set(rows.map((r) => r.name));

  for (const file of (await readdir(dir)).filter((f) => f.endsWith('.sql')).sort()) {
    if (done.has(file)) continue;
    const sql = await readFile(path.join(dir, file), 'utf8');
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      await client.query(sql);
      await client.query('INSERT INTO schema_migrations (name) VALUES ($1)', [file]);
      await client.query('COMMIT');
      log(`마이그레이션 적용: ${file}`);
    } catch (e) {
      await client.query('ROLLBACK');
      throw new Error(`마이그레이션 실패 (${file}): ${e.message}`);
    } finally {
      client.release();
    }
  }
}
