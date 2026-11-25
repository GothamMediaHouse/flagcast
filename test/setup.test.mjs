// PIN rules on Save (golf.js pinProblem): new PINs 6 digits, none shared; older 4-digit ones keep working. Offline.
import assert from 'node:assert/strict';
import test from 'node:test';
import { pinProblem, mergeTeams } from '../setup.js';
test('new PINs need 6 digits and must differ', () => {
  assert.equal(pinProblem([{ id: 'a', name: 'Pro', pin: '123456' }]), null);
  assert.match(pinProblem([{ id: 'a', name: 'Pro', pin: '1234' }]), /6 digits/);
  assert.equal(pinProblem([{ id: 'a', name: 'Pro', pin: '1234' }], [{ id: 'a', pin: '1234' }]), null);
  assert.match(pinProblem([{ id: 'a', pin: '123456' }, { id: 'b', pin: '123456' }]), /Two people/);
});
test('a Save from an older copy keeps teams added or changed since', () => {
  const old = [{ id: 'a', name: 'A', players: [], sv: 1 }, { id: 'late', name: 'Late', players: [], sv: 5 }, { id: 'b', name: 'B', players: [], sv: 5 }];
  const sent = [{ id: 'a', name: 'A2', players: [] }, { id: 'b', name: 'B old', players: [] }];
  const out = mergeTeams(old, sent, 3, 6);
  assert.deepEqual(out.map((t) => [t.id, t.name, t.sv]), [['a', 'A2', 6], ['b', 'B', 5], ['late', 'Late', 5]]);
  assert.deepEqual(mergeTeams(old, [sent[0]], 5, 6).map((t) => t.id), ['a']); // a current copy can take teams off
});
