// 공통: 변경이력, 권한, 번호 체계, 설정, 파일 위치
import path from 'node:path';
import os from 'node:os';
import { mkdirSync } from 'node:fs';
import { query } from './db.js';
import { forbidden } from './errors.js';

// ---------------------------------------------------------------- 파일 위치
export function dataDir() {
  return process.env.DATA_DIR
    || (process.platform === 'win32'
      ? path.join(process.env.ProgramData || 'C:\\ProgramData', 'WorkGuideline')
      : path.join(os.homedir(), '.work-guideline'));
}
export function filesDir() {
  const d = process.env.FILES_DIR || path.join(dataDir(), 'files');
  mkdirSync(d, { recursive: true });
  return d;
}

// ---------------------------------------------------------------- 설정
export async function getConfig(key, fallback = null, db = { query }) {
  const { rows } = await db.query('SELECT value FROM app_config WHERE key = $1', [key]);
  return rows[0] ? rows[0].value : fallback;
}
export async function setConfig(key, value, db = { query }) {
  await db.query(
    `INSERT INTO app_config (key, value) VALUES ($1, $2)
     ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = now()`,
    [key, JSON.stringify(value)],
  );
}

export const DEFAULT_NUMBERING = {
  types: [
    { key: 'M', label: '매뉴얼', prefix: 'M' },
    { key: 'P', label: '프로세스', prefix: 'P' },
    { key: 'I', label: '지침', prefix: 'I' },
  ],
  docPattern: '{prefix}-{num}',
  formPattern: '{doc}-{seq:02}',
};

export const DEFAULT_COMPANY = {
  name: '',
  approvalRoles: ['담당', '팀장', '부서장', '대표이사'],
};

// ---------------------------------------------------------------- 번호 체계
/** 패턴 예: {prefix}-{num}, {doc}-{seq:02}, KS-{prefix}{num:03} */
export function formatCode(pattern, vars) {
  return pattern.replace(/\{(\w+)(?::(\d+))?\}/g, (_, key, width) => {
    const v = vars[key];
    if (v === undefined || v === null) return '';
    if (width && Number.isInteger(v)) return String(v).padStart(Number(width), '0');
    return String(v);
  });
}
export function docCode(nb, type, num) {
  const t = nb.types.find((x) => x.key === type) || { prefix: type };
  return formatCode(nb.docPattern, { prefix: t.prefix, num: Number(num) || 0, type });
}
export function formCode(nb, doc, seq) {
  return formatCode(nb.formPattern, { doc, seq: Number(seq) || 0 });
}
export async function numbering(db = { query }) {
  return getConfig('numbering', DEFAULT_NUMBERING, db);
}

/**
 * 번호 체계에 맞춰 직접 지정하지 않은 문서·양식 번호를 다시 계산한다.
 * apply=false 면 바꾸지 않고 바뀔 목록만 돌려준다 (미리보기).
 */
export async function renumber(db, nb, apply) {
  const changes = [];
  const { rows: docs } = await db.query(
    'SELECT id, type, num, code, code_manual FROM documents WHERE deleted_at IS NULL ORDER BY type, num, id');
  const newDocCode = new Map();
  for (const d of docs) {
    const c = d.code_manual ? d.code : docCode(nb, d.type, d.num);
    newDocCode.set(d.id, c);
    if (c !== d.code) {
      changes.push({ kind: 'document', id: d.id, from: d.code, to: c });
      if (apply) await db.query('UPDATE documents SET code = $2 WHERE id = $1', [d.id, c]);
    }
  }
  const { rows: forms } = await db.query(
    'SELECT id, document_id, seq, code, code_manual FROM forms WHERE deleted_at IS NULL ORDER BY document_id, seq');
  for (const f of forms) {
    const dc = newDocCode.get(f.document_id);
    if (!dc) continue;
    const c = f.code_manual ? f.code : formCode(nb, dc, f.seq);
    if (c !== f.code) {
      changes.push({ kind: 'form', id: f.id, from: f.code, to: c });
      if (apply) await db.query('UPDATE forms SET code = $2 WHERE id = $1', [f.id, c]);
    }
  }
  return changes;
}

// ---------------------------------------------------------------- 권한
export const MODULES = [
  { key: 'docs', label: '업무표준 (문서·양식)' },
  { key: 'laws', label: '법령' },
  { key: 'projects', label: '프로젝트' },
  { key: 'logs', label: '변경이력' },
];
export const LEVELS = ['없음', '조회', '등록·수정', '등록·수정·삭제'];
export const DEFAULT_LEVELS = { docs: 1, laws: 1, projects: 1, logs: 1 };

/** 사용자의 메뉴별 실제 권한 = max(기본값, 부서 권한, 개인 권한). 관리자는 모두 3 */
export async function effectivePerms(user) {
  const out = {};
  if (user.isAdmin) {
    for (const m of MODULES) out[m.key] = 3;
    return out;
  }
  const defaults = await getConfig('default_levels', DEFAULT_LEVELS);
  for (const m of MODULES) out[m.key] = defaults[m.key] ?? 1;
  if (user.departmentId) {
    const { rows } = await query('SELECT module, level FROM department_permissions WHERE department_id = $1', [user.departmentId]);
    for (const r of rows) out[r.module] = Math.max(out[r.module] ?? 0, r.level);
  }
  const { rows } = await query('SELECT module, level FROM user_permissions WHERE user_id = $1', [user.id]);
  for (const r of rows) out[r.module] = Math.max(out[r.module] ?? 0, r.level);
  return out;
}

export function requireLevel(req, module, level) {
  if ((req.user.perms?.[module] ?? 0) < level) {
    const what = MODULES.find((m) => m.key === module)?.label || module;
    throw forbidden(`${what} ${LEVELS[level]} 권한이 없습니다. 관리자에게 요청하세요.`);
  }
}

// ---------------------------------------------------------------- 변경이력
export async function audit(db, req, action, entity, entityId, label, detail = {}, projectId = null) {
  await db.query(
    `INSERT INTO audit_logs (user_id, user_name, action, entity, entity_id, label, project_id, detail)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
    [req?.user?.id ?? null, req?.user?.name ?? 'system', action, entity, entityId, label, projectId, JSON.stringify(detail)],
  );
}

/** 두 객체에서 바뀐 항목만 {표시이름: [전, 후]} 로 */
export function diffFields(before, after, labels) {
  const ch = {};
  for (const [k, lbl] of Object.entries(labels)) {
    const a = before?.[k] ?? null;
    const b = after?.[k] ?? null;
    if (JSON.stringify(norm(a)) !== JSON.stringify(norm(b))) ch[lbl] = [a, b];
  }
  return ch;
}
function norm(v) {
  if (v === '' || v === undefined) return null;
  if (Array.isArray(v) && v.length === 0) return null;
  if (v && typeof v === 'object' && !Array.isArray(v)) {
    const o = {};
    for (const k of Object.keys(v).sort()) {
      const n = norm(v[k]);
      if (n !== null) o[k] = n;
    }
    return Object.keys(o).length ? o : null;
  }
  return v;
}

/** 오늘 날짜 (서버 시간대 기준 YYYY-MM-DD) */
export function today() {
  const tz = process.env.TZ_NAME || 'Asia/Seoul';
  return new Intl.DateTimeFormat('sv-SE', { timeZone: tz }).format(new Date());
}
