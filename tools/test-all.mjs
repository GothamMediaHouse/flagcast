// npm test: every test in one go. The offline ones with node --test, then the server ones against two local servers
// (`wrangler dev`): one with no Admin passcode (as most tests expect) and one with a test passcode for clubs.test.
// Each server keeps its data in a fresh temporary folder, so runs don't affect each other.
import { spawn, spawnSync } from 'node:child_process';
import { mkdtempSync, writeFileSync, rmSync, existsSync, readdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const SERVER = ['groupnotes', 'contestentry', 'pinsheet', 'protools', 'screens', 'stalesave', 'where', 'live', 'tv'];
const ADMIN = ['trydemo', 'clubs']; // clubs ends by locking out wrong passcodes, so it goes last
const STREAM = ['golive']; // needs a Cloudflare Stream stand-in
const all = readdirSync('test').filter((f) => f.endsWith('.test.mjs')).map((f) => f.replace('.test.mjs', ''));
const offline = all.filter((t) => !SERVER.includes(t) && !ADMIN.includes(t) && !STREAM.includes(t));
let failed = 0;
const run = (args) => { const r = spawnSync(process.execPath, args, { stdio: 'inherit' }); if (r.status) failed++; return r.status === 0; };

console.log(`\n== offline: ${offline.join(', ')}`);
run(['--test', ...offline.map((t) => `test/${t}.test.mjs`)]);

async function server(port, vars) {
  const dir = mkdtempSync(join(tmpdir(), 'flagcast-test-'));
  if (existsSync('.dev.vars')) { console.log('A .dev.vars file is here: move it away first so the tests use their own settings.'); process.exit(1); }
  if (vars) writeFileSync('.dev.vars', vars);
  const p = spawn('npx', ['wrangler', 'dev', '--port', String(port), '--persist-to', dir], { stdio: 'ignore', detached: true });
  const base = `http://127.0.0.1:${port}`;
  for (let i = 0; i < 90; i++) { try { await fetch(base); break; } catch { await new Promise((r) => setTimeout(r, 1000)); } }
  return { base, stop: () => { try { process.kill(-p.pid); } catch {} if (vars) rmSync('.dev.vars', { force: true }); rmSync(dir, { recursive: true, force: true }); } };
}

let s = await server(8791, '');
try { for (const t of SERVER) { console.log(`\n== ${t} (local server)`); run([`test/${t}.test.mjs`, s.base]); } } finally { s.stop(); }
s = await server(8792, 'GOLF_CREATE_PASS="local-test-pass"\nADMIN_EMAIL="staff@example.com"\n');
try { for (const t of ADMIN) { console.log(`\n== ${t} (local server with a test passcode)`); run([`test/${t}.test.mjs`, s.base, 'local-test-pass', 'staff@example.com']); } } finally { s.stop(); }

// Go live: Cloudflare Stream is a stand-in on this computer (the test starts it on 8793)
s = await server(8794, 'CF_ACCOUNT_ID="acc"\nCF_STREAM_TOKEN="tok"\nCF_STREAM_API="http://127.0.0.1:8793"\n');
try { console.log('\n== golive (local server, Stream stand-in)'); run(['test/golive.test.mjs', s.base, '8793']); } finally { s.stop(); }

console.log(failed ? `\n${failed} test file(s) failed` : '\nEverything passed');
process.exit(failed ? 1 : 0);
