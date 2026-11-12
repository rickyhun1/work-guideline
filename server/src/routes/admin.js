// 관리자: 사용자, 부서, 권한, 번호 체계, 회사 설정
import bcrypt from 'bcryptjs';
import { query, tx } from '../lib/db.js';
import { badRequest, conflict, notFound } from '../lib/errors.js';
import {
  MODULES, LEVELS, DEFAULT_LEVELS, DEFAULT_COMPANY, getConfig, setConfig, numbering, renumber, audit, diffFields,
} from '../lib/core.js';
import { publicUser } from './auth.js';

const userProps = {
  empNo: { type: 'string', minLength: 1 },
  name: { type: 'string', minLength: 1 },
  departmentId: { type: ['integer', 'null'] },
  position: { type: ['string', 'null'] },
  isAdmin: { type: 'boolean' },
  password: { type: 'string', minLength: 4 },
  active: { type: 'boolean' },
};
const levelMap = { type: 'object', additionalProperties: { type: 'integer', minimum: 0, maximum: 3 } };

export default async function adminRoutes(app) {
  const admin = app.need('admin');

  // ------------------------------------------------------------ 부서 (목록은 누구나)
  app.get('/departments', { onRequest: app.auth }, async () => {
    const { rows } = await query('SELECT id, name, sort_order FROM departments WHERE active ORDER BY sort_order, id');
    return rows.map((r) => ({ id: r.id, name: r.name, sortOrder: r.sort_order }));
  });
  app.post('/departments', {
    onRequest: admin,
    schema: { body: { type: 'object', required: ['name'], properties: { name: { type: 'string', minLength: 1 } } } },
  }, async (req) => {
    const { rows } = await query(
      `INSERT INTO departments (name, sort_order) SELECT $1, COALESCE(MAX(sort_order), 0) + 1 FROM departments RETURNING id`,
      [req.body.name.trim()]);
    await audit({ query }, req, '등록', 'department', rows[0].id, req.body.name.trim());
    return { id: rows[0].id };
  });
  app.patch('/departments/:id', {
    onRequest: admin,
    schema: { body: { type: 'object', properties: { name: { type: 'string', minLength: 1 }, sortOrder: { type: 'integer' } } } },
  }, async (req) => {
    const id = Number(req.params.id);
    const { rows: old } = await query('SELECT * FROM departments WHERE id = $1', [id]);
    if (!old[0]) throw notFound();
    await query('UPDATE departments SET name = COALESCE($2, name), sort_order = COALESCE($3, sort_order) WHERE id = $1',
      [id, req.body.name?.trim() ?? null, req.body.sortOrder ?? null]);
    if (req.body.name && req.body.name.trim() !== old[0].name) {
      await audit({ query }, req, '수정', 'department', id, req.body.name.trim(), { changes: { 부서명: [old[0].name, req.body.name.trim()] } });
    }
    return { ok: true };
  });
  app.delete('/departments/:id', { onRequest: admin }, async (req) => {
    const id = Number(req.params.id);
    const { rows } = await query('UPDATE departments SET active = FALSE WHERE id = $1 RETURNING name', [id]);
    if (!rows[0]) throw notFound();
    await audit({ query }, req, '삭제', 'department', id, rows[0].name);
    return { ok: true };
  });

  // ------------------------------------------------------------ 사용자
  app.get('/users', { onRequest: admin }, async () => {
    const { rows } = await query(
      `SELECT u.*, d.name AS department FROM users u LEFT JOIN departments d ON d.id = u.department_id ORDER BY u.emp_no`);
    return rows.map(publicUser);
  });
  /** 담당자 지정용 이름 목록 (로그인한 누구나) */
  app.get('/users/names', { onRequest: app.auth }, async () => {
    const { rows } = await query(
      `SELECT u.name, d.name AS department FROM users u LEFT JOIN departments d ON d.id = u.department_id WHERE u.active ORDER BY d.sort_order NULLS LAST, u.name`);
    return rows;
  });

  app.post('/users', {
    onRequest: admin,
    schema: { body: { type: 'object', required: ['empNo', 'name', 'password'], properties: userProps } },
  }, async (req, reply) => {
    const b = req.body;
    const { rows } = await query(
      `INSERT INTO users (emp_no, name, department_id, position, is_admin, password_hash)
       VALUES ($1, $2, $3, $4, $5, $6) RETURNING *`,
      [b.empNo.trim(), b.name.trim(), b.departmentId ?? null, b.position ?? null, b.isAdmin ?? false, await bcrypt.hash(b.password, 10)]);
    await audit({ query }, req, '등록', 'user', rows[0].id, `${b.empNo} ${b.name}`);
    return reply.status(201).send(publicUser(rows[0]));
  });

  app.patch('/users/:id', {
    onRequest: admin,
    schema: { body: { type: 'object', properties: userProps } },
  }, async (req) => {
    const b = req.body;
    const id = Number(req.params.id);
    if (id === req.user.id && b.active === false) throw badRequest('본인 계정은 사용 중지할 수 없습니다.');
    const hash = b.password ? await bcrypt.hash(b.password, 10) : null;
    return tx(async (db) => {
      await db.query('SELECT id FROM users WHERE is_admin AND active FOR UPDATE');
      const { rows: old } = await db.query('SELECT * FROM users WHERE id = $1', [id]);
      if (!old[0]) throw notFound();
      const { rows } = await db.query(
        `UPDATE users SET
           name = COALESCE($2, name),
           department_id = CASE WHEN $3::boolean THEN $4::int ELSE department_id END,
           position = CASE WHEN $5::boolean THEN $6 ELSE position END,
           is_admin = COALESCE($7, is_admin),
           active = COALESCE($8, active),
           password_hash = COALESCE($9, password_hash)
         WHERE id = $1 RETURNING *`,
        [id, b.name ?? null, 'departmentId' in b, b.departmentId ?? null, 'position' in b, b.position ?? null,
          b.isAdmin ?? null, b.active ?? null, hash]);
      const { rows: left } = await db.query('SELECT count(*)::int AS c FROM users WHERE is_admin AND active');
      if (left[0].c === 0) throw conflict('관리자가 최소 한 명은 있어야 합니다. 다른 사람을 먼저 관리자로 지정하세요.');
      const ch = diffFields(old[0], rows[0], { name: '이름', department_id: '부서', position: '직책', is_admin: '관리자', active: '사용' });
      if (hash) ch['비밀번호'] = ['', '변경됨'];
      await audit(db, req, '수정', 'user', id, `${rows[0].emp_no} ${rows[0].name}`, { changes: ch });
      return publicUser(rows[0]);
    });
  });

  // ------------------------------------------------------------ 권한
  async function loadPerms() {
    const { rows: dp } = await query('SELECT department_id, module, level FROM department_permissions');
    const { rows: up } = await query('SELECT user_id, module, level FROM user_permissions');
    const dept = {};
    for (const r of dp) (dept[r.department_id] ??= {})[r.module] = r.level;
    const user = {};
    for (const r of up) (user[r.user_id] ??= {})[r.module] = r.level;
    return { modules: MODULES, levels: LEVELS, defaults: await getConfig('default_levels', DEFAULT_LEVELS), departments: dept, users: user };
  }
  app.get('/permissions', { onRequest: admin }, loadPerms);

  /** 권한 저장. defaults: 모든 사람 기본값, departments: {부서id: {module: level}}, users: {사용자id: {...}} */
  app.put('/permissions', {
    onRequest: admin,
    schema: {
      body: {
        type: 'object',
        properties: {
          defaults: levelMap,
          departments: { type: 'object', additionalProperties: levelMap },
          users: { type: 'object', additionalProperties: levelMap },
        },
      },
    },
  }, async (req) => {
    const before = await loadPerms();
    await tx(async (db) => {
      if (req.body.defaults) await setConfig('default_levels', { ...DEFAULT_LEVELS, ...req.body.defaults }, db);
      if (req.body.departments) {
        await db.query('DELETE FROM department_permissions');
        for (const [d, m] of Object.entries(req.body.departments)) {
          for (const [mod, lv] of Object.entries(m)) {
            if (lv > 0) await db.query('INSERT INTO department_permissions VALUES ($1, $2, $3)', [Number(d), mod, lv]);
          }
        }
      }
      if (req.body.users) {
        await db.query('DELETE FROM user_permissions');
        for (const [u, m] of Object.entries(req.body.users)) {
          for (const [mod, lv] of Object.entries(m)) {
            if (lv > 0) await db.query('INSERT INTO user_permissions VALUES ($1, $2, $3)', [Number(u), mod, lv]);
          }
        }
      }
      await audit(db, req, '설정', 'settings', null, '권한 변경', {
        changes: { 권한: [{ 기본: before.defaults, 부서: before.departments, 개인: before.users }, req.body] },
      });
    });
    return { ok: true };
  });

  // ------------------------------------------------------------ 번호 체계
  const numberingSchema = {
    type: 'object', required: ['types', 'docPattern', 'formPattern'],
    properties: {
      types: {
        type: 'array', minItems: 1,
        items: {
          type: 'object', required: ['key', 'label', 'prefix'],
          properties: { key: { type: 'string', minLength: 1 }, label: { type: 'string', minLength: 1 }, prefix: { type: 'string' } },
        },
      },
      docPattern: { type: 'string', minLength: 1 },
      formPattern: { type: 'string', minLength: 1 },
    },
  };
  function checkNumbering(nb) {
    if (!nb.docPattern.includes('{num')) throw badRequest('문서번호 형식에 {num} 이 있어야 합니다.');
    if (!nb.formPattern.includes('{seq')) throw badRequest('양식번호 형식에 {seq} 가 있어야 합니다.');
    const keys = nb.types.map((t) => t.key);
    if (new Set(keys).size !== keys.length) throw badRequest('구분 코드가 겹칩니다.');
  }

  app.get('/settings/numbering', { onRequest: app.auth }, async () => numbering());

  /** 미리보기: 바뀔 번호 목록만 돌려준다 */
  app.post('/settings/numbering/preview', { onRequest: admin, schema: { body: numberingSchema } }, async (req) => {
    checkNumbering(req.body);
    return { changes: await renumber({ query }, req.body, false) };
  });

  /** 저장 + 일괄 적용 */
  app.put('/settings/numbering', { onRequest: admin, schema: { body: numberingSchema } }, async (req) => {
    checkNumbering(req.body);
    return tx(async (db) => {
      const { rows: used } = await db.query('SELECT DISTINCT type FROM documents WHERE deleted_at IS NULL');
      const missing = used.map((r) => r.type).filter((t) => !req.body.types.some((x) => x.key === t));
      if (missing.length) throw badRequest(`사용 중인 구분(${missing.join(', ')})은 지울 수 없습니다.`);
      const old = await numbering(db);
      await setConfig('numbering', req.body, db);
      const changes = await renumber(db, req.body, true);
      await audit(db, req, '번호변경', 'settings', null, `번호 체계 변경 (${changes.length}건 적용)`,
        { changes: { 번호체계: [old, req.body] }, codes: changes.map((c) => [c.from, c.to]) });
      return { changes };
    });
  });

  // ------------------------------------------------------------ 회사 설정 (내보내기 머리글, 결재 직책)
  app.get('/settings/company', { onRequest: app.auth }, async () => getConfig('company', DEFAULT_COMPANY));
  app.put('/settings/company', {
    onRequest: admin,
    schema: {
      body: {
        type: 'object',
        properties: { name: { type: 'string' }, approvalRoles: { type: 'array', items: { type: 'string' } } },
      },
    },
  }, async (req) => {
    const old = await getConfig('company', DEFAULT_COMPANY);
    const next = { ...old, ...req.body };
    await setConfig('company', next);
    await audit({ query }, req, '설정', 'settings', null, '회사 설정', { changes: diffFields(old, next, { name: '회사명', approvalRoles: '결재 직책' }) });
    return next;
  });
}
