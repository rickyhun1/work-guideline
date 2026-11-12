// 전체 흐름: 기본 데이터 → 권한(총무팀만 편집) → 문서·양식·번호 체계 → 법령 → 프로젝트 → 내보내기 → 변경이력
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { unzipSync, strFromU8 } from 'fflate';
import { buildApp } from '../src/app.js';
import { pool } from '../src/lib/db.js';
import { migrate } from '../src/lib/migrate.js';
import { seed } from '../src/lib/seed.js';

let app;
let admin;
let emp;

async function call(method, url, body, token = admin, headers = {}) {
  const r = await app.inject({
    method, url,
    headers: { ...(token ? { authorization: `Bearer ${token}` } : {}), ...headers },
    ...(body !== undefined ? (Buffer.isBuffer(body) ? { payload: body } : { payload: body }) : {}),
  });
  return r;
}
async function ok(method, url, body, token = admin) {
  const r = await call(method, url, body, token);
  assert.ok(r.statusCode < 300, `${method} ${url} → ${r.statusCode} ${r.body}`);
  return r.headers['content-type']?.includes('json') ? r.json() : r;
}
const q = (s) => encodeURIComponent(s);

before(async () => {
  assert.match(process.env.DATABASE_URL || '', /test/, '테스트는 이름에 test 가 들어간 DB에서만 실행하세요.');
  process.env.FILES_DIR = mkdtempSync(path.join(os.tmpdir(), 'wg-files-'));
  await pool.query('DROP SCHEMA public CASCADE; CREATE SCHEMA public;');
  await migrate(pool, () => {});
  await seed(pool, () => {});
  app = buildApp({ logger: false });
  await app.ready();
  assert.equal((await ok('GET', '/setup/status', undefined, null)).needsSetup, true);
  await ok('POST', '/setup', { empNo: 'A001', name: '총무관리자', password: 'admin1234' }, null);
  admin = (await ok('POST', '/auth/login', { empNo: 'A001', password: 'admin1234' }, null)).token;
  const { id: sales } = await ok('POST', '/departments', { name: '영업팀' });
  await ok('POST', '/users', { empNo: 'E001', name: '김영업', departmentId: sales, password: 'pass1234' });
  emp = (await ok('POST', '/auth/login', { empNo: 'E001', password: 'pass1234' }, null)).token;
});

after(async () => {
  await app.close();
  await pool.end();
});

test('기본 데이터: 문서 45개, 양식, 원본 파일', async () => {
  const docs = await ok('GET', '/documents');
  assert.equal(docs.length, 45);
  const p1001 = docs.find((d) => d.code === 'P-1001');
  const d = await ok('GET', `/documents/${p1001.id}`);
  assert.equal(d.title, '부적합 및 시정조치');
  assert.equal(d.forms.length, 2);
  assert.ok(d.forms[0].latestFileId, '양식 파일이 있어야 함');
  assert.equal(d.data.steps[0].approver, '발행부서장');
  assert.deepEqual(d.related.map((r) => r.code), ['P-905', 'P-901', 'P-904', 'P-810']);
  assert.ok(d.fileCount >= 1, '원본 문서 파일');
});

test('권한: 총무팀만 편집, 다른 부서는 조회만', async () => {
  const me = await ok('GET', '/me', undefined, emp);
  assert.deepEqual(me.perms, { docs: 1, laws: 1, projects: 1, logs: 1 });
  const adminMe = await ok('GET', '/me');
  assert.equal(adminMe.user.department, '총무팀');
  const docs = await ok('GET', '/documents', undefined, emp);
  const d = await ok('GET', `/documents/${docs[0].id}`, undefined, emp);
  const r = await call('PATCH', `/documents/${d.id}`, { type: d.type, title: '바꿈', version: d.version }, emp);
  assert.equal(r.statusCode, 403);
  assert.equal((await call('POST', '/laws', { name: '산업안전보건법' }, emp)).statusCode, 403);
  assert.equal((await call('GET', '/users', undefined, emp)).statusCode, 403);
});

test('문서 수정: 변경이력(전→후)과 동시 수정 충돌', async () => {
  const docs = await ok('GET', '/documents');
  const d = await ok('GET', `/documents/${docs.find((x) => x.code === 'P-805').id}`);
  const data = { ...d.data, purpose: '새 목적', approvalLine: [{ stage: '작성', role: '담당' }, { stage: '승인', role: '대표이사' }] };
  const r1 = await ok('PATCH', `/documents/${d.id}`, { type: d.type, num: d.num, title: d.title, data, version: d.version });
  assert.equal(r1.version, d.version + 1);
  const stale = await call('PATCH', `/documents/${d.id}`, { type: d.type, num: d.num, title: '다른 제목', data, version: d.version });
  assert.equal(stale.statusCode, 409);
  const logs = await ok('GET', `/logs?entity=document&entityId=${d.id}`);
  assert.equal(logs[0].action, '수정');
  assert.deepEqual(Object.keys(logs[0].detail.changes).sort(), ['결재라인', '목적'].sort());
  assert.equal(logs[0].detail.changes['목적'][1], '새 목적');
});

