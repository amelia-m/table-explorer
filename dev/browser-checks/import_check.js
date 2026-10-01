#!/usr/bin/env node
// ============================================================
// import_check.js - data-dict YAML import and re-export
// ============================================================
//
// Drives the running app in headless Chromium with Playwright and prints
// one numbered line per check; compare against the expected values in
// dev/browser-checks/README.md.
//
// Usage:
//   Rscript dev/browser-checks/plain_app.R &       (empty app on PORT, default 8772)
//   node dev/browser-checks/import_check.js
// Env: PORT, OUT (output dir), PLAYWRIGHT_MODULE (path to playwright if not
// on NODE_PATH), CHROMIUM (browser executable if Playwright's own is absent).

const fs = require('fs');
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const os = require('os');
const path = require('path');
// Where downloads and screenshots go
const OUT = process.env.OUT || path.join(os.tmpdir(), 'te-browser-checks');
fs.mkdirSync(OUT, { recursive: true });
const launchOpts = process.env.CHROMIUM ? { executablePath: process.env.CHROMIUM } : {};
const port = process.env.PORT || 8772;
(async () => {
  const b = await chromium.launch(launchOpts);
  const p = await (await b.newContext({ viewport: { width: 1600, height: 1000 }, acceptDownloads: true })).newPage();
  p.on('pageerror', e => console.log('PAGE ERROR', e.message));
  await p.goto(`http://127.0.0.1:${port}`); await p.waitForTimeout(4000);
  const inputs = await p.$$eval('input[type=file]', x => x.map(i => i.id));
  console.log('file inputs:', JSON.stringify(inputs));
  await p.setInputFiles('#upload-schema_file', OUT + '/ui_data_dict.yaml'); await p.waitForTimeout(5000);
  console.log('notifications:', JSON.stringify(await p.$$eval('.shiny-notification', n => n.map(x => x.textContent.trim()))));
  await p.click('a[data-value="Relationships"]'); await p.waitForTimeout(2000);
  await p.click('a[data-value="Data Dictionary"]'); await p.waitForSelector('table.dict-dt tbody tr td', { timeout: 30000 }); await p.waitForTimeout(1000);
  const rows = await p.$$eval('table.dict-dt tbody tr', rs => rs.map(r => [...r.querySelectorAll('td')].map(td => td.textContent.trim())));
  console.log('rows:', rows.length);
  for (const r of rows) if (r[12] || r[14] || r[10]) console.log('  ', JSON.stringify([r[0], r[2], r[10], r[12], r[14]]));
  const [y2] = await Promise.all([p.waitForEvent('download'), p.click('#dictionary-dl_yaml')]);
  await y2.saveAs(OUT + '/ui_data_dict_2.yaml');
  console.log('re-exported');
  await b.close();
})().catch(e => { console.error('FAILED', e); process.exit(1); });
