import pg from 'pg';

// DATE 컬럼은 'YYYY-MM-DD' 문자열 그대로 받는다 (시간대 변환 방지)
pg.types.setTypeParser(1082, (v) => v);
// NUMERIC 은 숫자로
pg.types.setTypeParser(1700, (v) => (v === null ? null : Number(v)));

export const pool = new pg.Pool({
  connectionString: process.env.DATABASE_URL || 'postgres://localhost/work_guideline',
});

export function query(text, params) {
  return pool.query(text, params);
}

/** 트랜잭션 실행. fn(client) 이 던지면 롤백. */
export async function tx(fn) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const result = await fn(client);
    await client.query('COMMIT');
    return result;
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}