test('번호 체계: 미리보기 → 일괄 적용 (직접 지정 번호는 유지)', async () => {
  const docs = await ok('GET', '/documents');
  const m = await ok('GET', `/documents/${docs.find((x) => x.code === 'M-400').id}`);
  await ok('PATCH', `/documents/${m.id}`, { type: 'M', num: 400, title: m.title, code: 'QM-01', codeManual: true, data: m.data, version: m.version });
  const nb = await ok('GET', '/settings/numbering');
  nb.docPattern = 'KS-{prefix}-{num}';
  nb.formPattern = '{doc}-F{seq:02}';
  const pv = await ok('POST', '/settings/numbering/preview', nb);
  assert.ok(pv.changes.some((c) => c.from === 'P-1001' && c.to === 'KS-P-1001'));
  assert.ok(!pv.changes.some((c) => c.from === 'QM-01'));
  assert.ok(!(await ok('GET', '/documents')).some((d) => d.code.startsWith('KS-')), '미리보기는 바꾸지 않음');
  await ok('PUT', '/settings/numbering', nb);
  const after2 = await ok('GET', '/documents');
  assert.ok(after2.some((d) => d.code === 'KS-P-1001'));
  assert.ok(after2.some((d) => d.code === 'QM-01'));
  const forms = await ok('GET', `/forms?q=${q('KS-P-1001')}`);
  assert.deepEqual(forms.map((f) => f.code), ['KS-P-1001-F01', 'KS-P-1001-F02']);
  const bad = await call('PUT', '/settings/numbering', { ...nb, docPattern: '{prefix}' });
  assert.equal(bad.statusCode, 400);
});

test('양식: 새 버전 업로드 → 최신 파일로 내보내기, 이전 버전 보관', async () => {
  const [f] = await ok('GET', `/forms?q=${q('KS-P-1001-F01')}`);
  const before2 = await ok('GET', `/files?owner=form&ownerId=${f.id}`);
  const up = await app.inject({
    method: 'POST', url: `/files?owner=form&ownerId=${f.id}&name=${q('요구서 2027 개정.xlsx')}&note=${q('2027 개정')}`,
    headers: { authorization: `Bearer ${admin}`, 'content-type': 'application/octet-stream' }, payload: Buffer.from('NEWFILE'),
  });
  assert.equal(up.statusCode, 201, up.body);
  const files = await ok('GET', `/files?owner=form&ownerId=${f.id}`);
  assert.equal(files.length, before2.length + 1);
  assert.equal(files[0].filename, '요구서 2027 개정.xlsx');
  const ex = await call('GET', `/export/forms/${f.id}`);
  assert.equal(ex.statusCode, 200);
  assert.equal(ex.body, 'NEWFILE');
  assert.match(decodeURIComponent(ex.headers['content-disposition']), /KS-P-1001-F01 부적합 및 시정조치 요구서\.xlsx/);
  const empUp = await app.inject({
    method: 'POST', url: `/files?owner=form&ownerId=${f.id}&name=x.xlsx`,
    headers: { authorization: `Bearer ${emp}`, 'content-type': 'application/octet-stream' }, payload: Buffer.from('X'),
  });
  assert.equal(empUp.statusCode, 403);
});

test('법령: 직접 입력, 내용 검색, 문서 연결', async () => {
  const docs = await ok('GET', '/documents');
  const i810 = docs.find((d) => d.code === 'KS-I-810');
  const { id } = await ok('POST', '/laws', {
    name: '산업안전보건법', kind: '법률', article: '제38조', title: '안전조치',
    content: '사업주는 굴착작업 등 위험한 작업에서 발생하는 위험을 예방하기 위하여 필요한 조치를 하여야 한다.',
    effectiveDate: '2025-01-01', documentIds: [i810.id],
  });
  const found = await ok('GET', `/laws?q=${q('굴착작업')}`);
  assert.deepEqual(found.map((l) => l.id), [id]);
  const s = await ok('GET', `/search?q=${q('굴착작업')}`);
  assert.ok(s.some((x) => x.kind === 'law' && x.id === id));
  const d = await ok('GET', `/documents/${i810.id}`);
  assert.deepEqual(d.laws.map((l) => l.article), ['제38조']);
  const l = await ok('GET', `/laws/${id}`);
  await ok('PATCH', `/laws/${id}`, { ...l, effectiveDate: l.effectiveDate, documentIds: [], version: l.version });
  const logs = await ok('GET', `/logs?entity=law&entityId=${id}`);
  assert.ok(logs[0].detail.changes['관련 문서']);
});

