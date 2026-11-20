// Updates: checks flagcast.app/updates/<app>/ quietly at launch and from Help → Check for Updates….
// Nothing downloads until the user picks Install and Restart. The feed is the publish URL in package.json;
// FLAGCAST_UPDATE_FEED points it somewhere else for testing.
const { app, dialog, BrowserWindow } = require('electron')

let au = null
let busy = false
let manual = false

function win() { return BrowserWindow.getFocusedWindow() || BrowserWindow.getAllWindows()[0] }
function box(opts) { const w = win(); return w ? dialog.showMessageBox(w, opts) : dialog.showMessageBox(opts) }

function setup() {
  if (au) return au
  au = require('electron-updater').autoUpdater
  au.autoDownload = false
  au.autoInstallOnAppQuit = false
  au.logger = process.env.FLAGCAST_UPDATE_FEED ? console : null   // quiet, except when testing a feed
  if (process.env.FLAGCAST_UPDATE_FEED) au.setFeedURL({ provider: 'generic', url: process.env.FLAGCAST_UPDATE_FEED })

  au.on('update-available', async (info) => {
    const r = await box({
      type: 'info',
      message: `${app.getName()} ${info.version} is available`,
      detail: `You have ${app.getVersion()}. It downloads now and ${app.getName()} restarts when it's ready.`,
      buttons: ['Install and Restart', 'Later'],
      defaultId: 0,
      cancelId: 1,
    })
    if (r.response !== 0) { busy = false; return }
    au.downloadUpdate().catch((e) => fail(e, true))
  })
  au.on('update-not-available', () => {
    busy = false
    if (manual) box({ type: 'info', message: `${app.getName()} is up to date`, detail: `Version ${app.getVersion()}.`, buttons: ['OK'] })
  })
  au.on('download-progress', (p) => { const w = win(); if (w) w.setProgressBar(p.percent / 100) })
  au.on('update-downloaded', () => {
    const w = win(); if (w) w.setProgressBar(-1)
    setImmediate(() => au.quitAndInstall(false, true))
  })
  au.on('error', (e) => fail(e, manual))
  return au
}

function fail(e, show) {
  busy = false
  const w = win(); if (w) w.setProgressBar(-1)
  if (show) box({ type: 'warning', message: 'Couldn’t check for updates', detail: String((e && e.message) || e).split('\n')[0], buttons: ['OK'] })
}

function check(quiet) {
  if (!app.isPackaged && !process.env.FLAGCAST_UPDATE_FEED) {
    if (!quiet) box({ type: 'info', message: 'Updates work in the installed app', buttons: ['OK'] })
    return
  }
  if (busy) return
  busy = true
  manual = !quiet
  setup().checkForUpdates().catch((e) => fail(e, !quiet))
}

module.exports = { check }
