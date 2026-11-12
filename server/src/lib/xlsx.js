// 엑셀 파일 만들기: 업무표준 문서(원본 양식과 비슷한 배치), 목록표, 법령, 프로젝트 체크리스트
import ExcelJS from 'exceljs';

const FONT = 'Malgun Gothic';
const NAVY = 'FF1F3B57';
const LIGHT = 'FFE9EEF4';
const thin = { style: 'thin', color: { argb: 'FF808080' } };
const BOX = { top: thin, left: thin, bottom: thin, right: thin };

function newBook() {
  const wb = new ExcelJS.Workbook();
  wb.creator = '업무표준 관리';
  wb.created = new Date();
  return wb;
}

function setup(ws, landscape = false) {
  ws.pageSetup = {
    paperSize: 9, orientation: landscape ? 'landscape' : 'portrait', fitToPage: true, fitToWidth: 1, fitToHeight: 0,
    margins: { left: 0.5, right: 0.5, top: 0.6, bottom: 0.6, header: 0.3, footer: 0.3 },
  };
  ws.headerFooter = { oddFooter: '&C&P / &N' };
}

/** 글자 수로 줄 높이 추정 (병합 칸 너비 = 문자 수) */
function rowHeight(text, widthChars) {
  const lines = String(text ?? '').split('\n').reduce((n, l) => n + Math.max(1, Math.ceil(l.length * 1.9 / Math.max(widthChars, 1))), 0);
  return Math.min(409, Math.max(18, lines * 15 + 4));
}

// ---------------------------------------------------------------- 업무표준 문서
// 열: A~H (8칸) 폭 합계 ≈ 100자
const COLS = [12, 12, 14, 14, 14, 14, 12, 12];
const W = (from, to) => COLS.slice(from, to + 1).reduce((a, b) => a + b, 0);
const L = 'ABCDEFGH';

class Sheet {
  constructor(ws) { this.ws = ws; this.r = 1; }
  cell(col, text, opt = {}) {
    const c = this.ws.getCell(`${L[col]}${this.r}`);
    // 병합된 칸의 나머지 칸에 값을 넣으면 첫 칸 값이 지워지므로 모양만 입힌다
    if (!opt.styleOnly) c.value = text ?? '';
    c.font = { name: FONT, size: opt.size || 9.5, bold: !!opt.bold, color: opt.color ? { argb: opt.color } : undefined };
    c.alignment = { vertical: opt.valign || 'top', horizontal: opt.align || 'left', wrapText: true };
    if (opt.fill) c.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: opt.fill } };
    if (opt.border !== false) c.border = BOX;
    return c;
  }
  /** cells: [[fromCol, toCol, text, opt]] 한 줄 */
  row(cells, minHeight = 18) {
    let h = minHeight;
    for (const [a, b, text, opt = {}] of cells) {
      if (b > a) this.ws.mergeCells(`${L[a]}${this.r}:${L[b]}${this.r}`);
      for (let k = a; k <= b; k++) this.cell(k, text, k === a ? opt : { ...opt, styleOnly: true });
      h = Math.max(h, rowHeight(text, W(a, b)));
    }
    this.ws.getRow(this.r).height = h;
    this.r += 1;
  }
  title(text) {
    this.row([[0, 7, text, { bold: true, size: 10.5, fill: LIGHT, valign: 'middle' }]], 20);
  }
  gap() { this.r += 1; }
}

const RES_KEYS = ['시설', '장비/도구', '수단', '자재', '인원의적격성', '관련조직'];

/**
 * doc: {code, title, type, typeLabel, department, data}, forms: [{code,name,retention}], related: [{code,title}]
 */
