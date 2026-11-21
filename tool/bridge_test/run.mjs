// Runs the EPUB reader's JavaScript (assets/epub_viewer, unmodified) in
// headless desktop Chrome with Dart's side replaced by stub.js, feeds it
// book.epub through the calls custom_epub_viewer.dart makes, and checks the
// handler calls Dart receives. Prints each check and exits 1 if one fails.
//
//   node tool/bridge_test/run.mjs [viewer-dir]
//
// viewer-dir defaults to assets/epub_viewer. Point it at a copy with an
// older reader_bridge.js to replay a past bug; the Dart side (handler
// names, the bridge functions it calls) is always read from this checkout.
// The checks run in order on one page, each starting where the last ended.
// Chrome only: WKWebView (iOS) is not covered.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromium, errors } from 'playwright-core';

const started = Date.now();
const here = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(here, '../..');
const viewer = path.resolve(process.argv[2] ?? path.join(repo, 'assets/epub_viewer'));
const dart = (file) =>
  fs.readFileSync(path.join(repo, 'lib/features/reader/presentation/widgets', file), 'utf8');
const matches = (text, re) => new Set([...text.matchAll(re)].map((m) => m[1] ?? m[2]));
const registered = matches(dart('custom_epub_viewer.dart'), /handlerName: '(\w+)'/g);
// Each JS call Dart makes is a string literal that starts with the function
// ('next()', 'loadBook(', ...), or a chunk function passed as append:.
const dartCalls = matches(
  ['custom_epub_viewer.dart', 'custom_epub_controller.dart', 'bridge_transfer.dart'].map(dart).join(),
  /'([a-z]\w*)\(|append: '(\w+)'/g,
);

const browser = await chromium.launch({ channel: 'chrome' });
const page = await browser.newPage({ viewport: { width: 412, height: 800 } });
const pageErrors = [];
page.on('pageerror', (e) => pageErrors.push(e.message));
await page.route('http://viewer.localhost/**', (route) => {
  const file = path.join(viewer, new URL(route.request().url()).pathname);
  return fs.existsSync(file) ? route.fulfill({ path: file }) : route.fulfill({ status: 404 });
});
await page.addInitScript({ path: path.join(here, 'stub.js') });

// Before the first page load there is no stub yet, and so no calls.
const mark = () => page.evaluate(() => window.__calls?.length ?? 0);
const calls = (from) => page.evaluate((f) => (window.__calls ?? []).slice(f), from);
const seq = (list) => list.map((c) => c.name).join(' ');
const argOf = (list, name) => list.find((c) => c.name === name)?.args[0];
function expect(ok, problem) {
  if (!ok) throw new Error(problem);
}

// Waits for a call since index `from` for which `test` (page-side source
// over `c`, a recorded call) holds.
async function until(from, test, timeout = 5000, problem = `no call where ${test}`) {
  try {
    await page.waitForFunction(`window.__calls.slice(${from}).some((c) => ${test})`, null, { timeout });
  } catch (e) {
    if (e instanceof errors.TimeoutError) throw new Error(`${problem} (waited ${timeout} ms)`);
    throw e;
  }
}

// Nothing tells that a re-layout is over, so the checks that a re-layout
// sends no pageChars wait for 500 ms without any call after its relocated.
async function quiet(ms = 500) {
  let n = await mark();
  let since = Date.now();
  const cap = since + 10000;
  while (Date.now() - since < ms && Date.now() < cap) {
    await new Promise((resolve) => setTimeout(resolve, 50));
    const m = await mark();
    if (m !== n) [n, since] = [m, Date.now()];
  }
}

