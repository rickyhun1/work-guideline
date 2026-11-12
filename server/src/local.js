// PC 단독 실행 모드.
// 관리자 프로그램이 이 파일을 실행하면, 내장 PostgreSQL 을 준비·기동하고 API 서버를 띄운다.
//
// 데이터 위치: DATA_DIR 환경변수, 없으면
//   Windows: C:\ProgramData\WorkGuideline   (한글 경로를 피하기 위해 ProgramData 사용)
//   그 외  : ~/.work-guideline
//
// 같은 PC의 다른 프로그램이 데이터를 건드리지 못하도록 기본은 127.0.0.1 에서만 받는다.
// 다른 PC/모바일 접속을 허용하려면 HOST=0.0.0.0
import { spawn } from 'node:child_process';
import { randomBytes } from 'node:crypto';
import { existsSync } from 'node:fs';
import { cp, mkdir, readFile, writeFile, rm, appendFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const DATA_DIR = process.env.DATA_DIR
  || (process.platform === 'win32'
    ? path.join(process.env.ProgramData || 'C:\\ProgramData', 'WorkGuideline')
    : path.join(os.homedir(), '.work-guideline'));
const PG_DATA = path.join(DATA_DIR, 'pgdata');
const CONFIG_FILE = path.join(DATA_DIR, 'local.json');
const LOG_FILE = path.join(DATA_DIR, 'server.log');
const PG_LOG = path.join(DATA_DIR, 'postgres.log');

async function log(msg) {
  const line = `[${new Date().toISOString()}] ${msg}`;
  console.log(line);
  await appendFile(LOG_FILE, `${line}\n`).catch(() => {});
}

/**
 * 외부 프로그램 실행.
 * detachedOutput: pg_ctl start 처럼 자식이 계속 살아남는 경우. Windows 의 pg_ctl 은 출력 핸들을
 * postgres 에 물려주므로, 파이프를 연결하면 출력이 끝나지 않아 기다림이 끝나지 않는다 → 출력은 버린다.
 */
function run(cmd, args, { allowFail = false, detachedOutput = false } = {}) {
  return new Promise((resolve, reject) => {
    const p = spawn(cmd, args, {
      windowsHide: true,
      env: { ...process.env, LC_MESSAGES: 'C' },
      stdio: detachedOutput ? 'ignore' : 'pipe',
    });
    let out = '';
    p.stdout?.on('data', (d) => { out += d; });
    p.stderr?.on('data', (d) => { out += d; });
    p.on('error', reject);
    // 'close' 가 아닌 'exit': 프로세스가 끝나면 바로 진행
    p.on('exit', (code) => {
      setTimeout(() => {
        if (code === 0 || allowFail) resolve({ code, out });
        else reject(new Error(`${path.basename(cmd)} 실패 (code ${code})\n${out}`));
      }, 50);
    });
  });
}

async function tailFile(file, lines = 15) {
  try {
    return (await readFile(file, 'utf8')).trim().split(/\r?\n/).slice(-lines).join('\n');
  } catch {
    return '';
  }
}

/** PostgreSQL 실행 파일 위치. 한글 등 비ASCII 경로 문제를 피하려고 데이터 폴더 아래로 복사해서 쓴다. */
/** 이 파일이 있는 폴더 (배포판에서는 server 폴더) */
const HERE = path.dirname(fileURLToPath(import.meta.url));

/**
 * PostgreSQL 실행 파일 위치. 한글 등 비ASCII 경로 문제를 피하려고 데이터 폴더 아래에 풀어서 쓴다.
 * 배포판: server/pgsql.zip (파일 수를 줄이려고 한 덩어리로 묶음)
 * 개발용: node_modules/@embedded-postgres/<플랫폼>
 */
async function pgBinaries() {
  const zipFile = path.join(HERE, 'pgsql.zip');
  let version;
  let install;
  if (existsSync(zipFile)) {
    version = (await readFile(path.join(HERE, 'pgsql.version'), 'utf8')).trim();
    install = async (target) => {
      const { unzipSync } = await import('fflate');
      const files = unzipSync(new Uint8Array(await readFile(zipFile)));
      for (const [name, data] of Object.entries(files)) {
        if (name.endsWith('/')) continue;
        const out = path.join(target, ...name.split('/'));
        await mkdir(path.dirname(out), { recursive: true });
        await writeFile(out, data);
      }
      if (process.platform !== 'win32') {
        const { readdir, chmod } = await import('node:fs/promises');
        for (const f of await readdir(path.join(target, 'bin'))) await chmod(path.join(target, 'bin', f), 0o755);
      }
    };
  } else {
    const pkgName = process.platform === 'win32' ? '@embedded-postgres/windows-x64' : '@embedded-postgres/linux-x64';
    const pkg = await import(pkgName);
    const nativeDir = path.dirname(path.dirname(pkg.pg_ctl)); // .../native
    version = JSON.parse(await readFile(path.join(path.dirname(nativeDir), 'package.json'), 'utf8')).version;
    install = (target) => cp(nativeDir, target, { recursive: true });
  }
  const target = path.join(DATA_DIR, `pgsql-${version}`);
  if (!existsSync(path.join(target, '.ready'))) {
    await log(`PostgreSQL 실행 파일 준비 중: ${target}`);
    await rm(target, { recursive: true, force: true });
    await install(target);
    await writeFile(path.join(target, '.ready'), version);
  }
  const ext = process.platform === 'win32' ? '.exe' : '';
  const bin = (n) => path.join(target, 'bin', n + ext);
  return { initdb: bin('initdb'), pgCtl: bin('pg_ctl') };
}

async function loadConfig() {
  if (existsSync(CONFIG_FILE)) return JSON.parse(await readFile(CONFIG_FILE, 'utf8'));
  const cfg = {
    pgPort: 54339,
    pgPassword: randomBytes(18).toString('base64url'),
    jwtSecret: randomBytes(32).toString('base64url'),
    shutdownToken: randomBytes(18).toString('base64url'),
  };
  await writeFile(CONFIG_FILE, JSON.stringify(cfg, null, 2));
  return cfg;
}

async function startPostgres(cfg) {
  const { initdb, pgCtl } = await pgBinaries();

  if (!existsSync(path.join(PG_DATA, 'PG_VERSION'))) {
    await log('데이터베이스 최초 생성 중...');
    const pwFile = path.join(DATA_DIR, '.pw');
    await writeFile(pwFile, `${cfg.pgPassword}\n`);
    try {
      await run(initdb, ['-D', PG_DATA, '-U', 'postgres', '--auth=scram-sha-256', `--pwfile=${pwFile}`,
        '-E', 'UTF8', '--no-locale']);
    } finally {
      await rm(pwFile, { force: true });
    }
  }

  const status = await run(pgCtl, ['status', '-D', PG_DATA], { allowFail: true });
  if (status.code !== 0) {
    await log('데이터베이스 시작 중...');
    const opts = `-p ${cfg.pgPort} -c listen_addresses=127.0.0.1`
      + (process.platform === 'win32' ? '' : ` -c unix_socket_directories=${DATA_DIR}`);
    try {
      await run(pgCtl, ['start', '-D', PG_DATA, '-w', '-t', '120', '-l', PG_LOG, '-o', opts], { detachedOutput: true });
    } catch (e) {
      throw new Error(`데이터베이스를 시작하지 못했습니다.\n${await tailFile(PG_LOG)}`);
    }
  }
  return pgCtl;
}

async function stopPostgres(pgCtl) {
  await run(pgCtl, ['stop', '-D', PG_DATA, '-m', 'fast', '-w'], { allowFail: true });
}

async function ensureDatabase(cfg) {
  const pg = (await import('pg')).default;
  const client = new pg.Client({
    host: '127.0.0.1', port: cfg.pgPort, user: 'postgres', password: cfg.pgPassword, database: 'postgres',
  });
  await client.connect();
  const { rowCount } = await client.query(`SELECT 1 FROM pg_database WHERE datname = 'work_guideline'`);
  if (!rowCount) await client.query('CREATE DATABASE work_guideline');
  await client.end();
}

async function main() {
  await mkdir(DATA_DIR, { recursive: true });
  await log(`로컬 서버 시작 (데이터: ${DATA_DIR})`);
  const cfg = await loadConfig();
  const pgCtl = await startPostgres(cfg);
  await ensureDatabase(cfg);

  process.env.DATABASE_URL = `postgres://postgres:${encodeURIComponent(cfg.pgPassword)}@127.0.0.1:${cfg.pgPort}/work_guideline`;
  process.env.JWT_SECRET ||= cfg.jwtSecret;
  process.env.SERVER_MODE = 'local';
  process.env.DATA_DIR ||= DATA_DIR;

  // DATABASE_URL 설정 후에 로드해야 올바른 접속 정보로 풀이 만들어진다
  const { pool } = await import('./lib/db.js');
  const { migrate } = await import('./lib/migrate.js');
  const { seed } = await import('./lib/seed.js');
  const { buildApp } = await import('./app.js');
  await migrate(pool, (m) => log(m));
  await seed(pool, (m) => log(m));

  let app;
  let stopping = false;
  const shutdown = async (why) => {
    if (stopping) return;
    stopping = true;
    await log(`종료 중 (${why})`);
    try { await app?.close(); } catch { /* ignore */ }
    try { await pool.end(); } catch { /* ignore */ }
    await stopPostgres(pgCtl);
    await log('종료 완료');
    process.exit(0);
  };

  const watchers = new Set();
  const appPid = Number(process.env.APP_PID);
  if (Number.isInteger(appPid) && appPid > 0) watchers.add(appPid);

  app = buildApp({
    logger: { level: 'warn' },
    extraRoutes: async (a) => {
      // 종료 요청은 본문을 쓰지 않으므로 어떤 형식으로 와도 받는다
      a.addContentTypeParser('*', { parseAs: 'buffer' }, (req, body, done) => done(null, null));
      // 관리자 프로그램이 종료/업데이트 시 호출. 같은 PC에서, 토큰을 아는 경우에만.
      a.post('/local/shutdown', async (req, reply) => {
        const local = ['127.0.0.1', '::1', '::ffff:127.0.0.1'].includes(req.ip);
        if (!local || req.headers['x-shutdown-token'] !== cfg.shutdownToken) {
          return reply.status(403).send({ error: '권한이 없습니다.' });
        }
        setTimeout(() => shutdown('요청'), 50);
        return { ok: true };
      });

      // 비밀번호를 잊었을 때: 이 PC에서, 데이터 폴더의 토큰을 읽을 수 있는 경우에만 관리자 비밀번호를 다시 정한다.
      const trusted = (req) => ['127.0.0.1', '::1', '::ffff:127.0.0.1'].includes(req.ip)
        && req.headers['x-shutdown-token'] === cfg.shutdownToken;
      // 이 서버를 쓰는 관리자 프로그램 등록 (이미 켜진 서버에 붙을 때)
      a.post('/local/attach', async (req, reply) => {
        if (!trusted(req)) return reply.status(403).send({ error: '권한이 없습니다.' });
        const pid = Number(req.body?.pid);
        if (Number.isInteger(pid) && pid > 0) watchers.add(pid);
        return { ok: true };
      });
      a.get('/local/admins', async (req, reply) => {
        if (!trusted(req)) return reply.status(403).send({ error: '권한이 없습니다.' });
        const { query } = await import('./lib/db.js');
        const { rows } = await query(
          'SELECT emp_no, name, active FROM users WHERE is_admin ORDER BY active DESC, emp_no',
        );
        return rows.map((r) => ({ empNo: r.emp_no, name: r.name, active: r.active }));
      });
      a.post('/local/reset-password', {
        schema: {
          body: {
            type: 'object',
            required: ['empNo', 'password'],
            properties: { empNo: { type: 'string' }, password: { type: 'string', minLength: 4 } },
          },
        },
      }, async (req, reply) => {
        if (!trusted(req)) return reply.status(403).send({ error: '권한이 없습니다.' });
        const { query } = await import('./lib/db.js');
        const bcrypt = (await import('bcryptjs')).default;
        const { rowCount } = await query(
          'UPDATE users SET password_hash = $2, active = TRUE WHERE emp_no = $1 AND is_admin',
          [req.body.empNo, await bcrypt.hash(req.body.password, 10)],
        );
        if (!rowCount) return reply.status(404).send({ error: '관리자 계정을 찾을 수 없습니다.' });
        await log(`관리자 비밀번호 재설정: ${req.body.empNo}`);
        return { ok: true };
      });
    },
  });

  // 관리자 프로그램이 모두 꺼지면(창 닫기, 강제 종료 등) 서버와 DB도 끈다
  const alive = (pid) => {
    try {
      process.kill(pid, 0);
      return true;
    } catch (e) {
      return e.code === 'EPERM';
    }
  };
  setInterval(() => {
    if (!watchers.size) return;
    for (const pid of watchers) if (!alive(pid)) watchers.delete(pid);
    if (!watchers.size) shutdown('관리자 프로그램 종료');
  }, 2000).unref();

  process.on('SIGINT', () => shutdown('SIGINT'));
  process.on('SIGTERM', () => shutdown('SIGTERM'));

  const port = Number(process.env.PORT || 37220);
  const host = process.env.HOST || '127.0.0.1';
  await app.listen({ port, host });
  await log(`API 대기 중: http://${host}:${port}`);
}

main().catch(async (e) => {
  await log(`시작 실패: ${e.stack || e.message}`);
  process.exit(1);
});
