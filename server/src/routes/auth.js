import bcrypt from 'bcryptjs';
import { query } from '../lib/db.js';
import { AppError, badRequest } from '../lib/errors.js';
import { MODULES, LEVELS, numbering, getConfig, DEFAULT_COMPANY } from '../lib/core.js';

export function publicUser(u) {
  return {
    id: u.id, empNo: u.emp_no, name: u.name, departmentId: u.department_id ?? null, department: u.department ?? null,
    position: u.position ?? null, isAdmin: u.is_admin, active: u.active,
  };
}

const failures = new Map(); // ip -> {count, until}

export default async function authRoutes(app) {
  app.post('/auth/login', {
    schema: {
      body: {
        type: 'object', required: ['empNo', 'password'],
        properties: { empNo: { type: 'string' }, password: { type: 'string' } },
      },
    },
  }, async (req) => {
    const f = failures.get(req.ip);
    if (f && f.until > Date.now()) {
      throw new AppError(429, `여러 번 틀려서 잠시 막혔습니다. ${Math.ceil((f.until - Date.now()) / 60000)}분 뒤에 다시 하세요.`);
    }
    const { rows } = await query('SELECT * FROM users WHERE emp_no = $1 AND active', [req.body.empNo.trim()]);
    const user = rows[0];
    if (!user || !(await bcrypt.compare(req.body.password, user.password_hash))) {
      const n = (f && !f.until ? f.count : 0) + 1;
      failures.set(req.ip, { count: n, until: n >= 10 ? Date.now() + 10 * 60_000 : 0 });
      throw new AppError(401, '사번 또는 비밀번호가 올바르지 않습니다.');
    }
    failures.delete(req.ip);
    return { token: app.jwt.sign({ id: user.id }) };
  });

  /** 로그인한 사람 정보 + 메뉴별 권한 + 화면에 필요한 설정 */
  app.get('/me', { onRequest: app.auth }, async (req) => {
    const { rows } = await query(
      `SELECT u.*, d.name AS department FROM users u LEFT JOIN departments d ON d.id = u.department_id WHERE u.id = $1`,
      [req.user.id]);
    return {
      user: publicUser(rows[0]),
      perms: req.user.perms,
      modules: MODULES,
      levels: LEVELS,
      numbering: await numbering(),
      company: await getConfig('company', DEFAULT_COMPANY),
    };
  });

  app.post('/me/password', {
    onRequest: app.auth,
    schema: {
      body: {
        type: 'object', required: ['current', 'next'],
        properties: { current: { type: 'string' }, next: { type: 'string', minLength: 4 } },
      },
    },
  }, async (req) => {
    const { rows } = await query('SELECT password_hash FROM users WHERE id = $1', [req.user.id]);
    if (!(await bcrypt.compare(req.body.current, rows[0].password_hash))) throw badRequest('현재 비밀번호가 올바르지 않습니다.');
    await query('UPDATE users SET password_hash = $2 WHERE id = $1', [req.user.id, await bcrypt.hash(req.body.next, 10)]);
    return { ok: true };
  });
}
