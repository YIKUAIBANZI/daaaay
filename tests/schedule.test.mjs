import test from 'node:test';
import assert from 'node:assert/strict';
import { validateSchedule, activeWindows, nextBoundary, blockingRules } from '../blocker/extension/schedule.mjs';

const plan = { version: 1, windows: [
  { id: 'overnight', start: '2026-09-06T23:30:00+08:00', end: '2026-09-07T00:30:00+08:00' },
  { id: 'overlap', start: '2026-09-07T00:00:00+08:00', end: '2026-09-07T01:00:00+08:00' }
] };
const at = s => Date.parse(s);

test('blocks from start inclusive, unlocks at end exclusive, including overlapping midnight windows', () => {
  const p = validateSchedule(plan);
  assert.equal(activeWindows(p, at('2026-09-06T23:29:59+08:00')).length, 0);
  assert.equal(activeWindows(p, at('2026-09-06T23:30:00+08:00')).length, 1);
  assert.equal(activeWindows(p, at('2026-09-07T00:15:00+08:00')).length, 2);
  assert.equal(activeWindows(p, at('2026-09-07T00:30:00+08:00')).length, 1);
  assert.equal(activeWindows(p, at('2026-09-07T01:00:00+08:00')).length, 0);
});
test('empty or expired plan never locks; next boundary is a future transition', () => {
  assert.deepEqual(activeWindows(validateSchedule({version:1, windows:[]}), Date.now()), []);
  assert.equal(nextBoundary(plan, at('2026-09-06T23:30:00+08:00')), at('2026-09-07T00:00:00+08:00'));
  assert.equal(nextBoundary(plan, at('2026-09-07T01:00:00+08:00')), null);
});
test('rejects ambiguous times, reversed ranges, duplicate IDs and unsupported schema', () => {
  for (const bad of [
    {version:2, windows:[]},
    {version:1, windows:[{id:'x',start:'2026-09-06T12:00:00',end:'2026-09-06T13:00:00'}]},
    {version:1, windows:[{id:'x',start:'garbage',end:'garbage'}]},
    {version:1, windows:[{id:'x',start:plan.windows[0].end,end:plan.windows[0].start}]},
    {version:1, windows:[plan.windows[0],plan.windows[0]]}
  ]) assert.throws(() => validateSchedule(bad));
});
test('rules cover only douyin and its subdomains; disabling removes all owned rules', () => {
  assert.deepEqual(blockingRules(false), []);
  const rules = blockingRules(true);
  assert.equal(rules.length, 1);
  assert.equal(rules[0].action.type, 'block');
  assert.deepEqual(rules[0].condition.requestDomains, ['douyin.com']);
  // Explicitly include navigation: an empty exclusion list failed in the installed Chrome.
  for (const type of ['main_frame','sub_frame','xmlhttprequest','media','websocket'])
    assert.ok(rules[0].condition.resourceTypes.includes(type), type);
  assert.equal(rules[0].condition.excludedResourceTypes, undefined);
});
