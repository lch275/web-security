import { Router } from 'express';

import { sortOrders } from './repository.js';
import {
  ValidationError,
  parseId,
  parseIds,
  parseIntInRange,
  requireKeyword,
  requireLastName,
  requireLastNameList,
} from './validation.js';

function resolveSort(value, { required }) {
  if (value === undefined && !required) {
    return sortOrders.get('name');
  }
  // 배열이나 미등록 키는 Map에서 찾을 수 없으므로 거부된다.
  const orderBy = sortOrders.get(value);
  if (!orderBy) {
    throw new ValidationError('지원하지 않는 정렬 기준입니다.');
  }
  return orderBy;
}

export function customerRoutes(repository) {
  const router = Router();

  router.get('/search', async (req, res) => {
    const lastName = requireLastName(req.query.lastName);
    const orderBy = resolveSort(req.query.sort, { required: false });
    res.json(await repository.searchByLastName(lastName, orderBy));
  });

  router.get('/contains', async (req, res) => {
    res.json(await repository.searchByLastNameContains(requireKeyword(req.query.keyword)));
  });

  router.get('/sorted', async (req, res) => {
    res.json(await repository.findAllIdsSorted(resolveSort(req.query.sort, { required: true })));
  });

  router.get('/by-ids', async (req, res) => {
    res.json(await repository.findIds(parseIds(req.query.ids)));
  });

  router.get('/', async (req, res) => {
    const limit = parseIntInRange(req.query.limit, 'limit', { min: 1, max: 100, fallback: 20 });
    const offset = parseIntInRange(req.query.offset, 'offset', { min: 0, max: 100_000, fallback: 0 });
    res.json(await repository.list(limit, offset));
  });

  router.post('/batch', async (req, res) => {
    const lastNames = requireLastNameList(req.body?.lastNames);
    res.status(201).json(await repository.createAll(lastNames));
  });

  router.post('/', async (req, res) => {
    const lastName = requireLastName(req.body?.lastName).trim();
    res.status(201).json(await repository.create(lastName));
  });

  router.get('/:id', async (req, res) => {
    const customer = await repository.findById(parseId(req.params.id));
    if (!customer) {
      return res.status(404).json({ error: '고객을 찾을 수 없습니다.' });
    }
    return res.json(customer);
  });

  router.put('/:id', async (req, res) => {
    const id = parseId(req.params.id);
    const lastName = requireLastName(req.body?.lastName).trim();
    const customer = await repository.update(id, lastName);
    if (!customer) {
      return res.status(404).json({ error: '고객을 찾을 수 없습니다.' });
    }
    return res.json(customer);
  });

  router.delete('/:id', async (req, res) => {
    const deleted = await repository.remove(parseId(req.params.id));
    if (!deleted) {
      return res.status(404).json({ error: '고객을 찾을 수 없습니다.' });
    }
    return res.status(204).end();
  });

  return router;
}
