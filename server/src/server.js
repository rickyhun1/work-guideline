// 서버 모드 (회사 서버에 PostgreSQL 을 따로 두고 실행할 때)
//   DATABASE_URL, JWT_SECRET, DATA_DIR(파일 저장 위치), PORT, HOST 환경변수 사용
import { pool } from './lib/db.js';
import { migrate } from './lib/migrate.js';
import { seed } from './lib/seed.js';
import { buildApp } from './app.js';

await migrate(pool);
await seed(pool);
const app = buildApp();
await app.listen({ port: Number(process.env.PORT || 3100), host: process.env.HOST || '0.0.0.0' });
