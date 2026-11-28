// How long Flagcast keeps what (privacy.js): the daily tidy's plan, emails and GHIN going, old replays, a group that
// asked to stay off camera, and deleting one person's details.  node test/privacy.test.mjs
import assert from 'node:assert/strict';
import { DAY, eventDay, tidyPlan, stripPersonal, dropOldReplays, dropTeamClips, pruneInvites, findPerson, forgetPerson, juniorFlags, REMOVED } from '../privacy.js';

let n = 0; const ok = (name) => console.log(`ok ${++n} - ${name}`);
const day = Date.UTC(2026, 5, 6);
const ev = () => ({
  date: '2026-06-06', created: day - 20 * DAY,
  teams: [
    { id: 't1', name: '', players: [{ id: 'p1', name: 'Pat Smith', email: 'pat@example.com', ghin: '1234567' }, { id: 'p2', name: 'Lee Jones', email: '', ghin: '' }] },
    { id: 't2', name: 'Birdies', players: [{ id: 'p3', name: 'Sam Lee', email: 'sam@example.com', ghin: '' }] },
  ],
  invites: { p1: { to: 'pat@example.com', at: day, n: 1 }, p9: { to: 'gone@example.com', at: day, n: 1 } },
  inviteTests: [day],
  contests: [{ id: 'c1', entries: [{ name: 'Pat Smith', player: 'p1', dist: 280 }] }],
  replays: [
    { id: 'r1', hole: 7, label: 'Smith / Jones · tee shot', url: '', at: day, by: 'golfer', team: 't1' },
    { id: 'r2', hole: 7, label: 'Ace!', url: 'https://example.com/ace.mp4', at: day, by: 'desk' },
    { id: 'r3', hole: 16, label: 'Birdies · tee shot', url: '', at: day + 40 * DAY, by: 'golfer', team: 't2' },
  ],
  live: { take: { kind: 'replay', replay: 'r1' } },
});

assert.equal(eventDay({ date: '2026-06-06' }), day);
assert.equal(eventDay({ created: 5 }), 5);
ok('a tournament’s day is its date, else when it was made');

{
  const e = ev();
  assert.deepEqual(tidyPlan(e, day + 10 * DAY), { personal: false, replays: false, expired: false });
  assert.deepEqual(tidyPlan(e, day + 31 * DAY), { personal: false, replays: true, expired: false });
  assert.equal(tidyPlan(e, day + 91 * DAY).personal, true);
  assert.equal(tidyPlan({ ...e, tidied: 1 }, day + 91 * DAY).personal, false);
  assert.equal(tidyPlan(e, day + 729 * DAY).expired, false);
  assert.equal(tidyPlan(e, day + 731 * DAY).expired, true);
  assert.deepEqual(tidyPlan({ ...e, demo: true, replays: [] }, day + 1000 * DAY), { personal: false, replays: false, expired: false });
}
ok('the plan: old replays after 30 days, emails and GHIN after 90, the whole tournament after 2 years, never a Demo');

{
  const e = ev();
  assert.equal(stripPersonal(e), true);
  assert.deepEqual(e.teams.flatMap((t) => t.players.map((p) => [p.name, p.email, p.ghin])), [['Pat Smith', '', ''], ['Lee Jones', '', ''], ['Sam Lee', '', '']]);
  assert.equal(e.invites, undefined); assert.equal(e.inviteTests, undefined);
  assert.equal(stripPersonal(e), false);
}
ok('after 90 days emails, GHIN numbers and the invite log go; names and scores stay');

{
  const e = ev();
  assert.equal(dropOldReplays(e, day + 31 * DAY), true);
  assert.deepEqual(e.replays.map((r) => r.id), ['r2', 'r3']); // a clip link isn't a recording, and r3 is newer
  assert.equal(e.live.take, null);
}
ok('replays of recordings that are gone come off, and so does a TV take-over showing one');

{
  const e = ev();
  assert.equal(dropTeamClips(e, 't1'), true);
  assert.deepEqual(e.replays.map((r) => r.id), ['r2', 'r3']);
  assert.equal(dropTeamClips(e, 't1'), false);
}
ok('a group that asks to stay off camera loses its saved shots');

{
  const e = ev();
  assert.equal(pruneInvites(e), true);
  assert.deepEqual(Object.keys(e.invites), ['p1']);
}
ok('the invite log forgets players who were taken off');

{
  const e = ev();
  assert.deepEqual(findPerson(e, 'pat smith'), [{ team: 't1', player: 'p1', name: 'Pat Smith', email: true }]);
  assert.deepEqual(findPerson(e, ' SAM@example.com ').map((f) => f.player), ['p3']);
  assert.deepEqual(findPerson(e, 'Pat'), []); // only a full name or email
  assert.deepEqual(findPerson(e, 'ab'), []);
  assert.equal(forgetPerson(e, 'Pat Smith'), 1);
  const p = e.teams[0].players[0];
  assert.deepEqual([p.name, p.email, p.ghin], [REMOVED, '', '']);
  assert.equal(e.invites.p1, undefined);
  assert.equal(e.contests[0].entries[0].name, REMOVED);
  assert.equal(e.replays[0].label, `${REMOVED} · tee shot`);
  assert.equal(e.replays[2].label, 'Birdies · tee shot');
  assert.equal(e.teams[0].players[1].name, 'Lee Jones');
}
ok('deleting one person: their name, email, GHIN, invite, contest name and replay labels go; nobody else’s');

assert.deepEqual(juniorFlags({}), {});
assert.deepEqual(juniorFlags({ junior: true }), { notesOff: true, clipsOff: true, everyoneOff: true });
ok('a junior event turns off notes, saved shots and the other groups on the map for golfers');

console.log(`\n${n} passed`);
