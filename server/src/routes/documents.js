// 업무표준 문서 (매뉴얼·프로세스·지침)
import { query, tx } from '../lib/db.js';
import { badRequest, notFound, checkVersion } from '../lib/errors.js';
import { numbering, docCode, formCode, audit, diffFields } from '../lib/core.js';

export const DATA_LABELS = {
  purpose: '목적', scope: '적용범위', resources: '프로세스 자원', requirements: '요구사항', kpis: '성과지표',
  mainSteps: '주요업무절차', steps: '세부 업무절차·전결권한', body: '본문', approvalLine: '결재라인',
  related: '관련 프로세스', revisions: '개정이력', deptNote: '부서 비고',
};
const DOC_LABELS = { type: '구분', num: '번호', code: '문서번호', code_manual: '번호 직접지정', title: '문서명', department: '주관부서' };

const docBody = {
  type: 'object',
  required: ['type', 'title'],
  properties: {
    type: { type: 'string', minLength: 1 },
    num: { type: 'integer', minimum: 0 },
    code: { type: 'string' },
    codeManual: { type: 'boolean' },
    title: { type: 'string', minLength: 1 },
    departmentId: { type: ['integer', 'null'] },
    data: { type: 'object' },
    version: { type: 'integer' },
  },
};

export function docRow(r) {
  return {
    id: r.id, type: r.type, num: r.num, code: r.code, codeManual: r.code_manual, title: r.title,
    departmentId: r.department_id, department: r.department ?? null, version: r.version,
    updatedAt: r.updated_at, updatedBy: r.updated_by,
  };
}

export async function loadDocument(id, db = { query }) {
  const { rows } = await db.query(
    `SELECT d.*, p.name AS department FROM documents d LEFT JOIN departments p ON p.id = d.department_id
      WHERE d.id = $1 AND d.deleted_at IS NULL`, [id]);
  return rows[0] || null;
}

/** 문서에 연결된 양식 (소속 + 다른 문서 양식 연결) */
export async function documentForms(id, db = { query }) {
  const { rows } = await db.query(
    `SELECT f.*, d.code AS doc_code, d.title AS doc_title,
            (SELECT count(*)::int FROM files x WHERE x.owner_type = 'form' AND x.owner_id = f.id AND x.deleted_at IS NULL) AS file_count,
            (SELECT x.id FROM files x WHERE x.owner_type = 'form' AND x.owner_id = f.id AND x.deleted_at IS NULL ORDER BY x.id DESC LIMIT 1) AS latest_file_id
       FROM document_forms l JOIN forms f ON f.id = l.form_id JOIN documents d ON d.id = f.document_id
      WHERE l.document_id = $1 AND f.deleted_at IS NULL
      ORDER BY (f.document_id <> $1), f.seq, f.code`, [id]);
  return rows;
}

