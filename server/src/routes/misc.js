// 변경이력, 통합 검색, 첫 화면
import { query } from '../lib/db.js';
import { requireLevel, today } from '../lib/core.js';

const ENTITY_MODULE = { document: 'docs', form: 'docs', law: 'laws', project: 'projects', item: 'projects' };

function logRow(r) {
  return { id: Number(r.id), at: r.at, userName: r.user_name, action: r.action, entity: r.entity, entityId: r.entity_id,
    label: r.label, projectId: r.project_id, detail: r.detail };
}

export default async function miscRoutes(app) {
  /**
   * 변경이력. 특정 대상(entity+entityId) 또는 프로젝트(projectId) 이력은 그 메뉴 조회 권한으로,
   * 전체 이력은 변경이력 조회 권한으로 본다.
   */
  app.get('/logs', { onRequest: app.auth }, async (req) => {
    const { entity, q } = req.query;
    const entityId = req.query.entityId ? Number(req.query.entityId) : null;
    const projectId = req.query.projectId ? Number(req.query.projectId) : null;
    const limit = Math.min(Number(req.query.limit) || 500, 5000);
    if (projectId) requireLevel(req, 'projects', 1);
    else if (entity && entityId && ENTITY_MODULE[entity]) requireLevel(req, ENTITY_MODULE[entity], 1);
    else requireLevel(req, 'logs', 1);
    const { rows } = await query(
      `SELECT * FROM audit_logs
        WHERE ($1::text IS NULL OR entity = $1) AND ($2::int IS NULL OR entity_id = $2) AND ($3::int IS NULL OR project_id = $3)
          AND ($4 = '' OR concat_ws(' ', label, user_name, action, detail::text) ILIKE '%' || $4 || '%')
        ORDER BY id DESC LIMIT $5`,
      [entity || null, projectId ? null : entityId, projectId, (q || '').trim(), limit]);
    return rows.map(logRow);
  });

  /** 통합 검색: 문서(내용 포함)·양식·법령(조문 포함)·프로젝트 */
  app.get('/search', { onRequest: app.auth }, async (req) => {
    const q = (req.query.q || '').trim();
    if (!q) return [];
    const p = req.user.perms;
    const out = [];
    const snippet = (text) => {
      if (!text) return '';
      const i = text.toLowerCase().indexOf(q.toLowerCase());
      if (i < 0) return '';
      return `…${text.slice(Math.max(0, i - 30), i + q.length + 40).replace(/\s+/g, ' ')}…`;
    };
    if (p.docs >= 1) {
      const { rows } = await query(
        `SELECT id, code, title, data FROM documents WHERE deleted_at IS NULL
           AND (code ILIKE '%' || $1 || '%' OR title ILIKE '%' || $1 || '%' OR data::text ILIKE '%' || $1 || '%')
         ORDER BY type, num LIMIT 100`, [q]);
      for (const r of rows) {
        const flat = [r.data.purpose, r.data.scope, r.data.body, ...(r.data.steps || []).map((s) => `${s.title} ${s.content}`),
          ...(r.data.requirements || []).map((x) => `${x.cat} ${x.no} ${x.name}`)].join(' \n ');
        out.push({ kind: 'document', id: r.id, code: r.code, title: r.title, snippet: snippet(flat) || snippet(`${r.code} ${r.title}`) });
      }
      const { rows: forms } = await query(
        `SELECT f.id, f.code, f.name, d.code AS doc_code FROM forms f JOIN documents d ON d.id = f.document_id
          WHERE f.deleted_at IS NULL AND d.deleted_at IS NULL AND (f.code ILIKE '%' || $1 || '%' OR f.name ILIKE '%' || $1 || '%')
          ORDER BY f.code LIMIT 100`, [q]);
      for (const r of forms) out.push({ kind: 'form', id: r.id, code: r.code, title: r.name, snippet: `양식 · ${r.doc_code}` });
    }
    if (p.laws >= 1) {
      const { rows } = await query(
        `SELECT id, name, article, title, content FROM laws WHERE deleted_at IS NULL
           AND concat_ws(' ', name, article, title, content, memo) ILIKE '%' || $1 || '%' ORDER BY name, article LIMIT 100`, [q]);
      for (const r of rows) out.push({ kind: 'law', id: r.id, code: r.article || '', title: r.name, snippet: snippet(r.content) || r.title || '' });
    }
    if (p.projects >= 1) {
      const { rows } = await query(
        `SELECT id, name, category, due_date FROM projects WHERE deleted_at IS NULL
           AND concat_ws(' ', name, category, description) ILIKE '%' || $1 || '%' ORDER BY id DESC LIMIT 50`, [q]);
      for (const r of rows) out.push({ kind: 'project', id: r.id, code: r.category || '', title: r.name, snippet: r.due_date ? `마감 ${r.due_date}` : '' });
    }
    return out;
  });

  /** 첫 화면: 건수, 기한 임박·지난 항목, 최근 변경 */
  app.get('/dashboard', { onRequest: app.auth }, async (req) => {
    const p = req.user.perms;
    const { rows: c } = await query(
      `SELECT (SELECT count(*)::int FROM documents WHERE deleted_at IS NULL) AS documents,
              (SELECT count(*)::int FROM forms WHERE deleted_at IS NULL) AS forms,
              (SELECT count(*)::int FROM laws WHERE deleted_at IS NULL) AS laws,
              (SELECT count(*)::int FROM projects WHERE deleted_at IS NULL AND status <> '완료') AS projects`);
    let upcoming = [];
    if (p.projects >= 1) {
      const { rows } = await query(
        `SELECT i.id, i.title, i.due_date, i.status, i.assignee, d.name AS department, p.id AS project_id, p.name AS project
           FROM project_items i JOIN projects p ON p.id = i.project_id LEFT JOIN departments d ON d.id = i.department_id
          WHERE i.deleted_at IS NULL AND p.deleted_at IS NULL AND p.status <> '완료'
            AND i.status NOT IN ('완료', '해당없음') AND i.due_date IS NOT NULL AND i.due_date <= ($1::date + 14)
          ORDER BY i.due_date LIMIT 50`, [today()]);
      upcoming = rows.map((r) => ({ id: r.id, title: r.title, dueDate: r.due_date, status: r.status, assignee: r.assignee,
        department: r.department, projectId: r.project_id, project: r.project }));
    }
    let recent = [];
    if (p.logs >= 1) {
      const { rows } = await query('SELECT * FROM audit_logs ORDER BY id DESC LIMIT 15');
      recent = rows.map(logRow);
    }
    return { counts: c[0], upcoming, recent, today: today() };
  });
}
