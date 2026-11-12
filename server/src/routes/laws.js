// 법령: 직접 입력하고 내용까지 검색
import { query, tx } from '../lib/db.js';
import { notFound, checkVersion, dateOrNull } from '../lib/errors.js';
import { audit, diffFields } from '../lib/core.js';

export const LAW_KINDS = ['법률', '시행령', '시행규칙', '고시·훈령', '규격(ISO 등)', '사내규정', '기타'];
const LABELS = { name: '법령명', kind: '구분', article: '조항', title: '조문 제목', content: '내용', effective_date: '시행일', url: '링크', memo: '메모', docs: '관련 문서' };
const str = { type: ['string', 'null'] };
const body = {
  type: 'object', required: ['name'],
  properties: {
    name: { type: 'string', minLength: 1 }, kind: str, article: str, title: str, content: str,
    effectiveDate: str, url: str, memo: str,
    documentIds: { type: 'array', items: { type: 'integer' } },
    version: { type: 'integer' },
  },
};

export function lawRow(l) {
  return { id: l.id, name: l.name, kind: l.kind, article: l.article, title: l.title, content: l.content,
    effectiveDate: l.effective_date, url: l.url, memo: l.memo, version: l.version, updatedAt: l.updated_at, updatedBy: l.updated_by };
}

async function lawDocs(db, id) {
  const { rows } = await db.query(
    `SELECT d.id, d.code, d.title FROM document_laws x JOIN documents d ON d.id = x.document_id
      WHERE x.law_id = $1 AND d.deleted_at IS NULL ORDER BY d.type, d.num`, [id]);
  return rows;
}

