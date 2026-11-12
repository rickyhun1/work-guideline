// 내보내기: 개별 파일, 목록표, 선택 항목 묶음(zip)
import path from 'node:path';
import { zipSync } from 'fflate';
import { query } from '../lib/db.js';
import { badRequest, notFound } from '../lib/errors.js';
import { numbering, getConfig, DEFAULT_COMPANY, requireLevel, audit } from '../lib/core.js';
import { documentWorkbook, documentListWorkbook, formListWorkbook, lawWorkbook, projectWorkbook } from '../lib/xlsx.js';
import { loadDocument, documentForms } from './documents.js';
import { loadItems } from './projects.js';
import { readStored, sendFile } from './files.js';

const XLSX = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

/** 파일·폴더 이름에 못 쓰는 글자 정리 */
export function safeName(s, max = 80) {
  return String(s ?? '').replace(/[\\/:*?"<>|\r\n\t]+/g, '_').replace(/\s+/g, ' ').trim().slice(0, max) || '_';
}
const ext = (f) => path.extname(f.filename) || '';

async function docXlsx(id, nb, company) {
  const d = await loadDocument(id);
  if (!d) return null;
  const forms = await documentForms(id);
  const relIds = (d.data.related || []).map(Number);
  const { rows: rel } = await query('SELECT id, code, title FROM documents WHERE id = ANY($1) AND deleted_at IS NULL', [relIds]);
  const related = relIds.map((r) => rel.find((x) => x.id === r)).filter(Boolean);
  const { rows: laws } = await query(
    `SELECT l.name, l.article, l.title FROM document_laws x JOIN laws l ON l.id = x.law_id
      WHERE x.document_id = $1 AND l.deleted_at IS NULL ORDER BY l.name, l.article`, [id]);
  const typeLabel = nb.types.find((t) => t.key === d.type)?.label || d.type;
  const buf = Buffer.from(await documentWorkbook({ ...d, typeLabel }, forms, related, laws, company));
  return { doc: d, forms, typeLabel, buf, filename: `${safeName(`${d.code} ${d.title}`)}.xlsx` };
}

async function latestFile(ownerType, ownerId) {
  const { rows } = await query(
    'SELECT * FROM files WHERE owner_type = $1 AND owner_id = $2 AND deleted_at IS NULL ORDER BY id DESC LIMIT 1', [ownerType, ownerId]);
  return rows[0] || null;
}
async function allFiles(ownerType, ownerId) {
  const { rows } = await query(
    'SELECT * FROM files WHERE owner_type = $1 AND owner_id = $2 AND deleted_at IS NULL ORDER BY id DESC', [ownerType, ownerId]);
  return rows;
}

async function documentListRows(ids) {
  const nb = await numbering();
  const { rows } = await query(
    `SELECT d.*, p.name AS department FROM documents d LEFT JOIN departments p ON p.id = d.department_id
      WHERE d.deleted_at IS NULL AND ($1::int[] IS NULL OR d.id = ANY($1)) ORDER BY d.type, d.num, d.id`, [ids]);
  const out = [];
  for (const d of rows) {
    const forms = await documentForms(d.id);
    const last = (d.data.revisions || []).slice(-1)[0] || {};
    out.push([nb.types.find((t) => t.key === d.type)?.label || d.type, d.code, d.title, d.department || d.data.deptNote || '',
      last.rev || '', last.date || '', forms.map((f) => `${f.code} ${f.name}`).join('\n')]);
  }
  return out;
}

async function lawRows(ids) {
  const { rows } = await query(
    `SELECT l.*, (SELECT string_agg(d.code, ', ' ORDER BY d.type, d.num) FROM document_laws x JOIN documents d ON d.id = x.document_id
                   WHERE x.law_id = l.id AND d.deleted_at IS NULL) AS docs
       FROM laws l WHERE l.deleted_at IS NULL AND ($1::int[] IS NULL OR l.id = ANY($1)) ORDER BY l.name, l.article`, [ids]);
  return rows.map((l) => [l.name, l.kind, l.article, l.title, l.content, l.effective_date, l.docs, l.memo, l.url]);
}

async function projectData(id) {
  const { rows } = await query('SELECT * FROM projects WHERE id = $1 AND deleted_at IS NULL', [id]);
  if (!rows[0]) return null;
  const p = rows[0];
  const { rows: dn } = await query('SELECT string_agg(name, \', \' ORDER BY sort_order, id) AS n FROM departments WHERE id = ANY($1)', [p.departments]);
  return {
    p: { name: p.name, category: p.category, status: p.status, startDate: p.start_date, dueDate: p.due_date, owner: p.owner,
      description: p.description, departmentNames: dn[0]?.n || '' },
    items: await loadItems({ query }, id),
  };
}

const ids = (v) => (Array.isArray(v) && v.length ? v.map(Number).filter(Number.isInteger) : null);

export default async function exportRoutes(app) {
  app.get('/export/documents/:id', { onRequest: app.need('docs', 1) }, async (req, reply) => {
    const x = await docXlsx(Number(req.params.id), await numbering(), await getConfig('company', DEFAULT_COMPANY));
    if (!x) throw notFound('문서를 찾을 수 없습니다.');
    return sendFile(reply, x.filename, x.buf, XLSX);
  });

  /** 양식 최신 파일을 현재 번호·이름으로 */
  app.get('/export/forms/:id', { onRequest: app.need('docs', 1) }, async (req, reply) => {
    const { rows } = await query('SELECT * FROM forms WHERE id = $1 AND deleted_at IS NULL', [Number(req.params.id)]);
    if (!rows[0]) throw notFound('양식을 찾을 수 없습니다.');
    const f = await latestFile('form', rows[0].id);
    if (!f) throw notFound('이 양식에는 아직 파일이 없습니다.');
    return sendFile(reply, `${safeName(`${rows[0].code} ${rows[0].name}`)}${ext(f)}`, await readStored(f));
  });

  app.get('/export/lists/documents', { onRequest: app.need('docs', 1) }, async (req, reply) => {
    const buf = Buffer.from(await documentListWorkbook(await documentListRows(null), await getConfig('company', DEFAULT_COMPANY)));
    return sendFile(reply, '업무표준 문서 목록표.xlsx', buf, XLSX);
  });

  app.get('/export/lists/forms', { onRequest: app.need('docs', 1) }, async (req, reply) => {
    const { rows } = await query(
      `SELECT f.*, d.code AS dc, d.title AS dt, (SELECT count(*)::int FROM files x WHERE x.owner_type = 'form' AND x.owner_id = f.id AND x.deleted_at IS NULL) AS n
         FROM forms f JOIN documents d ON d.id = f.document_id WHERE f.deleted_at IS NULL AND d.deleted_at IS NULL ORDER BY d.type, d.num, f.seq`);
    const buf = Buffer.from(await formListWorkbook(rows.map((f) => [f.code, f.name, `${f.dc} ${f.dt}`, f.retention, f.approval, f.n ? `${f.n}개` : '없음'])));
    return sendFile(reply, '양식 목록.xlsx', buf, XLSX);
  });

  /** 법령 목록 (ids=1,2,3 없으면 전체) */
  app.get('/export/laws', { onRequest: app.need('laws', 1) }, async (req, reply) => {
    const sel = req.query.ids ? String(req.query.ids).split(',').map(Number).filter(Number.isInteger) : null;
    return sendFile(reply, '법령 목록.xlsx', Buffer.from(await lawWorkbook(await lawRows(sel))), XLSX);
  });

  app.get('/export/projects/:id', { onRequest: app.need('projects', 1) }, async (req, reply) => {
    const x = await projectData(Number(req.params.id));
    if (!x) throw notFound();
    return sendFile(reply, `${safeName(x.p.name)}.xlsx`, Buffer.from(await projectWorkbook(x.p, x.items)), XLSX);
  });

  /**
   * 묶음 내보내기 (zip). 체크한 항목만 담는다.
   * body: { documentIds, formIds, lawIds, projectIds, includeForms(문서의 양식 포함, 기본 true),
   *         includeAttachments(문서·법령 첨부 포함, 기본 false), includeProjectFiles(기본 true), name }
   */
  app.post('/export/package', {
    onRequest: app.auth,
    schema: {
      body: {
        type: 'object',
        properties: {
          documentIds: { type: 'array', items: { type: 'integer' } },
          formIds: { type: 'array', items: { type: 'integer' } },
          lawIds: { type: 'array', items: { type: 'integer' } },
          projectIds: { type: 'array', items: { type: 'integer' } },
          includeForms: { type: 'boolean' },
          includeAttachments: { type: 'boolean' },
          includeProjectFiles: { type: 'boolean' },
          name: { type: 'string' },
        },
      },
    },
  }, async (req, reply) => {
    const b = req.body;
    const docIds = ids(b.documentIds) || [];
    const formIds = ids(b.formIds) || [];
    const lawIds = ids(b.lawIds) || [];
    const projIds = ids(b.projectIds) || [];
    if (!docIds.length && !formIds.length && !lawIds.length && !projIds.length) throw badRequest('내보낼 항목을 하나 이상 고르세요.');
    if (docIds.length || formIds.length) requireLevel(req, 'docs', 1);
    if (lawIds.length) requireLevel(req, 'laws', 1);
    if (projIds.length) requireLevel(req, 'projects', 1);
    const includeForms = b.includeForms !== false;
    const nb = await numbering();
    const company = await getConfig('company', DEFAULT_COMPANY);
    const zip = {};
    const used = new Set();
    const put = (p, buf) => {
      let name = p;
      for (let i = 2; used.has(name); i++) name = p.replace(/(\.[^./]+)?$/, ` (${i})$1`);
      used.add(name);
      zip[name] = [new Uint8Array(buf), { mtime: new Date() }];
    };
    let count = 0;
    const formsDone = new Set();

    if (docIds.length) {
      put('00_문서목록표.xlsx', Buffer.from(await documentListWorkbook(await documentListRows(docIds), company)));
      for (const id of docIds) {
        const x = await docXlsx(id, nb, company);
        if (!x) continue;
        const dir = `업무표준/${safeName(x.typeLabel)}/${safeName(`${x.doc.code} ${x.doc.title}`)}`;
        put(`${dir}/${x.filename}`, x.buf);
        count += 1;
        if (includeForms) {
          for (const f of x.forms) {
            const file = await latestFile('form', f.id);
            if (!file) continue;
            put(`${dir}/양식/${safeName(`${f.code} ${f.name}`)}${ext(file)}`, await readStored(file));
            formsDone.add(f.id);
            count += 1;
          }
        }
        if (b.includeAttachments) {
          for (const file of await allFiles('document', id)) {
            put(`${dir}/첨부/${safeName(file.filename, 120)}`, await readStored(file));
            count += 1;
          }
        }
      }
    }

    const extraForms = formIds.filter((f) => !formsDone.has(f));
    if (extraForms.length) {
      const { rows } = await query(
        `SELECT f.*, d.code AS dc, d.title AS dt FROM forms f JOIN documents d ON d.id = f.document_id
          WHERE f.id = ANY($1) AND f.deleted_at IS NULL ORDER BY d.type, d.num, f.seq`, [extraForms]);
      const listRows = [];
      for (const f of rows) {
        const file = await latestFile('form', f.id);
        listRows.push([f.code, f.name, `${f.dc} ${f.dt}`, f.retention, f.approval, file ? '포함' : '파일 없음']);
        if (!file) continue;
        put(`양식/${safeName(`${f.code} ${f.name}`)}${ext(file)}`, await readStored(file));
        count += 1;
      }
      put('양식/양식 목록.xlsx', Buffer.from(await formListWorkbook(listRows)));
    }

    if (lawIds.length) {
      put('법령/법령 목록.xlsx', Buffer.from(await lawWorkbook(await lawRows(lawIds))));
      count += 1;
      if (b.includeAttachments) {
        const { rows } = await query('SELECT id, name, article FROM laws WHERE id = ANY($1) AND deleted_at IS NULL', [lawIds]);
        for (const l of rows) {
          for (const file of await allFiles('law', l.id)) {
            put(`법령/첨부/${safeName(`${l.name} ${l.article || ''}`)}/${safeName(file.filename, 120)}`, await readStored(file));
            count += 1;
          }
        }
      }
    }

    for (const pid of projIds) {
      const x = await projectData(pid);
      if (!x) continue;
      const dir = `프로젝트/${safeName(x.p.name)}`;
      put(`${dir}/체크리스트.xlsx`, Buffer.from(await projectWorkbook(x.p, x.items)));
      count += 1;
      if (b.includeProjectFiles !== false) {
        for (const file of await allFiles('project', pid)) {
          put(`${dir}/공통자료/${safeName(file.filename, 120)}`, await readStored(file));
          count += 1;
        }
        let n = 0;
        for (const it of x.items) {
          n += 1;
          for (const file of await allFiles('item', it.id)) {
            put(`${dir}/제출서류/${String(n).padStart(2, '0')} ${safeName(it.title, 60)}/${safeName(file.filename, 120)}`, await readStored(file));
            count += 1;
          }
        }
      }
    }

    const buf = Buffer.from(zipSync(zip, { level: 6 }));
    const name = `${safeName(b.name || '업무표준 내보내기')}.zip`;
    await audit({ query }, req, '내보내기', 'settings', null, name,
      { note: `문서 ${docIds.length}, 양식 ${formIds.length}, 법령 ${lawIds.length}, 프로젝트 ${projIds.length} (파일 ${count}개)` });
    return sendFile(reply, name, buf, 'application/zip');
  });
}