function expectLocation(loc, label) {
  expect(
    /^epubcfi\(/.test(loc?.startCfi) && /^epubcfi\(/.test(loc?.endCfi),
    `${label}: relocated has no CFIs: ${JSON.stringify(loc)}`,
  );
  expect(
    typeof loc.progress === 'number' && loc.progress >= 0 && loc.progress <= 1,
    `${label}: relocated progress is ${loc.progress}`,
  );
}

let firstPage; // the relocation the book opened on

const checks = [
  ['a book loads', async (from) => {
    await page.goto('http://viewer.localhost/reader.html');
    await until(from, `c.name === 'readyToLoad'`);
    const bytes = fs.readFileSync(path.join(here, 'book.epub'));
    if (await page.evaluate(() => typeof beginEpubTransfer === 'function')) {
      await page.evaluate(`beginEpubTransfer(${bytes.length})`);
      // Dart sends 3 MiB chunks; 999 bytes (also a multiple of 3, so each
      // chunk decodes alone) makes this book arrive in three.
      for (let i = 0; i < bytes.length; i += 999) {
        await page.evaluate(`appendEpubChunk('${bytes.subarray(i, i + 999).toString('base64')}')`);
      }
      await page.evaluate('loadBook("", "rtl", "paginated", false, "18", "#000000", null, 28, 28, false, "book", 1, null)');
    } else {
      // Bridges before the chunked transfer took the bytes as loadBook's
      // first argument, and 'off' was the mode that generates no furigana.
      await page.evaluate(`loadBook([${[...bytes]}], "", "rtl", "paginated", false, "18", "#000000", null, 28, 28, false, "off", 1)`);
    }
    await page.evaluate('setBodyBackground("#ffffff")');
    await until(from, `c.name === 'locationsReady'`, 15000);
    await until(from, `c.name === 'pageChars'`, 15000);
    const got = await calls(from);
    firstPage = argOf(got, 'relocated');
    const names = got.map((c) => c.name);
    expect(names[0] === 'readyToLoad', 'readyToLoad is not the first call');
    for (const name of ['chapters', 'loaded', 'relocated', 'pageChars', 'locationsReady']) {
      const n = names.filter((x) => x === name).length;
      expect(n === 1, `${name} sent ${n} times, expected once`);
    }
    expect(names.indexOf('loaded') < names.indexOf('relocated'), 'relocated came before loaded');
    expect(names[names.indexOf('relocated') + 1] === 'pageChars', 'pageChars does not follow relocated');
    expectLocation(firstPage, 'load');
    const chars = argOf(got, 'pageChars');
    expect(chars.count > 0 && chars.pageKey === firstPage.startCfi, `pageChars ${JSON.stringify(chars)}`);
    const titles = argOf(got, 'chapters')?.map((c) => c.title).join();
    expect(titles === '第一章,第二章', `chapters are ${titles}`);
    // Dart saves this string as the book's locations.json.
    const saved = JSON.parse(argOf(got, 'locationsReady') ?? 'null');
    expect(
      Array.isArray(saved) && saved.length > 0 && saved.every((cfi) => cfi.startsWith('epubcfi(')),
      'locationsReady carries no locations to save',
    );
  }],

  ['next() and previous() send relocated, then pageChars', async () => {
    const turn = async (js) => {
      const at = await mark();
      await page.evaluate(js);
      await until(at, `c.name === 'pageChars'`);
      const got = await calls(at);
      expect(seq(got) === 'relocated pageChars', `${js} sent ${seq(got)}`);
      const [loc, chars] = got.map((c) => c.args[0]);
      expectLocation(loc, js);
      expect(chars.count > 0 && chars.pageKey === loc.startCfi, `${js}: pageChars ${JSON.stringify(chars)}`);
      return loc;
    };
    const forward = await turn('next()');
    const back = await turn('previous()');
    expect(forward.startCfi !== firstPage.startCfi, 'next() stayed on the first page');
    expect(forward.progress > firstPage.progress, `next() progress ${forward.progress} is not past ${firstPage.progress}`);
    expect(back.startCfi === firstPage.startCfi, `previous() went to ${back.startCfi}, not back to the first page`);
  }],

  ...[['setFontSize', 'setFontSize("24")'], ['setMargins', 'setMargins(40, 40)']].map(([label, js]) => [
    `${label} re-lays out the page and sends no pageChars`,
    async (from) => {
      await page.evaluate(js);
      await until(from, `c.name === 'relocated'`);
      await quiet();
      const got = await calls(from);
      expect(!got.some((c) => c.name === 'pageChars'), `${label} sent pageChars: a re-layout counted as reading`);
      const loc = got.filter((c) => c.name === 'relocated').at(-1).args[0];
      expect(loc.startCfi === firstPage.startCfi, `${label} moved the reader to ${loc.startCfi}`);
    },
  ]),

  ['searchBook sends a progress call per chapter, then done', async (from) => {
    await page.evaluate('searchBook(1, "猫")');
    await until(from, `c.name === 'searchProgress' && c.args[0].done`);
    const got = (await calls(from)).filter((c) => c.name === 'searchProgress').map((c) => c.args[0]);
    const done = got.pop();
    expect(got.concat(done).every((p) => p.id === 1), 'a searchProgress call for another search');
    const steps = got.map((p) => `${p.searched}/${p.total}`).join();
    expect(steps === '1/2,2/2', `progress went ${steps}, expected 1/2,2/2`);
    const hits = got.flatMap((p) => p.hits);
    // make_epub.py: 猫 appears four times per paragraph, 6 + 2 paragraphs.
    expect(hits.length === 32, `${hits.length} hits, expected 32`);
    expect(
      hits.every((h) => /^epubcfi\(/.test(h.cfi) && h.match === '猫' && typeof h.before === 'string' && typeof h.after === 'string'),
      'a hit without its cfi, before, match and after',
    );
    expect(got.every((p) => JSON.parse(p.toc).spine === p.searched - 1), 'a toc placement names another chapter');
    expect(done.done === true && done.capped === false, `the last call is ${JSON.stringify(done)}`);
  }],

  ['setFuriganaMode asks generateFurigana, then sends furiganaApplied', async (from) => {
    await page.evaluate('setFuriganaMode("all")');
    await until(from, `c.name === 'furiganaApplied'`);
    const got = await calls(from);
    const names = got.map((c) => c.name);
    expect(names.indexOf('generateFurigana') !== -1, 'generateFurigana was not asked');
    expect(names.indexOf('generateFurigana') < names.indexOf('furiganaApplied'), 'furiganaApplied came first');
    const texts = argOf(got, 'generateFurigana');
    expect(texts.length > 0 && texts.every((t) => /[一-龯]/.test(t)), `asked for ${JSON.stringify(texts)}`);
    expect(!texts.includes('漢字'), "the book's own ruby was sent for furigana");
  }],

  ['a null generateFurigana reply (MeCab not up) is asked again after a mode toggle', async (from) => {
    await page.evaluate(() => { window.__mecabReady = false; });
    // Turn pages into chapter 2, which has text without furigana yet. A CFI
    // into the second spine item starts epubcfi(/6/4!.
    for (let turns = 0; ; turns++) {
      expect(turns < 30, 'next() did not reach chapter 2 in 30 turns');
      const at = await mark();
      await page.evaluate('next()');
      await until(at, `c.name === 'pageChars'`);
      if (argOf(await calls(at), 'relocated').startCfi.startsWith('epubcfi(/6/4!')) break;
    }
    // The stub answers at once and the bridge takes the reply in microtasks,
    // so it has been handled by the time the call is seen.
    const first = argOf(await calls(from), 'generateFurigana');
    expect(first, 'chapter 2 asked no generateFurigana');
    await page.evaluate(() => { window.__mecabReady = true; });
    const at = await mark();
    await page.evaluate('setFuriganaMode("hide"); setFuriganaMode("all")');
    await until(at, `c.name === 'generateFurigana'`, 3000,
      'generateFurigana was not asked again, so chapter 2 stays without furigana');
    const again = argOf(await calls(at), 'generateFurigana');
    expect(JSON.stringify(again) === JSON.stringify(first), 'asked again, but for other text');
  }],

  ['every handler the page calls is registered in Dart', async () => {
    // The calls seen so far, and every name written in reader_bridge.js.
    const source = fs.readFileSync(path.join(viewer, 'reader_bridge.js'), 'utf8');
    const called = new Set([
      ...(await calls(0)).map((c) => c.name),
      ...matches(source, /(?:callDart|callDartAsync|callHandler)\(\s*'(\w+)'/g),
    ]);
    const missing = [...called].filter((name) => !registered.has(name));
    expect(missing.length === 0, `not registered in custom_epub_viewer.dart: ${missing.join(', ')}`);
  }],

  ['every bridge function Dart calls is defined', async () => {
    expect(dartCalls.size > 0, 'found no bridge calls in the Dart files');
    const missing = await page.evaluate((fns) => fns.filter((f) => typeof window[f] !== 'function'), [...dartCalls]);
    expect(missing.length === 0, `called from Dart but not defined: ${missing.join(', ')}`);
  }],

  ['the page throws no uncaught errors', async () => {
    expect(pageErrors.length === 0, pageErrors.join(' | '));
  }],
];

let passed = 0;
try {
  for (const [name, body] of checks) {
    const from = await mark();
    let problem = null;
    try {
      await body(from);
      passed++;
    } catch (e) {
      problem = e.message.split('\n')[0];
    }
    const sent = seq(await calls(from));
    console.log(`${problem ? 'FAIL' : 'PASS'}  ${name}${sent ? `\n      calls: ${sent}` : ''}`);
    if (problem) console.log(`      ${problem}`);
    if (!firstPage) break; // the rest needs a book on screen
  }
} finally {
  await browser.close();
}
console.log(`${passed} of ${checks.length} checks passed in ${(Date.now() - started) / 1000} s`);
process.exitCode = passed === checks.length ? 0 : 1;