export default async function documentRoutes(app) {
  app.get('/documents', { onRequest: app.need('docs', 1) }, async (req) => {
    const q = (req.query.q || '').trim();
    const { rows } = await query(
      `SELECT d.id, d.type, d.num, d.code, d.code_manual, d.title, d.department_id, d.version, d.updated_at, d.updated_by,
              p.name AS department
         FROM documents d LEFT JOIN departments p ON p.id = d.department_id
        WHERE d.deleted_at IS NULL
          AND ($1 = '' OR d.code ILIKE '%' || $1 || '%' OR d.title ILIKE '%' || $1 || '%' OR d.data::text ILIKE '%' || $1 || '%')
        ORDER BY d.type, d.num, d.id`, [q]);
    return rows.map(docRow);
  });

  app.get('/documents/:id', { onRequest: app.need('docs', 1) }, async (req) => {
    const id = Number(req.params.id);
    const d = await loadDocument(id);
    if (!d) throw notFound('문서를 찾을 수 없습니다.');
    const forms = await documentForms(id);
    const { rows: laws } = await query(
      `SELECT l.id, l.name, l.kind, l.article, l.title, l.effective_date FROM document_laws x JOIN laws l ON l.id = x.law_id
        WHERE x.document_id = $1 AND l.deleted_at IS NULL ORDER BY l.name, l.article`, [id]);
    const relIds = (d.data.related || []).map(Number).filter(Number.isInteger);
    const { rows: related } = await query(
      'SELECT id, code, title FROM documents WHERE id = ANY($1) AND deleted_at IS NULL', [relIds]);
    const relSorted = relIds.map((r) => related.find((x) => x.id === r)).filter(Boolean);
    const { rows: refBy } = await query(
      `SELECT id, code, title FROM documents WHERE deleted_at IS NULL AND data->'related' @> $1::jsonb ORDER BY type, num`,
      [JSON.stringify([id])]);
    const { rows: files } = await query(
      `SELECT count(*)::int AS c FROM files WHERE owner_type = 'document' AND owner_id = $1 AND deleted_at IS NULL`, [id]);
    return {
      ...docRow(d),
      data: d.data,
      forms: forms.map((f) => ({
        id: f.id, code: f.code, name: f.name, retention: f.retention, approval: f.approval, documentId: f.document_id,
        docCode: f.doc_code, own: f.document_id === id, fileCount: f.file_count, latestFileId: f.latest_file_id,
      })),
      laws,
      related: relSorted,
      referencedBy: refBy,
      fileCount: files[0].c,
    };
  });

  app.post('/documents', { onRequest: app.need('docs', 2), schema: { body: docBody } }, async (req, reply) => {
    const b = req.body;
    const nb = await numbering();
    if (!nb.types.some((t) => t.key === b.type)) throw badRequest('알 수 없는 구분입니다.');
    let num = b.num;
    if (num === undefined) {
      const { rows } = await query('SELECT COALESCE(MAX(num), 0) + 1 AS n FROM documents WHERE type = $1 AND deleted_at IS NULL', [b.type]);
      num = rows[0].n;
    }
    const code = b.codeManual && b.code ? b.code.trim() : docCode(nb, b.type, num);
    const data = b.data || {};
    const id = await tx(async (db) => {
      const { rows } = await db.query(
        `INSERT INTO documents (type, num, code, code_manual, title, department_id, data, updated_by)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8) RETURNING id`,
        [b.type, num, code, !!b.codeManual, b.title.trim(), b.departmentId ?? null, JSON.stringify(data), req.user.name]);
      await audit(db, req, '등록', 'document', rows[0].id, `${code} ${b.title.trim()}`);
      return rows[0].id;
    });
    return reply.status(201).send({ id, code });
  });

  app.patch('/documents/:id', { onRequest: app.need('docs', 2), schema: { body: docBody } }, async (req) => {
    const id = Number(req.params.id);
    const b = req.body;
    return tx(async (db) => {
      const { rows: lock } = await db.query('SELECT * FROM documents WHERE id = $1 AND deleted_at IS NULL FOR UPDATE', [id]);
      if (!lock[0]) throw notFound('문서를 찾을 수 없습니다.');
      checkVersion(lock[0], b.version, '이 문서');
      const old = await loadDocument(id, db);
      const nb = await numbering(db);
      if (!nb.types.some((t) => t.key === b.type)) throw badRequest('알 수 없는 구분입니다.');
      const num = b.num ?? old.num;
      const code = b.codeManual && b.code ? b.code.trim() : docCode(nb, b.type, num);
      const data = b.data ?? old.data;
      const { rows: dn } = await db.query('SELECT name FROM departments WHERE id = $1', [b.departmentId ?? null]);
      const after = { type: b.type, num, code, code_manual: !!b.codeManual, title: b.title.trim(), department: dn[0]?.name ?? null };
      const ch = { ...diffFields(old, after, DOC_LABELS), ...diffFields(old.data, data, DATA_LABELS) };
      if (!Object.keys(ch).length) return { id, code, version: old.version, unchanged: true };
      const { rows } = await db.query(
        `UPDATE documents SET type = $2, num = $3, code = $4, code_manual = $5, title = $6, department_id = $7, data = $8,
                version = version + 1, updated_at = now(), updated_by = $9
          WHERE id = $1 RETURNING version`,
        [id, b.type, num, code, !!b.codeManual, b.title.trim(), b.departmentId ?? null, JSON.stringify(data), req.user.name]);
      // 문서번호가 바뀌면 소속 양식 번호도 따라 바꾼다 (직접 지정한 양식 제외)
      const formChanges = [];
      if (code !== old.code) {
        const { rows: fs } = await db.query('SELECT id, seq, code FROM forms WHERE document_id = $1 AND deleted_at IS NULL AND NOT code_manual', [id]);
        for (const f of fs) {
          const fc = formCode(nb, code, f.seq);
          if (fc !== f.code) {
            await db.query('UPDATE forms SET code = $2 WHERE id = $1', [f.id, fc]);
            formChanges.push([f.code, fc]);
          }
        }
      }
      await audit(db, req, '수정', 'document', id, `${code} ${after.title}`, { changes: ch, codes: formChanges.length ? formChanges : undefined });
      return { id, code, version: rows[0].version };
    });
  });

  app.delete('/documents/:id', { onRequest: app.need('docs', 3) }, async (req) => {
    const id = Number(req.params.id);
    return tx(async (db) => {
      const { rows } = await db.query('UPDATE documents SET deleted_at = now(), updated_by = $2 WHERE id = $1 AND deleted_at IS NULL RETURNING code, title',
        [id, req.user.name]);
      if (!rows[0]) throw notFound();
      await db.query('UPDATE forms SET deleted_at = now() WHERE document_id = $1 AND deleted_at IS NULL', [id]);
      await audit(db, req, '삭제', 'document', id, `${rows[0].code} ${rows[0].title}`, { note: '소속 양식도 함께 삭제됨' });
      return { ok: true };
    });
  });

  /** 다른 문서의 양식을 이 문서에 연결 / 해제 */
  app.put('/documents/:id/forms/:formId', { onRequest: app.need('docs', 2) }, async (req) => {
    const id = Number(req.params.id);
    const formId = Number(req.params.formId);
    const d = await loadDocument(id);
    const { rows: f } = await query('SELECT code FROM forms WHERE id = $1 AND deleted_at IS NULL', [formId]);
    if (!d || !f[0]) throw notFound();
    await query('INSERT INTO document_forms VALUES ($1, $2) ON CONFLICT DO NOTHING', [id, formId]);
    await audit({ query }, req, '수정', 'document', id, `${d.code} ${d.title}`, { changes: { '관련 양식 연결': [null, f[0].code] } });
    return { ok: true };
  });
  app.delete('/documents/:id/forms/:formId', { onRequest: app.need('docs', 2) }, async (req) => {
    const id = Number(req.params.id);
    const formId = Number(req.params.formId);
    const d = await loadDocument(id);
    const { rows: f } = await query('SELECT code, document_id FROM forms WHERE id = $1', [formId]);
    if (!d || !f[0]) throw notFound();
    if (f[0].document_id === id) throw badRequest('이 문서 소속 양식은 연결 해제할 수 없습니다. 양식 메뉴에서 삭제하거나 소속 문서를 바꾸세요.');
    await query('DELETE FROM document_forms WHERE document_id = $1 AND form_id = $2', [id, formId]);
    await audit({ query }, req, '수정', 'document', id, `${d.code} ${d.title}`, { changes: { '관련 양식 연결': [f[0].code, null] } });
    return { ok: true };
  });
}
