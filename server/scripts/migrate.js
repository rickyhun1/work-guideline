import { pool } from '../src/lib/db.js';
import { migrate } from '../src/lib/migrate.js';

await migrate(pool);
await pool.end();
