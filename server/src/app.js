import Fastify from 'fastify';
import jwt from '@fastify/jwt';
import cors from '@fastify/cors';
import { readFileSync } from 'node:fs';
import bcrypt from 'bcryptjs';
import { query } from './lib/db.js';
import { AppError, forbidden } from './lib/errors.js';
import { effectivePerms, requireLevel, audit } from './lib/core.js';
import authRoutes from './routes/auth.js';
import adminRoutes from './routes/admin.js';
import documentRoutes from './routes/documents.js';
import formRoutes from './routes/forms.js';
import fileRoutes from './routes/files.js';
import lawRoutes from './routes/laws.js';
import projectRoutes from './routes/projects.js';
import miscRoutes from './routes/misc.js';
import exportRoutes from './routes/exports.js';

const VERSION = (() => {
  for (const rel of ['../package.json', './package.json']) {
    try {
      return JSON.parse(readFileSync(new URL(rel, import.meta.url), 'utf8')).version;
    } catch { /* 다음 후보 */ }
  }
  return 'unknown';
})();

export function buildApp(opts = {}) {
  const app = Fastify({ logger: opts.logger ?? true, bodyLimit: 100 * 1024 * 1024 });

  const secret = process.env.JWT_SECRET;
  if (!secret && process.env.NODE_ENV === 'production') {
    throw new Error('운영 환경에서는 JWT_SECRET 을 반드시 설정해야 합니다.');
  }
  app.register(jwt, { secret: secret || 'dev-only-secret', sign: { expiresIn: '30d' } });
  app.register(cors);

  // 파일 올리기: 본문 = 파일 바이트
  app.addContentTypeParser('application/octet-stream', { parseAs: 'buffer' }, (req, body, done) => done(null, body));

  /**
   * 로그인 확인. 권한·사용 여부는 토큰이 아니라 매 요청마다 DB에서 읽는다
   * (권한을 회수하거나 퇴사 처리하면 즉시 반영되도록).
   */
  async function loadUser(req) {
    await req.jwtVerify();
    const { rows } = await query(
      `SELECT u.id, u.name, u.is_admin, u.active, u.department_id, d.name AS department
         FROM users u LEFT JOIN departments d ON d.id = u.department_id WHERE u.id = $1`, [req.user.id]);
    const u = rows[0];
    if (!u || !u.active) throw new AppError(401, '사용할 수 없는 계정입니다. 관리자에게 문의하세요.');
    req.user = { id: u.id, name: u.name, isAdmin: u.is_admin, departmentId: u.department_id, department: u.department };
    req.user.perms = await effectivePerms(req.user);
  }
  app.decorate('auth', loadUser);
  /** app.need('docs', 2) : 업무표준 등록·수정 권한 필요. app.need('admin') : 관리자 */
  app.decorate('need', (module, level = 1) => async (req) => {
    await loadUser(req);
    if (module === 'admin') {
      if (!req.user.isAdmin) throw forbidden('관리자 권한이 필요합니다.');
      return;
    }
    requireLevel(req, module, level);
  });

  app.setErrorHandler((err, req, reply) => {
    if (err instanceof AppError) return reply.status(err.statusCode).send({ error: err.message });
    if (err.statusCode === 401 || err.code?.startsWith?.('FST_JWT')) {
      return reply.status(401).send({ error: '로그인이 필요합니다.' });
    }
    if (err.validation) return reply.status(400).send({ error: `입력값 오류: ${err.message}` });
    if (err.statusCode >= 400 && err.statusCode < 500) {
      const msg = { 413: '파일이 너무 큽니다.', 415: '지원하지 않는 요청 형식입니다.' }[err.statusCode] || err.message;
      return reply.status(err.statusCode).send({ error: msg });
    }
    if (err.code === '23505') return reply.status(409).send({ error: '이미 존재하는 값입니다.' });
    if (err.code === '23503') return reply.status(400).send({ error: '참조 대상이 존재하지 않습니다.' });
    req.log.error(err);
    return reply.status(500).send({ error: '서버 오류가 발생했습니다.' });
  });

  app.get('/health', async () => ({ ok: true, version: VERSION, mode: process.env.SERVER_MODE || 'server' }));

  // 최초 실행: 사용자가 한 명도 없을 때만 첫 관리자를 만든다. 첫 관리자는 기본 편집 부서(총무팀) 소속.
  app.get('/setup/status', async () => {
    const { rows } = await query('SELECT count(*)::int AS c FROM users');
    return { needsSetup: rows[0].c === 0 };
  });
  app.post('/setup', {
    schema: {
      body: {
        type: 'object',
        required: ['empNo', 'name', 'password'],
        properties: {
          empNo: { type: 'string', minLength: 1 },
          name: { type: 'string', minLength: 1 },
          password: { type: 'string', minLength: 4 },
        },
      },
    },
  }, async (req, reply) => {
    const hash = await bcrypt.hash(req.body.password, 10);
    const { rows: d } = await query(`SELECT id FROM departments WHERE active ORDER BY sort_order, id LIMIT 1`);
    const { rows } = await query(
      `INSERT INTO users (emp_no, name, is_admin, password_hash, department_id)
       SELECT $1, $2, TRUE, $3, $4 WHERE NOT EXISTS (SELECT 1 FROM users) RETURNING id`,
      [req.body.empNo.trim(), req.body.name.trim(), hash, d[0]?.id ?? null],
    );
    if (!rows[0]) return reply.status(409).send({ error: '이미 설정이 완료되었습니다.' });
    await audit({ query }, { user: { id: rows[0].id, name: req.body.name } }, '등록', 'user', rows[0].id, `첫 관리자 ${req.body.empNo}`);
    return { ok: true };
  });

  if (opts.extraRoutes) app.register(opts.extraRoutes);

  app.register(authRoutes);
  app.register(adminRoutes);
  app.register(documentRoutes);
  app.register(formRoutes);
  app.register(fileRoutes);
  app.register(lawRoutes);
  app.register(projectRoutes);
  app.register(miscRoutes);
  app.register(exportRoutes);

  return app;
}
