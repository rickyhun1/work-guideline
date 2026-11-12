// 파일 (양식 파일, 문서 원본·첨부, 법령 첨부, 프로젝트 자료)
import path from 'node:path';
import { readFile, writeFile } from 'node:fs/promises';
import { query, tx } from '../lib/db.js';
import { badRequest, notFound } from '../lib/errors.js';
import { filesDir, audit, requireLevel } from '../lib/core.js';

const OWNER_MODULE = { document: 'docs', form: 'docs', law: 'laws', project: 'projects', item: 'projects' };
const OWNER_TABLE = { document: 'documents', form: 'forms', law: 'laws', project: 'projects', item: 'project_items' };

export function fileRow(f) {
  return { id: f.id, ownerType: f.owner_type, ownerId: f.owner_id, filename: f.filename, size: Number(f.size), note: f.note,
    uploadedAt: f.uploaded_at, uploadedBy: f.uploaded_by };
}

/** 파일 저장 (시드 가져오기에서도 사용) */
export async function storeFile(db, req, ownerType, ownerId, filename, buf, note, logIt = true) {
  const { rows } = await db.query(
    `INSERT INTO files (owner_type, owner_id, filename, stored_name, size, note, uploaded_by)
     VALUES ($1, $2, $3, '', $4, $5, $6) RETURNING id`,
    [ownerType, ownerId, filename, buf.length, note ?? null, req?.user?.name ?? 'system']);
  const id = rows[0].id;
  const stored = `${String(id).padStart(7, '0')}${path.extname(filename).toLowerCase().replace(/[^.\w]/g, '')}`;
  await writeFile(path.join(filesDir(), stored), buf);
  await db.query('UPDATE files SET stored_name = $2 WHERE id = $1', [id, stored]);
  if (logIt) {
    await audit(db, req, '업로드', ownerType, ownerId, filename, { fileId: id, note }, ownerType === 'item' ? await itemProject(db, ownerId) : null);
  }
  return id;
}

async function itemProject(db, itemId) {
  const { rows } = await db.query('SELECT project_id FROM project_items WHERE id = $1', [itemId]);
  return rows[0]?.project_id ?? null;
}

export async function readStored(f) {
  return readFile(path.join(filesDir(), f.stored_name));
}

/** 내려받기 헤더 (한글 파일명) */
export function sendFile(reply, filename, buf, type = 'application/octet-stream') {
  return reply
    .header('content-type', type)
    .header('content-disposition', `attachment; filename*=UTF-8''${encodeURIComponent(filename)}`)
    .send(buf);
}

export default async function fileRoutes(app) {
  /** 목록: /files?owner=form&ownerId=3 (최신이 위) */
  app.get('/files', { onRequest: app.auth }, async (req) => {
    const owner = req.query.owner;
    if (!OWNER_MODULE[owner]) throw badRequest('owner 값이 올바르지 않습니다.');
    requireLevel(req, OWNER_MODULE[owner], 1);
    const { rows } = await query(
      'SELECT * FROM files WHERE owner_type = $1 AND owner_id = $2 AND deleted_at IS NULL ORDER BY id DESC',
      [owner, Number(req.query.ownerId)]);
    return rows.map(fileRow);
  });

  /** 올리기: POST /files?owner=form&ownerId=3&name=파일명.xlsx&note=메모  (본문 = 파일 바이트) */
  app.post('/files', { onRequest: app.auth }, async (req, reply) => {
    const { owner, name, note } = req.query;
    const ownerId = Number(req.query.ownerId);
    if (!OWNER_MODULE[owner]) throw badRequest('owner 값이 올바르지 않습니다.');
    requireLevel(req, OWNER_MODULE[owner], 2);
    if (!name) throw badRequest('파일 이름이 필요합니다.');
    if (!Buffer.isBuffer(req.body) || !req.body.length) throw badRequest('빈 파일입니다.');
    const { rows } = await query(`SELECT id FROM ${OWNER_TABLE[owner]} WHERE id = $1 AND deleted_at IS NULL`, [ownerId]);
    if (!rows[0]) throw notFound('파일을 붙일 대상을 찾을 수 없습니다.');
    const id = await tx((db) => storeFile(db, req, owner, ownerId, path.basename(String(name)), req.body, note));
    return reply.status(201).send({ id });
  });

  app.get('/files/:id/download', { onRequest: app.auth }, async (req, reply) => {
    const { rows } = await query('SELECT * FROM files WHERE id = $1 AND deleted_at IS NULL', [Number(req.params.id)]);
    const f = rows[0];
    if (!f) throw notFound('파일을 찾을 수 없습니다.');
    requireLevel(req, OWNER_MODULE[f.owner_type], 1);
    return sendFile(reply, f.filename, await readStored(f));
  });

  app.patch('/files/:id', {
    onRequest: app.auth,
    schema: { body: { type: 'object', properties: { note: { type: ['string', 'null'] }, filename: { type: 'string', minLength: 1 } } } },
  }, async (req) => {
    const { rows } = await query('SELECT * FROM files WHERE id = $1 AND deleted_at IS NULL', [Number(req.params.id)]);
    const f = rows[0];
    if (!f) throw notFound();
    requireLevel(req, OWNER_MODULE[f.owner_type], 2);
    const filename = req.body.filename ? path.basename(req.body.filename) : f.filename;
    const note = 'note' in req.body ? req.body.note : f.note;
    await query('UPDATE files SET filename = $2, note = $3 WHERE id = $1', [f.id, filename, note]);
    await audit({ query }, req, '수정', f.owner_type, f.owner_id, filename,
      { fileId: f.id, changes: { 파일명: [f.filename, filename], 메모: [f.note, note] } });
    return { ok: true };
  });

  app.delete('/files/:id', { onRequest: app.auth }, async (req) => {
    const { rows } = await query('SELECT * FROM files WHERE id = $1 AND deleted_at IS NULL', [Number(req.params.id)]);
    const f = rows[0];
    if (!f) throw notFound();
    requireLevel(req, OWNER_MODULE[f.owner_type], 3);
    await query('UPDATE files SET deleted_at = now() WHERE id = $1', [f.id]);
    await audit({ query }, req, '파일삭제', f.owner_type, f.owner_id, f.filename, { fileId: f.id },
      f.owner_type === 'item' ? await itemProject({ query }, f.owner_id) : null);
    return { ok: true };
  });
}