test('프로젝트: 부서·서류·기한 공유, 복제, 엑셀', async () => {
  const depts = await ok('GET', '/departments');
  const { id } = await ok('POST', '/projects', {
    name: '2027 스마트공장 지원사업', category: '지원사업 신청', dueDate: '2027-03-31', departments: depts.map((d) => d.id),
  });
  const [form] = await ok('GET', `/forms?q=${q('KS-P-1001-F01')}`);
  await ok('POST', `/projects/${id}/items`, { title: '사업계획서', departmentId: depts[0].id, dueDate: '2027-03-15', formId: form.id });
  await ok('POST', `/projects/${id}/items`, { title: '재무제표 3년', departmentId: depts[1].id, assignee: '김영업' });
  const p = await ok('GET', `/projects/${id}`);
  assert.equal(p.items.length, 2);
  assert.equal(p.items[0].formCode, 'KS-P-1001-F01');
  assert.ok(p.items[0].formFileId);
  const it = p.items[1];
  await ok('PATCH', `/items/${it.id}`, { ...it, status: '완료', version: it.version });
  const list = await ok('GET', '/projects');
  assert.equal(list.find((x) => x.id === id).doneCount, 1);
  const copy = await ok('POST', `/projects/${id}/copy`);
  const c = await ok('GET', `/projects/${copy.id}`);
  assert.equal(c.items.length, 2);
  assert.ok(c.items.every((x) => x.status === '미착수'));
  const logs = await ok('GET', `/logs?projectId=${id}`);
  assert.ok(logs.some((l) => l.entity === 'item' && l.action === '수정'));
  const x = await call('GET', `/export/projects/${id}`);
  assert.equal(x.statusCode, 200);
  assert.equal(x.rawPayload.subarray(0, 2).toString(), 'PK');
  assert.equal((await call('POST', `/projects/${id}/items`, { title: 'x' }, emp)).statusCode, 403);
});

test('묶음 내보내기: 체크한 문서·양식·법령·프로젝트를 zip 하나로', async () => {
  const docs = await ok('GET', '/documents');
  const pick = docs.filter((d) => ['KS-P-1001', 'KS-I-810', 'QM-01'].includes(d.code)).map((d) => d.id);
  const [form] = await ok('GET', `/forms?q=${q('KS-P-805-F01')}`);
  const laws = await ok('GET', '/laws');
  const projects = await ok('GET', '/projects');
  const r = await call('POST', '/export/package', {
    documentIds: pick, formIds: [form.id], lawIds: laws.map((l) => l.id), projectIds: [projects[0].id], name: '인증심사 제출',
  });
  assert.equal(r.statusCode, 200, r.body);
  assert.match(decodeURIComponent(r.headers['content-disposition']), /인증심사 제출\.zip/);
  const names = Object.keys(unzipSync(new Uint8Array(r.rawPayload)));
  assert.ok(names.includes('00_문서목록표.xlsx'));
  assert.ok(names.includes('업무표준/프로세스/KS-P-1001 부적합 및 시정조치/KS-P-1001 부적합 및 시정조치.xlsx'), names.join('\n'));
  assert.ok(names.some((n) => n.startsWith('업무표준/프로세스/KS-P-1001 부적합 및 시정조치/양식/KS-P-1001-F01')));
  assert.ok(names.some((n) => n.startsWith('업무표준/매뉴얼/QM-01 경영매뉴얼/')));
  assert.ok(names.includes('양식/양식 목록.xlsx'));
  assert.ok(names.includes('법령/법령 목록.xlsx'));
  assert.ok(names.some((n) => n.startsWith('프로젝트/') && n.endsWith('체크리스트.xlsx')));
  const empty = await call('POST', '/export/package', {});
  assert.equal(empty.statusCode, 400);
  // 문서 하나 엑셀
  const one = await call('GET', `/export/documents/${pick[0]}`);
  assert.equal(one.statusCode, 200);
  assert.equal(one.rawPayload.subarray(0, 2).toString(), 'PK');
  const logs = await ok('GET', `/logs?q=${q('인증심사 제출')}`);
  assert.equal(logs[0].action, '내보내기');
});

test('권한 부여: 영업팀에 프로젝트 등록·수정 권한 → 바로 반영', async () => {
  const depts = await ok('GET', '/departments');
  const sales = depts.find((d) => d.name === '영업팀');
  const perms = await ok('GET', '/permissions');
  perms.departments[sales.id] = { projects: 2 };
  await ok('PUT', '/permissions', { defaults: perms.defaults, departments: perms.departments, users: perms.users });
  const me = await ok('GET', '/me', undefined, emp);
  assert.equal(me.perms.projects, 2);
  assert.equal(me.perms.docs, 1);
  const [p] = await ok('GET', '/projects', undefined, emp);
  await ok('POST', `/projects/${p.id}/items`, { title: '영업팀 추가 서류' }, emp);
  assert.equal((await call('DELETE', `/projects/${p.id}`, undefined, emp)).statusCode, 403);
});

test('검색: 문서 내용까지', async () => {
  const s = await ok('GET', `/search?q=${q('화기작업')}`, undefined, emp);
  assert.ok(s.some((x) => x.kind === 'document' && x.code === 'KS-I-810'));
  const dash = await ok('GET', '/dashboard');
  assert.equal(dash.counts.documents, 45);
  assert.ok(dash.recent.length > 0);
});

test('관리자 최소 1명 유지', async () => {
  const users = await ok('GET', '/users');
  const a = users.find((u) => u.empNo === 'A001');
  assert.equal((await call('PATCH', `/users/${a.id}`, { isAdmin: false })).statusCode, 409);
  void strFromU8;
});
