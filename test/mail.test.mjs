import test from 'node:test';
import assert from 'node:assert/strict';
import { mailHtml, mailText, EMAILS } from '../mail.js';

test('sign-in code email shows the code in HTML and text', () => {
  const m = EMAILS.code('123456');
  assert.equal(m.subject, '123456 is your Flagcast sign-in code');
  assert.match(mailHtml(m), /123456/);
  assert.match(mailText(m), /123456/);
  assert.match(mailHtml(m), /email-logo\.png/);
});

test('club names are escaped in HTML', () => {
  const h = mailHtml(EMAILS.approved('<b>Bad & Co</b>'));
  assert.ok(!h.includes('<b>Bad'));
  assert.match(h, /&lt;b&gt;Bad &amp; Co/);
});

test('every email has a subject, title and text', () => {
  for (const m of [EMAILS.code('1'), EMAILS.added('C', 'a@b.co'), EMAILS.added('C'), EMAILS.approved('C'), EMAILS.setUp('C'), EMAILS.newClub('C', ['x', ''])]) {
    assert.ok(m.subject && m.title);
    assert.ok(mailText(m).includes(m.title));
  }
});
