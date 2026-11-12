export class AppError extends Error {
  constructor(statusCode, message) {
    super(message);
    this.statusCode = statusCode;
  }
}

export const badRequest = (msg) => new AppError(400, msg);
export const notFound = (msg = '대상을 찾을 수 없습니다.') => new AppError(404, msg);
export const conflict = (msg) => new AppError(409, msg);
export const forbidden = (msg = '권한이 없습니다.') => new AppError(403, msg);

/** 동시 수정 확인: 화면에서 읽은 version 과 지금 DB 의 version 이 다르면 거절 */
export function checkVersion(row, version, what = '이 항목') {
  if (version !== undefined && version !== null && row.version !== version) {
    throw conflict(`다른 사용자가 먼저 ${what}을(를) 수정했습니다 (${row.updated_by || '알 수 없음'}). 새로 불러온 뒤 다시 수정하세요.`);
  }
}

/** '' → null (DATE 컬럼용) */
export const dateOrNull = (v) => (v ? v : null);
