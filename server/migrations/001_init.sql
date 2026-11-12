-- 업무표준 관리 초기 스키마
-- 원칙: 지우지 않고 deleted_at 으로 표시한다. 모든 변경은 audit_logs 에 남긴다.
--       동시에 고치는 것을 막으려고 주요 표에 version 을 두고, 저장할 때 맞는지 확인한다.

CREATE TABLE app_config (
  key        TEXT PRIMARY KEY,
  value      JSONB,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE departments (
  id         SERIAL PRIMARY KEY,
  name       TEXT NOT NULL,
  sort_order INT NOT NULL DEFAULT 0,
  active     BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX departments_name_active ON departments (name) WHERE active;

CREATE TABLE users (
  id            SERIAL PRIMARY KEY,
  emp_no        TEXT NOT NULL UNIQUE,           -- 사번 (로그인 ID)
  name          TEXT NOT NULL,
  department_id INT REFERENCES departments(id),
  position      TEXT,
  is_admin      BOOLEAN NOT NULL DEFAULT FALSE, -- 사용자·권한·설정 관리
  password_hash TEXT NOT NULL,
  active        BOOLEAN NOT NULL DEFAULT TRUE,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 권한: 메뉴(module)별 단계(level). 실제 권한 = max(기본값, 부서 권한, 개인 권한). 관리자는 모두 3.
--   module: docs(업무표준 문서·양식) / laws(법령) / projects(프로젝트) / logs(변경이력 조회)
--   level : 0 없음, 1 조회, 2 등록·수정, 3 등록·수정·삭제
CREATE TABLE department_permissions (
  department_id INT NOT NULL REFERENCES departments(id) ON DELETE CASCADE,
  module        TEXT NOT NULL,
  level         INT NOT NULL CHECK (level BETWEEN 0 AND 3),
  PRIMARY KEY (department_id, module)
);
CREATE TABLE user_permissions (
  user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  module  TEXT NOT NULL,
  level   INT NOT NULL CHECK (level BETWEEN 0 AND 3),
  PRIMARY KEY (user_id, module)
);

-- 업무표준 문서 (매뉴얼·프로세스·지침 …). 구분(type)은 번호 체계 설정에서 정의한다.
-- data: 목적, 적용범위, 자원, 요구사항, 지표, 주요업무절차, 세부절차(전결권한), 본문, 결재라인, 관련 프로세스, 개정이력
CREATE TABLE documents (
  id            SERIAL PRIMARY KEY,
  type          TEXT NOT NULL,
  num           INT NOT NULL DEFAULT 0,
  code          TEXT NOT NULL,
  code_manual   BOOLEAN NOT NULL DEFAULT FALSE,  -- 번호 직접 지정 (일괄 적용에서 제외)
  title         TEXT NOT NULL,
  department_id INT REFERENCES departments(id),
  data          JSONB NOT NULL DEFAULT '{}',
  version       INT NOT NULL DEFAULT 1,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by    TEXT,
  deleted_at    TIMESTAMPTZ
);
CREATE INDEX ON documents (type, num) WHERE deleted_at IS NULL;

-- 양식(기록). 소속 문서(document_id)가 있고, 다른 문서에서도 연결(document_forms)해서 쓸 수 있다.
CREATE TABLE forms (
  id          SERIAL PRIMARY KEY,
  document_id INT NOT NULL REFERENCES documents(id),
  seq         INT NOT NULL DEFAULT 0,
  code        TEXT NOT NULL,
  code_manual BOOLEAN NOT NULL DEFAULT FALSE,
  name        TEXT NOT NULL,
  retention   TEXT,
  approval    TEXT,          -- 결재란 (예: 담당 → 팀장 → 부서장)
  memo        TEXT,
  version     INT NOT NULL DEFAULT 1,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by  TEXT,
  deleted_at  TIMESTAMPTZ
);
CREATE INDEX ON forms (document_id) WHERE deleted_at IS NULL;

CREATE TABLE document_forms (
  document_id INT NOT NULL REFERENCES documents(id),
  form_id     INT NOT NULL REFERENCES forms(id),
  PRIMARY KEY (document_id, form_id)
);

-- 법령: 사용자가 직접 입력 (조항 단위 권장)
CREATE TABLE laws (
  id             SERIAL PRIMARY KEY,
  name           TEXT NOT NULL,
  kind           TEXT,
  article        TEXT,
  title          TEXT,
  content        TEXT,
  effective_date DATE,
  url            TEXT,
  memo           TEXT,
  version        INT NOT NULL DEFAULT 1,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by     TEXT,
  deleted_at     TIMESTAMPTZ
);

CREATE TABLE document_laws (
  document_id INT NOT NULL REFERENCES documents(id),
  law_id      INT NOT NULL REFERENCES laws(id),
  PRIMARY KEY (document_id, law_id)
);

-- 프로젝트: 지원사업 신청·인증심사 등 건별로 부서·필요서류·기한 공유
CREATE TABLE projects (
  id          SERIAL PRIMARY KEY,
  name        TEXT NOT NULL,
  category    TEXT,
  description TEXT,
  owner       TEXT,
  start_date  DATE,
  due_date    DATE,
  status      TEXT NOT NULL DEFAULT '준비',
  departments INT[] NOT NULL DEFAULT '{}',
  version     INT NOT NULL DEFAULT 1,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by  TEXT,
  deleted_at  TIMESTAMPTZ
);

CREATE TABLE project_items (
  id            SERIAL PRIMARY KEY,
  project_id    INT NOT NULL REFERENCES projects(id),
  title         TEXT NOT NULL,
  department_id INT REFERENCES departments(id),
  assignee      TEXT,
  due_date      DATE,
  status        TEXT NOT NULL DEFAULT '미착수',
  form_id       INT REFERENCES forms(id),
  document_id   INT REFERENCES documents(id),
  note          TEXT,
  sort_order    INT NOT NULL DEFAULT 0,
  version       INT NOT NULL DEFAULT 1,
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by    TEXT,
  deleted_at    TIMESTAMPTZ
);
CREATE INDEX ON project_items (project_id) WHERE deleted_at IS NULL;

-- 파일 (양식 파일, 문서 원본·첨부, 법령 첨부, 프로젝트 자료). 실제 파일은 데이터 폴더의 files/ 에 둔다.
-- 같은 대상에 여러 개를 올리면 최신 것이 위에 오고 이전 것은 이력처럼 남는다.
CREATE TABLE files (
  id          SERIAL PRIMARY KEY,
  owner_type  TEXT NOT NULL CHECK (owner_type IN ('document', 'form', 'law', 'project', 'item')),
  owner_id    INT NOT NULL,
  filename    TEXT NOT NULL,
  stored_name TEXT NOT NULL,
  size        BIGINT NOT NULL DEFAULT 0,
  note        TEXT,
  uploaded_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  uploaded_by TEXT,
  deleted_at  TIMESTAMPTZ
);
CREATE INDEX ON files (owner_type, owner_id) WHERE deleted_at IS NULL;

-- 변경이력: 누가 언제 무엇을 (변경 전 → 후)
CREATE TABLE audit_logs (
  id         BIGSERIAL PRIMARY KEY,
  at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  user_id    INT,
  user_name  TEXT,
  action     TEXT NOT NULL,     -- 등록 / 수정 / 삭제 / 업로드 / 파일삭제 / 번호변경 / 설정 …
  entity     TEXT NOT NULL,     -- document / form / law / project / item / file / user / department / settings
  entity_id  INT,
  label      TEXT,
  project_id INT,               -- 프로젝트 항목 이력을 프로젝트별로 모아 보기 위해
  detail     JSONB NOT NULL DEFAULT '{}'
);
CREATE INDEX ON audit_logs (entity, entity_id);
CREATE INDEX ON audit_logs (project_id);
