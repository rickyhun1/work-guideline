// 프로젝트: 지원사업 신청·인증심사 등 건별로 참여부서·필요서류·기한 공유
import { query, tx } from '../lib/db.js';
import { notFound, checkVersion, dateOrNull } from '../lib/errors.js';
import { audit, diffFields } from '../lib/core.js';

export const PROJECT_STATUS = ['준비', '진행중', '완료', '보류'];
export const ITEM_STATUS = ['미착수', '작성중', '검토중', '완료', '해당없음'];
export const CATEGORIES = ['지원사업 신청', '인증심사(외부)', '내부심사', '고객 감사', '법정 신고·보고', '기타'];

const str = { type: ['string', 'null'] };
const pBody = {
  type: 'object', required: ['name'],
  properties: {
    name: { type: 'string', minLength: 1 }, category: str, description: str, owner: str,
    startDate: str, dueDate: str, status: { enum: PROJECT_STATUS },
    departments: { type: 'array', items: { type: 'integer' } }, version: { type: 'integer' },
  },
};
const iBody = {
  type: 'object', required: ['title'],
  properties: {
    title: { type: 'string', minLength: 1 }, departmentId: { type: ['integer', 'null'] }, assignee: str,
    dueDate: str, status: { enum: ITEM_STATUS }, formId: { type: ['integer', 'null'] }, documentId: { type: ['integer', 'null'] },
    note: str, sortOrder: { type: 'integer' }, version: { type: 'integer' },
  },
};
const P_LABELS = { name: '프로젝트명', category: '분류', description: '설명', owner: '총괄 담당', start_date: '시작일', due_date: '마감일', status: '상태', departments: '참여부서' };
const I_LABELS = { title: '항목', department: '담당부서', assignee: '담당자', due_date: '기한', status: '상태', form: '연결 양식', document: '관련 문서', note: '비고', sort_order: '순서' };

export async function loadItems(db, projectId) {
  const { rows } = await db.query(
    `SELECT i.*, d.name AS department, f.code AS form_code, f.name AS form_name, c.code AS doc_code, c.title AS doc_title,
            (SELECT x.id FROM files x WHERE x.owner_type = 'form' AND x.owner_id = i.form_id AND x.deleted_at IS NULL ORDER BY x.id DESC LIMIT 1) AS form_file_id,
            (SELECT count(*)::int FROM files x WHERE x.owner_type = 'item' AND x.owner_id = i.id AND x.deleted_at IS NULL) AS file_count
       FROM project_items i LEFT JOIN departments d ON d.id = i.department_id
       LEFT JOIN forms f ON f.id = i.form_id AND f.deleted_at IS NULL LEFT JOIN documents c ON c.id = i.document_id AND c.deleted_at IS NULL
      WHERE i.project_id = $1 AND i.deleted_at IS NULL ORDER BY i.sort_order, i.due_date NULLS LAST, i.id`, [projectId]);
  return rows.map(itemRow);
}
function itemRow(i) {
  return {
    id: i.id, projectId: i.project_id, title: i.title, departmentId: i.department_id, department: i.department, assignee: i.assignee,
    dueDate: i.due_date, status: i.status, formId: i.form_id, formCode: i.form_code, formName: i.form_name, formFileId: i.form_file_id,
    documentId: i.document_id, docCode: i.doc_code, docTitle: i.doc_title, note: i.note, sortOrder: i.sort_order,
    fileCount: i.file_count, version: i.version, updatedAt: i.updated_at, updatedBy: i.updated_by,
  };
}
function projectRow(p) {
  return {
    id: p.id, name: p.name, category: p.category, description: p.description, owner: p.owner, startDate: p.start_date,
    dueDate: p.due_date, status: p.status, departments: p.departments, version: p.version, updatedAt: p.updated_at,
    updatedBy: p.updated_by, itemCount: p.item_count, doneCount: p.done_count,
  };
}
async function deptNames(db, ids) {
  if (!ids?.length) return '';
  const { rows } = await db.query('SELECT name FROM departments WHERE id = ANY($1) ORDER BY sort_order, id', [ids]);
  return rows.map((r) => r.name).join(', ');
}