export async function documentWorkbook(doc, forms, related, laws, company) {
  const wb = newBook();
  const ws = wb.addWorksheet(doc.code.slice(0, 31) || '문서');
  ws.columns = COLS.map((w) => ({ width: w }));
  setup(ws);
  const s = new Sheet(ws);
  const d = doc.data || {};
  const revs = d.revisions || [];
  const last = revs[revs.length - 1] || {};
  const kindLabel = { M: 'MANUAL', P: 'MANAGEMENT SYSTEM', I: 'INSTRUCTION' }[doc.type] || doc.typeLabel || '';

  // 머리글
  const top = s.r;
  for (let i = 0; i < 4; i++) {
    const labels = ['문서번호', '개정번호', '개정일자', '주관부서'];
    const vals = [doc.code, last.rev || '', last.date || '', doc.department || ''];
    s.cell(6, labels[i], { fill: LIGHT, align: 'center', valign: 'middle', bold: true });
    s.cell(7, vals[i], { align: 'center', valign: 'middle' });
    ws.getRow(s.r).height = 20;
    s.r += 1;
  }
  ws.mergeCells(`A${top}:B${top + 3}`);
  const c1 = ws.getCell(`A${top}`);
  c1.value = company?.name || '';
  c1.font = { name: FONT, size: 11, bold: true };
  c1.alignment = { vertical: 'middle', horizontal: 'center', wrapText: true };
  for (let r = top; r < top + 4; r++) for (const col of 'AB') ws.getCell(`${col}${r}`).border = BOX;
  ws.mergeCells(`C${top}:F${top + 3}`);
  const c2 = ws.getCell(`C${top}`);
  c2.value = { richText: [
    { text: `${kindLabel}\n`, font: { name: FONT, size: 9, color: { argb: 'FF6B7785' } } },
    { text: doc.title, font: { name: FONT, size: 16, bold: true, color: { argb: NAVY } } },
  ] };
  c2.alignment = { vertical: 'middle', horizontal: 'center', wrapText: true };
  for (let r = top; r < top + 4; r++) for (const col of 'CDEF') ws.getCell(`${col}${r}`).border = BOX;
  s.gap();

  // 개정이력
  s.title('개정이력');
  s.row([[0, 0, '개정번호', { bold: true, fill: LIGHT, align: 'center' }], [1, 1, '제·개정일자', { bold: true, fill: LIGHT, align: 'center' }],
    [2, 7, '개정 사유 및 내용', { bold: true, fill: LIGHT, align: 'center' }]]);
  for (const r of revs.length ? revs : [{}]) {
    s.row([[0, 0, r.rev || '', { align: 'center' }], [1, 1, r.date || '', { align: 'center' }], [2, 7, r.desc || '']]);
  }
  // 결재
  const stages = (d.approvalLine && d.approvalLine.length) ? d.approvalLine : [{ stage: '작성' }, { stage: '검토' }, { stage: '승인' }];
  const n = Math.min(stages.length, 7);
  const span = Math.floor(7 / n);
  const cellsFor = (fn) => {
    const out = [];
    let col = 1;
    for (let i = 0; i < n; i++) {
      const to = i === n - 1 ? 7 : col + span - 1;
      out.push([col, to, fn(stages[i]), { align: 'center', valign: 'middle' }]);
      col = to + 1;
    }
    return out;
  };
  s.row([[0, 0, '구분', { bold: true, fill: LIGHT, align: 'center' }], ...cellsFor((x) => `${x.stage || ''}${x.role ? ` (${x.role})` : ''}`)]);
  s.row([[0, 0, '서명', { bold: true, fill: LIGHT, align: 'center', valign: 'middle' }], ...cellsFor(() => '')], 36);
  s.row([[0, 0, '일자', { bold: true, fill: LIGHT, align: 'center' }], ...cellsFor(() => '')]);
  s.gap();

  // 목적·범위
  s.row([[0, 0, '목적', { bold: true, fill: LIGHT, align: 'center', valign: 'middle' }], [1, 7, d.purpose || '']], 30);
  s.row([[0, 0, '적용범위', { bold: true, fill: LIGHT, align: 'center', valign: 'middle' }], [1, 7, d.scope || '']], 30);
  s.gap();

  // 프로세스 분석
  const res = d.resources || {};
  if (RES_KEYS.some((k) => res[k])) {
    s.title('프로세스 분석');
    for (const k of RES_KEYS) {
      s.row([[0, 1, k === '인원의적격성' ? '인원의 적격성' : k, { bold: true, fill: LIGHT }], [2, 7, res[k] || '']]);
    }
    s.gap();
  }
  if ((d.requirements || []).length) {
    s.title('요구사항');
    s.row([[0, 1, '구분', { bold: true, fill: LIGHT, align: 'center' }], [2, 2, '조항', { bold: true, fill: LIGHT, align: 'center' }],
      [3, 7, '내용', { bold: true, fill: LIGHT, align: 'center' }]]);
    for (const r of d.requirements) s.row([[0, 1, r.cat || ''], [2, 2, r.no || '', { align: 'center' }], [3, 7, r.name || '']]);
    s.gap();
  }
  if (laws?.length) {
    s.title('관련 법령');
    for (const l of laws) s.row([[0, 2, l.name], [3, 4, l.article || ''], [5, 7, l.title || '']]);
    s.gap();
  }
  if ((d.kpis || []).length) {
    s.title('성과 및 리스크 지표');
    s.row([[0, 2, '지표', { bold: true, fill: LIGHT, align: 'center' }], [3, 6, '산출식', { bold: true, fill: LIGHT, align: 'center' }],
      [7, 7, '주기', { bold: true, fill: LIGHT, align: 'center' }]]);
    for (const k of d.kpis) s.row([[0, 2, k.name || ''], [3, 6, k.formula || ''], [7, 7, k.period || '', { align: 'center' }]]);
    s.gap();
  }
  // 주요 업무절차 + 관련 프로세스 (나란히)
  const ms = d.mainSteps || [];
  if (ms.length || related?.length) {
    s.title('주요 업무절차 / 관련 프로세스');
    s.row([[0, 3, '주요 업무절차', { bold: true, fill: LIGHT, align: 'center' }], [4, 5, '문서번호', { bold: true, fill: LIGHT, align: 'center' }],
      [6, 7, '프로세스명', { bold: true, fill: LIGHT, align: 'center' }]]);
    for (let i = 0; i < Math.max(ms.length, related?.length || 0); i++) {
      const rp = related?.[i];
      s.row([[0, 3, ms[i] ? `${i + 1}. ${ms[i]}` : ''], [4, 5, rp?.code || '', { align: 'center' }], [6, 7, rp?.title || '']]);
    }
    s.gap();
  }
  // 관련 기록 및 양식
  if (forms?.length) {
    s.title('관련 기록 및 양식');
    s.row([[0, 0, '순', { bold: true, fill: LIGHT, align: 'center' }], [1, 2, '양식번호', { bold: true, fill: LIGHT, align: 'center' }],
      [3, 6, '양식명', { bold: true, fill: LIGHT, align: 'center' }], [7, 7, '보존년한', { bold: true, fill: LIGHT, align: 'center' }]]);
    forms.forEach((f, i) => s.row([[0, 0, String(i + 1), { align: 'center' }], [1, 2, f.code, { align: 'center' }], [3, 6, f.name],
      [7, 7, f.retention || '', { align: 'center' }]]));
    s.gap();
  }
  // 업무 절차
  const steps = d.steps || [];
  if (steps.length) {
    if (s.r > 40) ws.getRow(s.r - 1).addPageBreak();
    s.title('업무 절차');
    s.row([[0, 1, '입력사항', { bold: true, fill: LIGHT, align: 'center' }], [2, 5, '업무 수행 내용', { bold: true, fill: LIGHT, align: 'center' }],
      [6, 6, '출력사항', { bold: true, fill: LIGHT, align: 'center' }], [7, 7, '전결권한', { bold: true, fill: LIGHT, align: 'center' }]]);
    steps.forEach((st, i) => {
      s.row([[0, 7, `${i + 1}. ${st.title || ''}`, { bold: true, fill: 'FFF6F8FA' }]]);
      s.row([[0, 1, (st.inputs || []).map((x) => `▶ ${x}`).join('\n')], [2, 5, st.content || ''],
        [6, 6, (st.outputs || []).map((x) => `▶ ${x}`).join('\n')], [7, 7, st.approver || '', { align: 'center' }]]);
      if (st.note) s.row([[0, 7, st.note, { color: 'FF555555' }]]);
    });
    s.gap();
  }
  if (d.body) {
    s.title(doc.type === 'M' ? '본문' : '세부 내용');
    // 긴 본문은 문단별로 나눠 줄 높이 한도를 넘지 않게
    for (const para of String(d.body).split(/\n(?=\S)/)) s.row([[0, 7, para, { border: false }]]);
  }
  return wb.xlsx.writeBuffer();
}

