// 양식(기록)
import { query, tx } from '../lib/db.js';
import { notFound, checkVersion } from '../lib/errors.js';
import { numbering, formCode, audit, diffFields } from '../lib/core.js';

const LABELS = { code: '양식번호', name: '양식명', retention: '보존년한', approval: '결재란', memo: '메모', seq: '순번', doc_code: '소속 문서' };
const body = {
  type: 'object',
  required: ['documentId', 'name'],
  properties: {
    documentId: { type: 'integer' },
    seq: { type: 'integer', minimum: 0 },
    code: { type: 'string' },
    codeManual: { type: 'boolean' },
    name: { type: 'string', minLength: 1 },
    retention: { type: ['string', 'null'] },
    approval: { type: ['string', 'null'] },
    memo: { type: ['string', 'null'] },
    version: { type: 'integer' },
  },
};

const SELECT = `
  SELECT f.*, d.code AS doc_code, d.title AS doc_title, d.type AS doc_type, d.num AS doc_num,
         (SELECT count(*)::int FROM files x WHERE x.owner_type = 'form' AND x.owner_id = f.id AND x.deleted_at IS NULL) AS file_count,
         (SELECT x.id FROM files x WHERE x.owner_type = 'form' AND x.owner_id = f.id AND x.deleted_at IS NULL ORDER BY x.id DESC LIMIT 1) AS latest_file_id
    FROM forms f JOIN documents d ON d.id = f.document_id
   WHERE f.deleted_at IS NULL AND d.deleted_at IS NULL`;

export function formRow(f) {
  return {
    id: f.id, documentId: f.document_id, docCode: f.doc_code, docTitle: f.doc_title, seq: f.seq, code: f.code,
    codeManual: f.code_manual, name: f.name, retention: f.retention, approval: f.approval, memo: f.memo,
    fileCount: f.file_count, latestFileId: f.latest_file_id, version: f.version, updatedAt: f.updated_at, updatedBy: f.updated_by,
  };
}

export default async function formRoutes(app) {
  app.get('/forms', { onRequest: app.need('docs', 1) }, async (req) => {
    const q = (req.query.q || '').trim();
    const { rows } = await query(
      `${SELECT} AND ($1 = '' OR f.code ILIKE '%' || $1 || '%' OR f.name ILIKE '%' || $1 || '%' OR d.code ILIKE '%' || $1 || '%' OR d.title ILIKE '%' || $1 || '%')
       ORDER BY d.type, d.num, f.seq, f.id`, [q]);
    return rows.map(formRow);
  });

  app.get('/forms/:id', { onRequest: app.need('docs', 1) }, async (req) => {
    const id = Number(req.params.id);
    const { rows } = await query(`${SELECT} AND f.id = $1`, [id]);
    if (!rows[0]) throw notFound('양식을 찾을 수 없습니다.');
    const { rows: usedBy } = await query(
      `SELECT d.id, d.code, d.title FROM document_forms l JOIN documents d ON d.id = l.document_id
        WHERE l.form_id = $1 AND d.deleted_at IS NULL ORDER BY d.type, d.num`, [id]);
    return { ...formRow(rows[0]), usedBy };
  });

  app.post('/forms', { onRequest: app.need('docs', 2), schema: { body } }, async (req, reply) => {
    const b = req.body;
    return tx(async (db) => {
      const { rows: d } = await db.query('SELECT code FROM documents WHERE id = $1 AND deleted_at IS NULL', [b.documentId]);
      if (!d[0]) throw notFound('소속 문서를 찾을 수 없습니다.');
      let seq = b.seq;
      if (seq === undefined) {
        const { rows } = await db.query('SELECT COALESCE(MAX(seq), 0) + 1 AS n FROM forms WHERE document_id = $1 AND deleted_at IS NULL', [b.documentId]);
        seq = rows[0].n;
      }
      const code = b.codeManual && b.code ? b.code.trim() : formCode(await numbering(db), d[0].code, seq);
      const { rows } = await db.query(
        `INSERT INTO forms (document_id, seq, code, code_manual, name, retention, approval, memo, updated_by)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9) RETURNING id`,
        [b.documentId, seq, code, !!b.codeManual, b.name.trim(), b.retention ?? null, b.approval ?? null, b.memo ?? null, req.user.name]);
      await db.query('INSERT INTO document_forms VALUES ($1, $2) ON CONFLICT DO NOTHING', [b.documentId, rows[0].id]);
      await audit(db, req, '등록', 'form', rows[0].id, `${code} ${b.name.trim()}`);
      return reply.status(201).send({ id: rows[0].id, code });
    });
  });

  app.patch('/forms/:id', { onRequest: app.need('docs', 2), schema: { body } }, async (req) => {
    const id = Number(req.params.id);
    const b = req.body;
    return tx(async (db) => {
      const { rows: lock } = await db.query('SELECT * FROM forms WHERE id = $1 AND deleted_at IS NULL FOR UPDATE', [id]);
      if (!lock[0]) throw notFound('양식을 찾을 수 없습니다.');
      checkVersion(lock[0], b.version, '이 양식');
      const { rows: o } = await db.query(`${SELECT} AND f.id = $1`, [id]);
      const old = o[0];
      const { rows: d } = await db.query('SELECT code FROM documents WHERE id = $1 AND deleted_at IS NULL', [b.documentId]);
      if (!d[0]) throw notFound('소속 문서를 찾을 수 없습니다.');
      const seq = b.seq ?? old.seq;
      const code = b.codeManual && b.code ? b.code.trim() : formCode(await numbering(db), d[0].code, seq);
      const after = { code, name: b.name.trim(), retention: b.retention ?? null, approval: b.approval ?? null, memo: b.memo ?? null, seq, doc_code: d[0].code };
      const ch = diffFields(old, after, LABELS);
      if (!!b.codeManual !== old.code_manual) ch['번호 직접지정'] = [old.code_manual, !!b.codeManual];
      if (!Object.keys(ch).length) return { id, code, version: old.version, unchanged: true };
      const { rows } = await db.query(
        `UPDATE forms SET document_id = $2, seq = $3, code = $4, code_manual = $5, name = $6, retention = $7, approval = $8, memo = $9,
                version = version + 1, updated_at = now(), updated_by = $10 WHERE id = $1 RETURNING version`,
        [id, b.documentId, seq, code, !!b.codeManual, after.name, after.retention, after.approval, after.memo, req.user.name]);
      if (b.documentId !== old.document_id) {
        await db.query('DELETE FROM document_forms WHERE document_id = $1 AND form_id = $2', [old.document_id, id]);
        await db.query('INSERT INTO document_forms VALUES ($1, $2) ON CONFLICT DO NOTHING', [b.documentId, id]);
      }
      await audit(db, req, '수정', 'form', id, `${code} ${after.name}`, { changes: ch });
      return { id, code, version: rows[0].version };
    });
  });

  app.delete('/forms/:id', { onRequest: app.need('docs', 3) }, async (req) => {
    const id = Number(req.params.id);
    const { rows } = await query('UPDATE forms SET deleted_at = now(), updated_by = $2 WHERE id = $1 AND deleted_at IS NULL RETURNING code, name',
      [id, req.user.name]);
    if (!rows[0]) throw notFound();
    await audit({ query }, req, '삭제', 'form', id, `${rows[0].code} ${rows[0].name}`);
    return { ok: true };
  });
}
