// 최초 실행 시 기본 데이터 넣기
//  1) 편집 부서: 총무팀 (모든 메뉴 등록·수정·삭제). 나머지 사람은 조회만 (기본값)
//  2) 원본 양식(ISO 문서 45개, 양식, 파일)에서 뽑은 업무표준 데이터 — seed/seed.json
// 한 번 넣으면 app_config.seeded 에 기록하고 다시 넣지 않는다.
import path from 'node:path';
import { existsSync } from 'node:fs';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { tx } from './db.js';
import { getConfig, setConfig, DEFAULT_NUMBERING, DEFAULT_COMPANY, DEFAULT_LEVELS, MODULES, renumber, audit } from './core.js';
import { storeFile } from '../routes/files.js';

const here = path.dirname(fileURLToPath(import.meta.url));

export function seedDir() {
  return [process.env.SEED_DIR, path.join(here, '..', '..', 'seed'), path.join(here, 'seed')]
    .find((d) => d && d !== 'none' && existsSync(path.join(d, 'seed.json')));
}

export async function seed(pool, log = console.log) {
  const { rows } = await pool.query(`SELECT value FROM app_config WHERE key = 'seeded'`);
  if (rows[0]) return false;
  const sys = { user: { id: null, name: '초기설정' } };
  await tx(async (db) => {
    await setConfig('numbering', DEFAULT_NUMBERING, db);
    await setConfig('company', DEFAULT_COMPANY, db);
    await setConfig('default_levels', DEFAULT_LEVELS, db);
    const { rows: d } = await db.query(`INSERT INTO departments (name, sort_order) VALUES ('총무팀', 1) RETURNING id`);
    for (const m of MODULES) {
      await db.query('INSERT INTO department_permissions VALUES ($1, $2, 3)', [d[0].id, m.key]);
    }
    await audit(db, sys, '설정', 'settings', null, '초기 권한: 총무팀 등록·수정·삭제, 그 외 조회');

    const dir = process.env.SEED_DIR === 'none' ? null : seedDir();
    if (dir) {
      const data = JSON.parse(await readFile(path.join(dir, 'seed.json'), 'utf8'));
      log(`기본 데이터 가져오는 중: 문서 ${data.documents.length}개`);
      const docIds = new Map();
      for (const x of data.documents) {
        const body = {
          purpose: x.purpose || '', scope: x.scope || '', resources: x.resources || {}, requirements: x.requirements || [],
          kpis: x.kpis || [], mainSteps: x.mainSteps || [], steps: x.steps || [], body: x.body || '', revisions: x.revisions || [],
          approvalLine: [], related: [],
          // 원본 양식의 주관부서는 다른 회사 조직이라 부서로 연결하지 않고 참고로만 남긴다
          deptNote: x.dept ? `원본 주관부서: ${x.dept}` : (x.deptNote ? `원본: ${x.deptNote}` : ''),
        };
        const { rows: r } = await db.query(
          `INSERT INTO documents (type, num, code, title, data, updated_by) VALUES ($1, $2, $3, $4, $5, '초기등록') RETURNING id`,
          [x.type, x.num, x.code, x.title, JSON.stringify(body)]);
        docIds.set(x.code, r[0].id);
      }
      for (const x of data.documents) {
        const rel = [...new Set(x.related.map((c) => docIds.get(c)).filter((v) => v && v !== docIds.get(x.code)))];
        if (rel.length) {
          await db.query(`UPDATE documents SET data = jsonb_set(data, '{related}', $2::jsonb) WHERE id = $1`,
            [docIds.get(x.code), JSON.stringify(rel)]);
        }
      }
      const formIds = new Map();
      // 원본에 양식번호가 없던 시트(-X)는 다음 순번으로
      const sorted = [...data.forms].sort((a, b) => Number(a.code.includes('-X')) - Number(b.code.includes('-X')));
      for (const f of sorted) {
        const did = docIds.get(f.docCode);
        if (!did) continue;
        let seq = f.seq;
        if (f.code.includes('-X')) {
          const { rows: m } = await db.query('SELECT COALESCE(MAX(seq), 0) + 1 AS n FROM forms WHERE document_id = $1', [did]);
          seq = m[0].n;
        }
        const { rows: r } = await db.query(
          `INSERT INTO forms (document_id, seq, code, name, retention, updated_by) VALUES ($1, $2, $3, $4, $5, '초기등록') RETURNING id`,
          [did, seq, f.code, f.name, f.retention || null]);
        formIds.set(f.code, r[0].id);
        await db.query('INSERT INTO document_forms VALUES ($1, $2) ON CONFLICT DO NOTHING', [did, r[0].id]);
      }
      for (const x of data.documents) {
        for (const fc of x.formCodes) {
          if (formIds.has(fc)) await db.query('INSERT INTO document_forms VALUES ($1, $2) ON CONFLICT DO NOTHING', [docIds.get(x.code), formIds.get(fc)]);
        }
      }
      let n = 0;
      for (const fl of data.files) {
        const oid = fl.owner === 'doc' ? docIds.get(fl.ownerCode) : formIds.get(fl.ownerCode);
        const src = path.join(dir, 'files', fl.path);
        if (!oid || !existsSync(src)) continue;
        await storeFile(db, sys, fl.owner === 'doc' ? 'document' : 'form', oid, fl.filename, await readFile(src), fl.note, false);
        n += 1;
      }
      await renumber(db, DEFAULT_NUMBERING, true);
      await audit(db, sys, '등록', 'settings', null, '기본 데이터 가져오기',
        { note: `원본 양식에서 문서 ${docIds.size}개, 양식 ${formIds.size}개, 파일 ${n}개` });
      log(`기본 데이터 완료: 문서 ${docIds.size}, 양식 ${formIds.size}, 파일 ${n}`);
    }
    await setConfig('seeded', { at: new Date().toISOString() }, db);
  });
  return true;
}

export { getConfig };