// ---------------------------------------------------------------- 목록표·표 형식
async function tableBook(sheetName, title, headers, widths, rows, landscape = false, subtitle = '') {
  const wb = newBook();
  const ws = wb.addWorksheet(sheetName);
  setup(ws, landscape);
  ws.columns = widths.map((w) => ({ width: w }));
  ws.mergeCells(1, 1, 1, headers.length);
  ws.getCell(1, 1).value = title;
  ws.getCell(1, 1).font = { name: FONT, size: 14, bold: true, color: { argb: NAVY } };
  ws.getRow(1).height = 26;
  let r = 2;
  if (subtitle) {
    ws.mergeCells(2, 1, 2, headers.length);
    ws.getCell(2, 1).value = subtitle;
    ws.getCell(2, 1).font = { name: FONT, size: 9, color: { argb: 'FF6B7785' } };
    ws.getCell(2, 1).alignment = { wrapText: true, vertical: 'top' };
    ws.getRow(2).height = Math.min(120, 16 * (subtitle.split('\n').length));
    r = 3;
  }
  r += 1;
  headers.forEach((h, i) => {
    const c = ws.getCell(r, i + 1);
    c.value = h;
    c.font = { name: FONT, size: 9.5, bold: true, color: { argb: 'FFFFFFFF' } };
    c.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: NAVY } };
    c.alignment = { horizontal: 'center', vertical: 'middle', wrapText: true };
    c.border = BOX;
  });
  ws.views = [{ state: 'frozen', ySplit: r }];
  ws.pageSetup.printTitlesRow = `${r}:${r}`;
  for (const row of rows) {
    r += 1;
    let h = 18;
    row.forEach((v, i) => {
      const c = ws.getCell(r, i + 1);
      c.value = v ?? '';
      c.font = { name: FONT, size: 9.5 };
      c.alignment = { vertical: 'top', wrapText: true };
      c.border = BOX;
      h = Math.max(h, rowHeight(v, widths[i]));
    });
    ws.getRow(r).height = h;
  }
  return wb.xlsx.writeBuffer();
}

