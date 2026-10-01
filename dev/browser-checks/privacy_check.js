#!/usr/bin/env node
// ============================================================
// privacy_check.js - Data Dictionary privacy review, end to end
// ============================================================
//
// Drives the running app in headless Chromium with Playwright and prints
// one numbered line per check; compare against the expected values in
// dev/browser-checks/README.md.
//
// Usage:
//   Rscript dev/browser-checks/sample_app.R &      (serves sample_data/ on PORT, default 8771)
//   node dev/browser-checks/privacy_check.js
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
const port = process.env.PORT || 8771;
(async () => {
  const b = await chromium.launch(launchOpts);
  const ctx = await b.newContext({ viewport: { width: 1600, height: 1000 }, acceptDownloads: true });
  const p = await ctx.newPage();
  p.on('pageerror', e => console.log('PAGE ERROR', e.message));
  await p.goto(`http://127.0.0.1:${port}`);
  await p.waitForSelector('#erd-canvas svg .erd-node', { timeout: 120000, state: 'attached' });
  const notes = await p.$$eval('.shiny-notification', n => n.map(x => x.textContent.trim()));
  console.log('0 notifications:', JSON.stringify(notes));
  await p.click('a[data-value="Data Dictionary"]');
  await p.waitForSelector('table.dict-dt tbody tr td', { timeout: 30000 }); await p.waitForTimeout(1000);
  const heads = await p.$$eval('table.dict-dt thead th', t => [...new Set(t.map(x => x.textContent.trim()).filter(Boolean))]);
  console.log('1 columns:', JSON.stringify(heads));
  console.log('  banner:', (await p.textContent('.dict-review-banner')).trim().slice(0, 80));
  const rowOf = async (tbl, col) => {
    const rows = p.locator('table.dict-dt tbody tr');
    const n = await rows.count();
    for (let i = 0; i < n; i++) {
      const t = await rows.nth(i).locator('td').allTextContents();
      if (t[0] === tbl && t[2] === col) return t;
    }
    return null;
  };
  const r1 = await rowOf('customers', 'email');
  console.log('2 customers.email:', JSON.stringify([r1[4], r1[9], r1[10], r1[11]]));
  const r2 = await rowOf('orders', 'amount');
  console.log('  orders.amount:', JSON.stringify([r2[4], r2[9], r2[10], r2[11]]));
  // Review modal
  await p.click('#dictionary-review'); await p.waitForSelector('.dict-review-table'); await p.waitForTimeout(500);
  const qrows = await p.$$eval('.dict-review-table tbody tr', rs => rs.map(r => [...r.querySelectorAll('td')].slice(0, 5).map(td => td.textContent.trim())));
  console.log('3 queue:', JSON.stringify(qrows));
  const modalText = await p.textContent('.modal-body');
  console.log('  modal leaks values:', /@|Alice|Main St/i.test(modalText));
  // products.name -> not personal, customers.email -> private, rest later
  for (let i = 0; i < qrows.length; i++) {
    const [t, c] = qrows[i];
    const v = (t === 'products' && c === 'name') ? 'rejected' : (t === 'customers' && c === 'email') ? 'confirmed' : null;
    if (v) await p.check(`input[name="dictionary-rv_${i + 1}"][value="${v}"]`);
  }
  await p.click('#dictionary-review_save'); await p.waitForTimeout(2000);
  console.log('4 banner after save:', (await p.textContent('.dict-review-banner')).trim().slice(0, 40));
  const pn = await rowOf('products', 'name');
  console.log('  products.name:', JSON.stringify([pn[10], pn[11]]));
  const ce = await rowOf('customers', 'email');
  console.log('  customers.email:', JSON.stringify([ce[10], ce[11]]));
  // Row selection -> Private
  const rows = p.locator('table.dict-dt tbody tr');
  const n = await rows.count();
  for (let i = 0; i < n; i++) {
    const t = await rows.nth(i).locator('td').allTextContents();
    if (t[0] === 'orders' && t[2] === 'amount') { await rows.nth(i).locator('td').nth(3).click(); break; }
  }
  await p.click('#dictionary-set_private'); await p.waitForTimeout(2000);
  const am = await rowOf('orders', 'amount');
  console.log('5 amount after Private:', JSON.stringify([am[9], am[10], am[11]]));
  // Pattern
  await p.click('.dict-settings summary');
  await p.fill('#dictionary-private_patterns', 'country'); await p.click('#dictionary-apply_patterns'); await p.waitForTimeout(2000);
  const co = await rowOf('suppliers', 'country');
  console.log('6 suppliers.country with pattern:', JSON.stringify([co[10], co[11]]));
  // Filter: flags to review
  await p.evaluate(v => $('#dictionary-show')[0].selectize.setValue(v), 'review'); await p.waitForTimeout(1500);
  console.log('7 review filter:', (await p.textContent('#dictionary-dict .dataTables_info')).trim());
  await p.evaluate(v => $('#dictionary-show')[0].selectize.setValue(v), 'all'); await p.waitForTimeout(1500);
  // Edit Label + Allowed values on orders.quantity
  const edit = async (tbl, col, colIdx, value) => {
    const rows = p.locator('table.dict-dt tbody tr'); const n = await rows.count();
    for (let i = 0; i < n; i++) {
      const t = await rows.nth(i).locator('td').allTextContents();
      if (t[0] === tbl && t[2] === col) {
        const cell = rows.nth(i).locator('td').nth(colIdx);
        await cell.dblclick(); await p.waitForTimeout(300);
        const input = cell.locator('input, textarea'); await input.fill(value); await input.press('Enter'); await p.waitForTimeout(1200);
        return;
      }
    }
  };
  await edit('products', 'category', 12, 'Product category');
  await edit('orders', 'amount', 14, 'USD');
  const pc = await rowOf('products', 'category');
  console.log('8 label edit:', pc[12]);
  // Downloads
  const [yml] = await Promise.all([p.waitForEvent('download'), p.click('#dictionary-dl_yaml')]);
  const yPath = OUT + '/ui_data_dict.yaml'; await yml.saveAs(yPath);
  const y = fs.readFileSync(yPath, 'utf8');
  console.log('9 yaml:', y.includes('$version: 0.1.0'), y.includes('label: Product category'), y.includes('display: restricted'), y.includes('units: USD'), y.includes('relationships:'));
  const [csv] = await Promise.all([p.waitForEvent('download'), p.click('#dictionary-dl_csv')]);
  const csvText = fs.readFileSync(await csv.path(), 'utf8');
  console.log('  csv header:', csvText.split('\n')[0]);
  const [md] = await Promise.all([p.waitForEvent('download'), p.click('#dictionary-dl_md')]);
  const mdText = fs.readFileSync(await md.path(), 'utf8');
  console.log('  md private note:', mdText.includes('private (confirmed)'), '| no real emails:', !/@example\.(com|org)|@[a-z]+\.(com|io)/.test(mdText.replace(/person@example.com/g, '')));
  await p.screenshot({ path: OUT + '/privacy_dark.png' });
  // Session round trip keeps decisions
  await p.click('a[data-value="Export"]'); await p.waitForTimeout(800);
  const [ses] = await Promise.all([p.waitForEvent('download'), p.click('#export-dl_session')]);
  const sesPath = OUT + '/privacy_session.json'; await ses.saveAs(sesPath);
  const p2 = await ctx.newPage();
  await p2.goto(`http://127.0.0.1:${port}`);
  await p2.waitForSelector('#erd-canvas svg .erd-node', { timeout: 120000, state: 'attached' });
  await p2.click('a[data-value="Export"]'); await p2.waitForTimeout(600);
  await p2.setInputFiles('#export-restore_session_file', sesPath); await p2.waitForTimeout(4000);
  await p2.click('a[data-value="Data Dictionary"]'); await p2.waitForTimeout(2000);
  const q2 = await p2.$('.dict-review-banner') ? (await p2.textContent('.dict-review-banner')).trim().slice(0, 40) : '(no banner)';
  console.log('10 restored banner:', q2, '| patterns:', await p2.inputValue('#dictionary-private_patterns'));
  await b.close();
})().catch(e => { console.error('FAILED', e); process.exit(1); });
