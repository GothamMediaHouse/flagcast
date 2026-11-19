// Flagcast Admin: Flagcast's own app for running the business side. Opens the admin page
// (flagcast.app/golf/admin/): set up clubs, give them tournaments when they pay, approve clubs that ask,
// switch clubs off, and make tournaments for a club. Unlocked with the GOLF_CREATE_PASS secret.
const { app, BrowserWindow, shell, Menu } = require('electron');
const path = require('path');
const fs = require('fs');

const DEFAULT_BASE = 'https://flagcast.app';
const store = () => path.join(app.getPath('userData'), 'admin.json');
function load() { try { return JSON.parse(fs.readFileSync(store(), 'utf8')); } catch { return {}; } }
const base = () => String(process.env.FLAGCAST_BASE || load().base || DEFAULT_BASE).replace(/\/+$/, '');
let win = null;

function createWindow() {
  win = new BrowserWindow({
    width: 1240, height: 880, minWidth: 760, minHeight: 560, title: 'Flagcast Admin', backgroundColor: '#123628',
    icon: path.join(__dirname, 'build', 'icon.png'),
    ...(process.platform === 'darwin' ? { titleBarStyle: 'hiddenInset', trafficLightPosition: { x: 18, y: 18 } } : { autoHideMenuBar: true }),
    webPreferences: { contextIsolation: true, nodeIntegration: false },
  });
  win.loadURL(`${base()}/golf/admin/`);
  win.webContents.on('did-finish-load', () => {
    // Mac: room for the traffic lights in the green bar, and the bar moves the window
    if (process.platform === 'darwin') win.webContents.insertCSS(`.topbar { padding-top: 34px !important; -webkit-app-region: drag; }
      .topbar a, .topbar button, .topbar input { -webkit-app-region: no-drag; }`).catch(() => {});
  });
  win.webContents.on('did-fail-load', (_e, code, desc, url) => {
    if (code === -3) return; // a cancelled load
    win.loadURL(`data:text/html;charset=utf-8,${encodeURIComponent(`<body style="font:16px system-ui;background:#123628;color:#eef3ec;display:grid;place-items:center;height:100vh;margin:0;text-align:center"><div><h2>Can’t reach Flagcast</h2><p>Check this Mac’s internet connection, then press ⌘R.</p><p style="opacity:.6;font-size:13px">${desc}</p></div></body>`)}`);
  });
  // desks and live pages open in their own windows; anything off Flagcast opens in the browser
  win.webContents.setWindowOpenHandler(({ url }) => {
    if (url.startsWith(base())) return { action: 'allow', overrideBrowserWindowOptions: { width: 1280, height: 860, autoHideMenuBar: true, webPreferences: { contextIsolation: true } } };
    shell.openExternal(url); return { action: 'deny' };
  });
  win.webContents.on('will-navigate', (e, url) => { if (!url.startsWith(base())) { e.preventDefault(); shell.openExternal(url); } });
  win.on('closed', () => { win = null; });
}

function menu() {
  const isMac = process.platform === 'darwin';
  Menu.setApplicationMenu(Menu.buildFromTemplate([
    ...(isMac ? [{ role: 'appMenu' }] : []),
    { label: 'File', submenu: [isMac ? { role: 'close' } : { role: 'quit' }] },
    { role: 'editMenu' },
    { label: 'View', submenu: [{ label: 'Reload', accelerator: 'CmdOrCtrl+R', click: () => win && win.loadURL(`${base()}/golf/admin/`) }, { role: 'togglefullscreen' }, { type: 'separator' }, { role: 'resetZoom' }, { role: 'zoomIn' }, { role: 'zoomOut' }, { type: 'separator' }, { role: 'toggleDevTools' }] },
    { role: 'windowMenu' },
    { role: 'help', submenu: [{ label: 'flagcast.app', click: () => shell.openExternal('https://flagcast.app') }] },
  ]));
}

app.whenReady().then(() => { menu(); createWindow(); app.on('activate', () => { if (!win) createWindow(); }); });
app.on('window-all-closed', () => { if (process.platform !== 'darwin') app.quit(); });
