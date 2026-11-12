// PC 단독 실행용 배포 폴더 만들기.
// 사용법: node scripts/package-local.mjs <출력폴더> <win32|linux> [버전]
//
// 결과 (파일 수를 최소로):
//   local.mjs        서버 전체를 한 파일로 묶은 것
//   migrations/      DB 스키마
//   seed/            기본 데이터 (원본 양식에서 뽑은 문서·양식·파일)
//   package.json     버전 정보
//   pgsql.zip        PostgreSQL 실행 파일 묶음 (처음 실행 시 데이터 폴더에 풀림)
//   pgsql.version
import { build } from 'esbuild';
import { zipSync } from 'fflate';
import { cp, mkdir, readdir, readFile, rm, stat, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.join(path.dirname(fileURLToPath(import.meta.url)), '..');
const [outDir, platform = process.platform, version] = process.argv.slice(2);
if (!outDir) {
  console.error('사용법: node scripts/package-local.mjs <출력폴더> <win32|linux> [버전]');
  process.exit(1);
}
const out = path.resolve(outDir);
await rm(out, { recursive: true, force: true });
await mkdir(out, { recursive: true });

// 1. 서버 코드 한 파일로
await build({
  entryPoints: [path.join(root, 'src', 'local.js')],
  outfile: path.join(out, 'local.mjs'),
  bundle: true,
  platform: 'node',
  target: 'node22',
  format: 'esm',
  minify: false,
  legalComments: 'none',
  // 묶지 않는 것: 선택 기능(푸시), pg 의 네이티브 확장, 개발용 PostgreSQL 패키지
  external: ['pg-native', '@embedded-postgres/*'],
  banner: {
    js: "import { createRequire as __cr } from 'node:module'; const require = __cr(import.meta.url);",
  },
  logLevel: 'warning',
});

// 2. 스키마, 버전
await cp(path.join(root, 'migrations'), path.join(out, 'migrations'), { recursive: true });
await cp(path.join(root, 'seed'), path.join(out, 'seed'), { recursive: true });
const pkg = JSON.parse(await readFile(path.join(root, 'package.json'), 'utf8'));
await writeFile(path.join(out, 'package.json'), JSON.stringify({ name: pkg.name, version: version || pkg.version, type: 'module' }, null, 2));

// 3. PostgreSQL 실행 파일 한 덩어리로
const pgPkg = platform === 'win32' ? 'windows-x64' : 'linux-x64';
const pgDir = path.join(root, 'node_modules', '@embedded-postgres', pgPkg);
const pgVersion = JSON.parse(await readFile(path.join(pgDir, 'package.json'), 'utf8')).version;
const files = {};
async function walk(dir, rel) {
  for (const name of await readdir(dir)) {
    const full = path.join(dir, name);
    const r = rel ? `${rel}/${name}` : name;
    if ((await stat(full)).isDirectory()) await walk(full, r);
    else files[r] = new Uint8Array(await readFile(full));
  }
}
await walk(path.join(pgDir, 'native'), '');
await writeFile(path.join(out, 'pgsql.zip'), zipSync(files, { level: 6 }));
await writeFile(path.join(out, 'pgsql.version'), pgVersion);

const list = await readdir(out);
console.log(`완료: ${out}\n  ${list.join(', ')}\n  PostgreSQL ${pgVersion} (${Object.keys(files).length}개 파일 → pgsql.zip)`);