export default async function lawRoutes(app) {
  app.get('/laws/kinds', { onRequest: app.auth }, async () => LAW_KINDS);

  app.get('/laws', { onRequest: app.need('laws', 1) }, async (req) => {
    const q = (req.query.q || '').trim();
    const kind = req.query.kind || '';
    const { rows } = await query(
      `SELECT l.*, (SELECT count(*)::int FROM document_laws x WHERE x.law_id = l.id) AS doc_count
         FROM laws l WHERE l.deleted_at IS NULL AND ($2 = '' OR l.kind = $2)
          AND ($1 = '' OR concat_ws(' ', l.name, l.article, l.title, l.content, l.memo) ILIKE '%' || $1 || '%')
        ORDER BY l.name, l.article NULLS FIRST, l.id`, [q, kind]);
    return rows.map((l) => ({ ...lawRow(l), content: undefined, docCount: l.doc_count }));
  });

  app.get('/laws/:id', { onRequest: app.need('laws', 1) }, async (req) => {
    const id = Number(req.params.id);
    const { rows } = await query('SELECT * FROM laws WHERE id = $1 AND deleted_at IS NULL', [id]);
    if (!rows[0]) throw notFound('법령을 찾을 수 없습니다.');
    return { ...lawRow(rows[0]), documents: await lawDocs({ query }, id) };
  });

  const values = (b) => [b.name.trim(), b.kind ?? null, b.article ?? null, b.title ?? null, b.content ?? null,
    dateOrNull(b.effectiveDate), b.url ?? null, b.memo ?? null];

  async function setDocs(db, id, ids) {
    await db.query('DELETE FROM document_laws WHERE law_id = $1', [id]);
    for (const d of new Set(ids)) await db.query('INSERT INTO document_laws VALUES ($1, $2) ON CONFLICT DO NOTHING', [d, id]);
  }

  app.post('/laws', { onRequest: app.need('laws', 2), schema: { body } }, async (req, reply) => {
    const b = req.body;
    return tx(async (db) => {
      const { rows } = await db.query(
        `INSERT INTO laws (name, kind, article, title, content, effective_date, url, memo, updated_by)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9) RETURNING id`, [...values(b), req.user.name]);
      if (b.documentIds) await setDocs(db, rows[0].id, b.documentIds);
      await audit(db, req, '등록', 'law', rows[0].id, `${b.name} ${b.article || ''}`.trim());
      return reply.status(201).send({ id: rows[0].id });
    });
  });

  app.patch('/laws/:id', { onRequest: app.need('laws', 2), schema: { body } }, async (req) => {
    const id = Number(req.params.id);
    const b = req.body;
    return tx(async (db) => {
      const { rows: o } = await db.query('SELECT * FROM laws WHERE id = $1 AND deleted_at IS NULL FOR UPDATE', [id]);
      if (!o[0]) throw notFound('법령을 찾을 수 없습니다.');
      checkVersion(o[0], b.version, '이 법령');
      const oldDocs = await lawDocs(db, id);
      const v = values(b);
      const after = { name: v[0], kind: v[1], article: v[2], title: v[3], content: v[4], effective_date: v[5], url: v[6], memo: v[7] };
      const ch = diffFields(o[0], after, LABELS);
      if (b.documentIds) {
        const before = oldDocs.map((d) => d.id).sort();
        const next = [...new Set(b.documentIds)].sort();
        if (JSON.stringify(before) !== JSON.stringify(next)) {
          await setDocs(db, id, next);
          const { rows: nd } = await db.query('SELECT code FROM documents WHERE id = ANY($1) ORDER BY type, num', [next]);
          ch['관련 문서'] = [oldDocs.map((d) => d.code).join(', '), nd.map((d) => d.code).join(', ')];
        }
      }
      if (!Object.keys(ch).length) return { id, version: o[0].version, unchanged: true };
      const { rows } = await db.query(
        `UPDATE laws SET name = $2, kind = $3, article = $4, title = $5, content = $6, effective_date = $7, url = $8, memo = $9,
                version = version + 1, updated_at = now(), updated_by = $10 WHERE id = $1 RETURNING version`,
        [id, ...v, req.user.name]);
      await audit(db, req, '수정', 'law', id, `${after.name} ${after.article || ''}`.trim(), { changes: ch });
      return { id, version: rows[0].version };
    });
  });

  app.delete('/laws/:id', { onRequest: app.need('laws', 3) }, async (req) => {
    const id = Number(req.params.id);
    const { rows } = await query('UPDATE laws SET deleted_at = now() WHERE id = $1 AND deleted_at IS NULL RETURNING name, article', [id]);
    if (!rows[0]) throw notFound();
    await audit({ query }, req, '삭제', 'law', id, `${rows[0].name} ${rows[0].article || ''}`.trim());
    return { ok: true };
  });

  /** 문서 화면에서 법령 연결/해제 (문서 수정 권한) */
  app.put('/documents/:id/laws', {
    onRequest: app.need('docs', 2),
    schema: { body: { type: 'object', required: ['lawIds'], properties: { lawIds: { type: 'array', items: { type: 'integer' } } } } },
  }, async (req) => {
    const id = Number(req.params.id);
    return tx(async (db) => {
      const { rows: d } = await db.query('SELECT code, title FROM documents WHERE id = $1 AND deleted_at IS NULL', [id]);
      if (!d[0]) throw notFound();
      const { rows: old } = await db.query(
        `SELECT l.id, l.name, l.article FROM document_laws x JOIN laws l ON l.id = x.law_id WHERE x.document_id = $1 ORDER BY l.id`, [id]);
      await db.query('DELETE FROM document_laws WHERE document_id = $1', [id]);
      const ids = [...new Set(req.body.lawIds)];
      for (const l of ids) await db.query('INSERT INTO document_laws VALUES ($1, $2) ON CONFLICT DO NOTHING', [id, l]);
      const { rows: nl } = await db.query('SELECT name, article FROM laws WHERE id = ANY($1) ORDER BY id', [ids]);
      const fmt = (r) => r.map((x) => `${x.name} ${x.article || ''}`.trim()).join(', ');
      if (fmt(old) !== fmt(nl)) {
        await audit(db, req, '수정', 'document', id, `${d[0].code} ${d[0].title}`, { changes: { '관련 법령': [fmt(old), fmt(nl)] } });
      }
      return { ok: true };
    });
  });
}