export function documentListWorkbook(rows, company) {
  return tableBook('문서목록표', `${company?.name ? `${company.name} ` : ''}업무표준 문서 목록표`,
    ['구분', '문서번호', '문서명', '주관부서', '개정번호', '개정일자', '관련 양식'],
    [12, 14, 34, 14, 9, 12, 44], rows, true);
}

export function formListWorkbook(rows) {
  return tableBook('양식목록', '양식 목록', ['양식번호', '양식명', '소속 문서', '보존년한', '결재란', '파일'],
    [16, 34, 30, 10, 20, 8], rows, true);
}

export function lawWorkbook(rows) {
  return tableBook('법령', '법령 목록', ['법령명', '구분', '조항', '조문 제목', '내용', '시행일', '관련 문서', '메모', '링크'],
    [22, 10, 12, 18, 70, 11, 18, 30, 24], rows, true);
}

export function projectWorkbook(p, items) {
  const sub = [`분류: ${p.category || ''}   상태: ${p.status || ''}   기간: ${p.startDate || '?'} ~ ${p.dueDate || '?'}   총괄: ${p.owner || ''}`,
    `참여부서: ${p.departmentNames || ''}`, p.description || ''].filter(Boolean).join('\n');
  return tableBook('체크리스트', p.name, ['No', '항목(서류·업무)', '담당부서', '담당자', '기한', '상태', '연결 양식', '관련 문서', '비고'],
    [5, 36, 13, 11, 11, 9, 26, 12, 30],
    items.map((it, i) => [i + 1, it.title, it.department, it.assignee, it.dueDate, it.status,
      it.formCode ? `${it.formCode} ${it.formName}` : '', it.docCode || '', it.note]), true, sub);
}