export default async function projectRoutes(app) {
  app.get('/projects/options', { onRequest: app.auth }, async () => ({ status: PROJECT_STATUS, itemStatus: ITEM_STATUS, categories: CATEGORIES }));

  app.get('/projects', { onRequest: app.need('projects', 1) }, async () => {
    const { rows } = await query(
      `SELECT p.*,
              (SELECT count(*)::int FROM project_items i WHERE i.project_id = p.id AND i.deleted_at IS NULL) AS item_count,
              (SELECT count(*)::int FROM project_items i WHERE i.project_id = p.id AND i.deleted_at IS NULL AND i.status IN ('완료', '해당없음')) AS done_count
         FROM projects p WHERE p.deleted_at IS NULL
        ORDER BY (p.status = '완료'), p.due_date NULLS LAST, p.id DESC`);
    return rows.map(projectRow);
  });

  app.get('/projects/:id', { onRequest: app.need('projects', 1) }, async (req) => {
    const id = Number(req.params.id);
    const { rows } = await query('SELECT * FROM projects WHERE id = $1 AND deleted_at IS NULL', [id]);
    if (!rows[0]) throw notFound('프로젝트를 찾을 수 없습니다.');
    const items = await loadItems({ query }, id);
    return { ...projectRow(rows[0]), departmentNames: await deptNames({ query }, rows[0].departments), items };
  });

  const pValues = (b) => [b.name.trim(), b.category ?? null, b.description ?? null, b.owner ?? null,
    dateOrNull(b.startDate), dateOrNull(b.dueDate), b.status ?? '준비', b.departments ?? []];

  app.post('/projects', { onRequest: app.need('projects', 2), schema: { body: pBody } }, async (req, reply) => {
    const { rows } = await query(
      `INSERT INTO projects (name, category, description, owner, start_date, due_date, status, departments, updated_by)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9) RETURNING id`, [...pValues(req.body), req.user.name]);
    await audit({ query }, req, '등록', 'project', rows[0].id, req.body.name.trim(), {}, rows[0].id);
    return reply.status(201).send({ id: rows[0].id });
  });

  app.patch('/projects/:id', { onRequest: app.need('projects', 2), schema: { body: pBody } }, async (req) => {
    const id = Number(req.params.id);
    return tx(async (db) => {
      const { rows: o } = await db.query('SELECT * FROM projects WHERE id = $1 AND deleted_at IS NULL FOR UPDATE', [id]);
      if (!o[0]) throw notFound();
      checkVersion(o[0], req.body.version, '이 프로젝트');
      const v = pValues(req.body);
      const before = { ...o[0], departments: await deptNames(db, o[0].departments) };
      const after = { name: v[0], category: v[1], description: v[2], owner: v[3], start_date: v[4], due_date: v[5], status: v[6], departments: await deptNames(db, v[7]) };
      const ch = diffFields(before, after, P_LABELS);
      if (!Object.keys(ch).length) return { id, version: o[0].version, unchanged: true };
      const { rows } = await db.query(
        `UPDATE projects SET name = $2, category = $3, description = $4, owner = $5, start_date = $6, due_date = $7, status = $8,
                departments = $9, version = version + 1, updated_at = now(), updated_by = $10 WHERE id = $1 RETURNING version`,
        [id, ...v, req.user.name]);
      await audit(db, req, '수정', 'project', id, after.name, { changes: ch }, id);
      return { id, version: rows[0].version };
    });
  });

  app.delete('/projects/:id', { onRequest: app.need('projects', 3) }, async (req) => {
    const id = Number(req.params.id);
    const { rows } = await query('UPDATE projects SET deleted_at = now() WHERE id = $1 AND deleted_at IS NULL RETURNING name', [id]);
    if (!rows[0]) throw notFound();
    await audit({ query }, req, '삭제', 'project', id, rows[0].name, {}, id);
    return { ok: true };
  });

  /** 복제: 같은 형태의 프로젝트를 새로 시작 (항목은 '미착수'로, 첨부는 복사하지 않음) */
  app.post('/projects/:id/copy', { onRequest: app.need('projects', 2) }, async (req, reply) => {
    const id = Number(req.params.id);
    return tx(async (db) => {
      const { rows: o } = await db.query('SELECT * FROM projects WHERE id = $1 AND deleted_at IS NULL', [id]);
      if (!o[0]) throw notFound();
      const name = `${o[0].name} (복사본)`;
      const { rows } = await db.query(
        `INSERT INTO projects (name, category, description, owner, start_date, due_date, status, departments, updated_by)
         VALUES ($1, $2, $3, $4, NULL, NULL, '준비', $5, $6) RETURNING id`,
        [name, o[0].category, o[0].description, o[0].owner, o[0].departments, req.user.name]);
      const nid = rows[0].id;
      await db.query(
        `INSERT INTO project_items (project_id, title, department_id, assignee, due_date, status, form_id, document_id, note, sort_order, updated_by)
         SELECT $1, title, department_id, assignee, NULL, '미착수', form_id, document_id, note, sort_order, $3
           FROM project_items WHERE project_id = $2 AND deleted_at IS NULL`, [nid, id, req.user.name]);
      await audit(db, req, '등록', 'project', nid, name, { note: `"${o[0].name}"에서 복제` }, nid);
      return reply.status(201).send({ id: nid });
    });
  });

  // ------------------------------------------------------------ 항목
  const iValues = (b) => [b.title.trim(), b.departmentId ?? null, b.assignee ?? null, dateOrNull(b.dueDate), b.status ?? '미착수',
    b.formId ?? null, b.documentId ?? null, b.note ?? null, b.sortOrder ?? 0];

  async function itemView(db, row) {
    const { rows: d } = await db.query('SELECT name FROM departments WHERE id = $1', [row.department_id]);
    const { rows: f } = await db.query('SELECT code FROM forms WHERE id = $1', [row.form_id]);
    const { rows: c } = await db.query('SELECT code FROM documents WHERE id = $1', [row.document_id]);
    return { ...row, department: d[0]?.name ?? null, form: f[0]?.code ?? null, document: c[0]?.code ?? null };
  }

  app.post('/projects/:id/items', { onRequest: app.need('projects', 2), schema: { body: iBody } }, async (req, reply) => {
    const pid = Number(req.params.id);
    return tx(async (db) => {
      const { rows: p } = await db.query('SELECT name FROM projects WHERE id = $1 AND deleted_at IS NULL', [pid]);
      if (!p[0]) throw notFound();
      const { rows } = await db.query(
        `INSERT INTO project_items (project_id, title, department_id, assignee, due_date, status, form_id, document_id, note, sort_order, updated_by)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11) RETURNING id`, [pid, ...iValues(req.body), req.user.name]);
      await audit(db, req, '등록', 'item', rows[0].id, `[${p[0].name}] ${req.body.title.trim()}`, {}, pid);
      return reply.status(201).send({ id: rows[0].id });
    });
  });

  app.patch('/items/:id', { onRequest: app.need('projects', 2), schema: { body: iBody } }, async (req) => {
    const id = Number(req.params.id);
    return tx(async (db) => {
      const { rows: o } = await db.query('SELECT * FROM project_items WHERE id = $1 AND deleted_at IS NULL FOR UPDATE', [id]);
      if (!o[0]) throw notFound();
      checkVersion(o[0], req.body.version, '이 항목');
      const v = iValues(req.body);
      const next = { ...o[0], title: v[0], department_id: v[1], assignee: v[2], due_date: v[3], status: v[4], form_id: v[5], document_id: v[6], note: v[7], sort_order: v[8] };
      const ch = diffFields(await itemView(db, o[0]), await itemView(db, next), I_LABELS);
      if (!Object.keys(ch).length) return { id, version: o[0].version, unchanged: true };
      const { rows } = await db.query(
        `UPDATE project_items SET title = $2, department_id = $3, assignee = $4, due_date = $5, status = $6, form_id = $7,
                document_id = $8, note = $9, sort_order = $10, version = version + 1, updated_at = now(), updated_by = $11
          WHERE id = $1 RETURNING version`, [id, ...v, req.user.name]);
      const { rows: p } = await db.query('SELECT name FROM projects WHERE id = $1', [o[0].project_id]);
      await audit(db, req, '수정', 'item', id, `[${p[0].name}] ${v[0]}`, { changes: ch }, o[0].project_id);
      return { id, version: rows[0].version };
    });
  });

  app.delete('/items/:id', { onRequest: app.need('projects', 3) }, async (req) => {
    const id = Number(req.params.id);
    const { rows } = await query('UPDATE project_items SET deleted_at = now() WHERE id = $1 AND deleted_at IS NULL RETURNING title, project_id', [id]);
    if (!rows[0]) throw notFound();
    await audit({ query }, req, '삭제', 'item', id, rows[0].title, {}, rows[0].project_id);
    return { ok: true };
  });
}
