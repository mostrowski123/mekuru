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

// A phone's pixel ratio. Only the launch flag makes scroll offsets land on
// device pixels, as Android's WebView does; deviceScaleFactor alone does not.
const browser = await chromium.launch({ channel: 'chrome', args: ['--force-device-scale-factor=2.625'] });
let page = await browser.newPage({ viewport: { width: 412, height: 800 }, deviceScaleFactor: 2.625 });
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

// A page of its own with `file` from this folder opened by loadBook(args).
// Resolves once it has shown a page; p.thrown collects its script errors.
async function openBook(file, args, [width, height] = [412, 800]) {
  const p = await browser.newPage({ viewport: { width, height }, deviceScaleFactor: 2.625 });
  p.thrown = [];
  p.on('pageerror', (e) => p.thrown.push(e.message));
  await p.route('http://viewer.localhost/**', (route) => {
    const file = path.join(viewer, new URL(route.request().url()).pathname);
    return fs.existsSync(file) ? route.fulfill({ path: file }) : route.fulfill({ status: 404 });
  });
  await p.addInitScript({ path: path.join(here, 'stub.js') });
  await p.goto('http://viewer.localhost/reader.html');
  await p.waitForFunction(`window.__calls.some((c) => c.name === 'readyToLoad')`);
  const bytes = fs.readFileSync(path.join(here, file));
  await p.evaluate(`beginEpubTransfer(${bytes.length}); appendEpubChunk('${bytes.toString('base64')}')`);
  await p.evaluate(`loadBook(${args})`);
  await p.waitForFunction(`window.__calls.some((c) => c.name === 'pageChars')`, null, { timeout: 8000 });
  return p;
}

// Runs `js` (a page turn or a jump) on page p, waits for its pageChars and
// then for 300 ms without a call, and returns the calls it sent.
async function turned(p, js) {
  const start = await p.evaluate(() => window.__calls.length);
  await p.evaluate(js);
  await p.waitForFunction(`window.__calls.slice(${start}).some((c) => c.name === 'pageChars')`, null, { timeout: 5000 })
    .catch(() => { throw new Error(`${js} showed no page`); });
  for (let n = -1, m = 0; n !== m; ) {
    [n, m] = [m, await p.evaluate(() => window.__calls.length)];
    if (n !== m) await new Promise((resolve) => setTimeout(resolve, 300));
  }
  return p.evaluate((f) => window.__calls.slice(f), start);
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

  ["previous() from a chapter's first page lands on the last page before it", async () => {
    // The last check left the reader on chapter 2's first page. Chapter 1 is
    // laid out again when it comes back (font size 24, furigana), and the
    // page back must land on its last page as laid out then.
    const before = (await calls(0)).filter((c) => c.name === 'relocated').at(-1).args[0];
    expect(
      before.startCfi.startsWith('epubcfi(/6/4!') && before.hrefProgression === 0,
      `not on chapter 2's first page: ${JSON.stringify(before)}`,
    );
    await quiet();
    let at = await mark();
    await page.evaluate('previous()');
    await until(at, `c.name === 'pageChars'`);
    await quiet();
    const back = await calls(at);
    const landed = back.filter((c) => c.name === 'relocated').map((c) => c.args[0]);
    const chars = argOf(back, 'pageChars');
    expect(landed.length > 0 && landed.every((l) => l.startCfi.startsWith('epubcfi(/6/2!')),
      `previous() went to ${landed.map((l) => l.startCfi).join()}, not into chapter 1`);
    expect(landed.every((l) => l.startCfi === chars.pageKey),
      `pageChars counted ${chars.pageKey}, but the reader was reported on ${landed.map((l) => l.startCfi).join()}`);
    at = await mark();
    await page.evaluate('next()');
    await until(at, `c.name === 'pageChars'`);
    const fwd = argOf(await calls(at), 'relocated');
    expect(fwd.startCfi.startsWith('epubcfi(/6/4!'),
      `previous() landed before chapter 1's last page: one next() from ${chars.pageKey} went to ${fwd.startCfi}, still in chapter 1`);
  }],

  ['a book whose links do not percent-decode opens and pages through', async () => {
    // bad_href.epub (make_epub.py), on a page of its own. Chapter two's link
    // escapes a byte that is not UTF-8 (c%FF.xhtml, and its picture
    // i%FF.png), chapter three's has a '%' that starts no escape
    // (100%.xhtml). Each names its zip entry as it is written.
    const main = page;
    const errors = [];
    page = await browser.newPage({ viewport: { width: 412, height: 800 } });
    try {
      page.on('pageerror', (e) => errors.push(e.message));
      page.on('console', (m) => m.type() === 'error' && errors.push(m.text()));
      await page.route('http://viewer.localhost/**', (route) => {
        const file = path.join(viewer, new URL(route.request().url()).pathname);
        return fs.existsSync(file) ? route.fulfill({ path: file }) : route.fulfill({ status: 404 });
      });
      await page.addInitScript({ path: path.join(here, 'stub.js') });
      await page.goto('http://viewer.localhost/reader.html');
      await until(0, `c.name === 'readyToLoad'`);
      const bytes = fs.readFileSync(path.join(here, 'bad_href.epub'));
      await page.evaluate(`beginEpubTransfer(${bytes.length})`);
      await page.evaluate(`appendEpubChunk('${bytes.toString('base64')}')`);
      await page.evaluate('loadBook("", "rtl", "paginated", false, "18", "#000000", null, 28, 28, false, "book", 1, null)');
      await until(0, `c.name === 'pageChars'`, 15000).catch((e) => {
        throw new Error(`the book showed no page: ${errors.join(' | ') || e.message}`);
      });
      const chapters = argOf(await calls(0), 'chapters');
      const hrefs = chapters.map((c) => c.href).join();
      expect(hrefs === 'c1.xhtml,c%FF.xhtml#top,100%.xhtml', `the chapters link ${hrefs}`);

      // Dart's chapter list shows a chapter with toCfi(its href).
      let at = await mark();
      await page.evaluate(`toCfi(${JSON.stringify(chapters[1].href)})`);
      await until(at, `c.name === 'pageChars'`, 5000, 'the link to chapter two showed no page');
      const href = argOf(await calls(at), 'relocated').href;
      expect(href === 'c%FF.xhtml', `the link to chapter two went to ${href}`);
      const shown = await page.evaluate(() => {
        const doc = rendition.getContents()[0].document;
        const img = doc.querySelector('img');
        return { title: doc.querySelector('h1').textContent, picture: img.complete && img.naturalWidth > 0 };
      });
      expect(shown.title === '第二章' && shown.picture, `chapter two shows ${JSON.stringify(shown)}`);

      for (let turns = 0; ; turns++) {
        expect(turns < 10, 'next() did not reach chapter three in 10 turns');
        at = await mark();
        await page.evaluate('next()');
        await until(at, `c.name === 'pageChars'`);
        if (argOf(await calls(at), 'relocated').href === '100%.xhtml') break;
      }
      expect(errors.length === 0, errors.join(' | '));
    } finally {
      await page.close();
      page = main;
    }
  }],

  ['a book reopened at its page in another mode shows that page, also when the window grows while it opens', async () => {
    // Each reading-mode change rebuilds the viewer at the page the last one
    // reported. Android lays a new WebView out at 0 x 0 and gives it its size
    // a moment later, and that resize cleared the page being opened: it
    // never showed (a blank page, or a script error and no `loaded`). Here
    // the page is hidden (0 x 0) until a chosen moment of the opening: before
    // the chapter is in its frame (serialize), while it is themed (content),
    // or as it is reported shown (loaded).
    const bytes = fs.readFileSync(path.join(here, 'book.epub'));
    const horizontal = JSON.stringify({ html: { 'writing-mode': 'horizontal-tb !important' } });
    // loadBook's arguments after the CFI, as Dart sends them for each mode.
    const modes = {
      pages: `"rtl", "paginated", false, "18", "#000000", null, 28, 28, false, "book", 1, null`,
      scroll: `"rtl", "scrolled", false, "18", "#000000", null, 0, 28, false, "book", 1, null`,
      horizontal: `"ltr", "paginated", false, "18", "#000000", ${horizontal}, 28, 28, true, "book", 1, null`,
    };
    function grow(moment) {
      if (!moment) return;
      document.body.style.display = 'none';
      let grown = false;
      const show = () => {
        if (grown) return;
        grown = true;
        document.body.style.display = '';
        window.dispatchEvent(new Event('resize'));
      };
      if (moment === 'loaded') {
        const call = window.flutter_inappwebview.callHandler;
        window.flutter_inappwebview.callHandler = function (name) {
          if (name === 'loaded') show();
          return call.apply(this, arguments);
        };
      } else {
        (moment === 'serialize' ? book.spine : rendition).hooks[moment].register(show);
      }
    }
    const count = (p) => p.evaluate(() => window.__calls.length);
    const open = async (mode, cfi, moment) => {
      const p = await browser.newPage({ viewport: { width: 412, height: 800 }, deviceScaleFactor: 2.625 });
      const thrown = [];
      p.on('pageerror', (e) => thrown.push(e.message));
      await p.route('http://viewer.localhost/**', (route) => {
        const file = path.join(viewer, new URL(route.request().url()).pathname);
        return fs.existsSync(file) ? route.fulfill({ path: file }) : route.fulfill({ status: 404 });
      });
      await p.addInitScript({ path: path.join(here, 'stub.js') });
      await p.goto('http://viewer.localhost/reader.html');
      await p.waitForFunction(`window.__calls.some((c) => c.name === 'readyToLoad')`);
      await p.evaluate(`beginEpubTransfer(${bytes.length}); appendEpubChunk('${bytes.toString('base64')}')`);
      // One script, so the hooks are in before the book has opened.
      await p.evaluate(`loadBook(${JSON.stringify(cfi)}, ${modes[mode]}); (${grow})(${JSON.stringify(moment ?? null)})`);
      try {
        await p.waitForFunction(`window.__calls.some((c) => c.name === 'relocated')`, null, { timeout: 8000 }).catch(() => {});
        // Until no call for 500 ms: a resize can show the page a second time.
        for (let n = -1, m = await count(p); n !== m; n = m, m = await count(p)) {
          await new Promise((resolve) => setTimeout(resolve, 500));
        }
        const label = `${mode} view at ${cfi}${moment ? `, grown at ${moment}` : ''}`;
        expect(thrown.length === 0, `${label}: the page threw ${thrown.join(' | ')}`);
        const shown = await p.evaluate((asked) => {
          const loc = rendition.location;
          const cfi = new ePub.CFI();
          return {
            loaded: window.__calls.some((c) => c.name === 'loaded'),
            views: rendition.manager.views.all().filter((v) => v.contents && v.element.style.visibility === 'visible').length,
            start: loc?.start?.cfi,
            holds: !!(loc?.start && loc.end && cfi.compare(loc.start.cfi, asked) <= 0 && cfi.compare(asked, loc.end.cfi) <= 0),
          };
        }, cfi);
        expect(shown.loaded && shown.views === 1, `${label}: no page on screen: ${JSON.stringify(shown)}`);
        expect(shown.holds, `${label}: shows ${shown.start}, not the page with ${cfi}`);
        return shown.start;
      } finally {
        await p.close();
      }
    };
    // Two pages back from where the last check left the reader (chapter 2's
    // first page), then page view to scroll view and back, and vertical text
    // off and on again, each viewer opened where the last one was.
    let start;
    for (let turn = 0; turn < 2; turn++) {
      const at = await mark();
      await page.evaluate('previous()');
      await until(at, `c.name === 'pageChars'`);
      start = argOf(await calls(at), 'relocated').startCfi;
    }
    for (const moment of [null, 'serialize', 'content', 'loaded']) {
      let at = start;
      for (const mode of ['scroll', 'pages', 'horizontal', 'pages']) at = await open(mode, at, moment);
    }
  }],

  ['a re-layout keeps the reader on the character they were at, not the start of its page', async () => {
    // A book reopened mid-page (another mode, a turned phone), then turned
    // and given other font sizes. The page holding the place usually starts
    // earlier after a re-layout; reporting that start as the place moved
    // the reader back a little with each one, to the chapter's start.
    const bytes = fs.readFileSync(path.join(here, 'book.epub'));
    const place = 'epubcfi(/6/2!/4/10/1:150)'; // mid-paragraph, mid-page
    const modes = {
      pages: `"rtl", "paginated", false, "24", "#000000", null, 28, 28, false, "book", 1, null`,
      scroll: `"rtl", "scrolled", false, "24", "#000000", null, 0, 28, false, "book", 1, null`,
    };
    for (const mode of Object.keys(modes)) {
      const p = await browser.newPage({ viewport: { width: 412, height: 800 }, deviceScaleFactor: 2.625 });
      try {
        await p.route('http://viewer.localhost/**', (route) => {
          const file = path.join(viewer, new URL(route.request().url()).pathname);
          return fs.existsSync(file) ? route.fulfill({ path: file }) : route.fulfill({ status: 404 });
        });
        await p.addInitScript({ path: path.join(here, 'stub.js') });
        await p.goto('http://viewer.localhost/reader.html');
        await p.waitForFunction(`window.__calls.some((c) => c.name === 'readyToLoad')`);
        await p.evaluate(`beginEpubTransfer(${bytes.length}); appendEpubChunk('${bytes.toString('base64')}')`);
        await p.evaluate(`loadBook(${JSON.stringify(place)}, ${modes[mode]})`);
        await p.waitForFunction(`window.__calls.some((c) => c.name === 'pageChars')`, null, { timeout: 8000 });
        const steps = [null, [800, 412], [412, 800], [800, 412], [412, 800], '30', '24'];
        for (const step of steps) {
          if (Array.isArray(step)) await p.setViewportSize({ width: step[0], height: step[1] });
          else if (step) await p.evaluate(`setFontSize("${step}")`);
          // Until no call for 500 ms: a re-layout reports once it is shown.
          for (let n = -1, m = 0; n !== m; ) {
            [n, m] = [m, await p.evaluate(() => window.__calls.length)];
            if (n !== m) await new Promise((resolve) => setTimeout(resolve, 500));
          }
          const label = `${mode}, ${step ? `then ${step}` : 'opened'}`;
          const got = await p.evaluate((asked) => {
            const reported = window.__calls.filter((c) => c.name === 'relocated').at(-1).args[0];
            const shown = rendition.location; // the page on screen
            const cfi = new ePub.CFI();
            return {
              reported: reported.startCfi,
              pageStart: shown.start.cfi,
              holds: cfi.compare(shown.start.cfi, asked) <= 0 && cfi.compare(asked, shown.end.cfi) <= 0,
            };
          }, place);
          if (!step) expect(got.pageStart !== place, `${label}: ${place} starts its page, so this checks nothing`);
          expect(got.reported === place, `${label}: reported ${got.reported}, not the place ${place}`);
          expect(got.holds, `${label}: shows the page from ${got.pageStart}, which does not hold ${place}`);
        }
      } finally {
        await p.close();
      }
    }
  }],

  ["a book paged right to left keeps its text's own direction, and its pages run right to left", async () => {
    // horizontal_rtl.epub and arabic_rtl.epub (make_epub.py): spines that
    // run right to left, horizontal text. epub.js turns such pages right to
    // left by making the content right-to-left, and that turned Japanese
    // text around too: right-aligned, each full stop at the line's left end.
    // With vertical text on (Dart's default for them) nothing forces the
    // text horizontal or left to right.
    const pages = `"rtl", "paginated", false, "18", "#000000", null, 28, 28, false, "book", 1, null`;
    for (const [file, ltr, args, size] of [
      ['horizontal_rtl.epub', true, pages, [412, 800]],
      ['horizontal_rtl.epub', true, `${pages}, 600`, [900, 600]], // two pages side by side
      ['arabic_rtl.epub', false, pages, [412, 800]],
    ]) {
      const label = `${file} at ${size.join(' x ')}`;
      const p = await openBook(file, `"", ${args}`, size);
      try {
        // Rightwards steps from the first paragraph's first character to
        // its second, and from its second to last to its last (a full stop).
        const steps = await p.evaluate(() => {
          const doc = rendition.getContents()[0].document;
          const text = doc.querySelector('p').firstChild;
          const x = (i) => {
            const r = doc.createRange();
            r.setStart(text, i);
            r.setEnd(text, i + 1);
            return r.getBoundingClientRect().left;
          };
          return [x(1) - x(0), x(text.length - 1) - x(text.length - 2)];
        });
        expect(steps.every((s) => (ltr ? s > 0 : s < 0)),
          `${label}: the text does not run ${ltr ? 'left to right' : 'right to left'} (rightward steps ${steps.join(', ')})`);

        // Through chapter 1 with next(), a page (or a pair) a turn, each
        // further left, then back from chapter 2 onto its last page.
        const where = () => p.evaluate(() => {
          const { start, end } = rendition.currentLocation();
          return [start.index, start.displayed.page, end.displayed.page, start.displayed.total,
            rendition.manager.container.scrollLeft];
        });
        let [index, page, last, total, left] = await where();
        const shown = [];
        while (index === 0 && shown.length <= total) {
          shown.push(`${page}-${last}`);
          await turned(p, 'next()');
          const before = left;
          [index, page, last, , left] = await where();
          expect(index !== 0 || left < before, `${label}: next() from page ${shown.at(-1)} moved right`);
        }
        expect(shown.at(-1).endsWith(`-${total}`) && shown[0].startsWith('1-'),
          `${label}: chapter 1 showed pages ${shown.join()} of ${total}`);
        await turned(p, 'previous()');
        [index, , last] = await where();
        expect(index === 0 && last === total, `${label}: previous() from chapter 2 went to page ${last} of chapter ${index + 1}`);
        if (p.thrown.length) throw new Error(`${label}: the page threw ${p.thrown.join(' | ')}`);
      } finally {
        await p.close();
      }
    }
  }],

  ["a link with a ?query goes to the start of its chapter", async () => {
    // epub.js looked c2.xhtml?v=1 up with its query, found no chapter, and
    // the link went nowhere; found, it was placed as a target in the chapter
    // and right to left went to the chapter's end. toCfi(href) is what Dart's
    // chapter list runs; a link in the text displays its href the same way.
    const p = await openBook('horizontal_rtl.epub', `"", "rtl", "paginated", false, "18", "#000000", null, 28, 28, false, "book", 1, null`);
    try {
      for (const [href, index] of [['c2.xhtml?v=1', 1], ['c1.xhtml?v=1', 0]]) {
        await turned(p, `toCfi(${JSON.stringify(href)})`);
        const [at, page] = await p.evaluate(() => {
          const { start } = rendition.currentLocation();
          return [start.index, start.displayed.page];
        });
        expect(at === index && page === 1, `toCfi('${href}') went to chapter ${at + 1}, page ${page}`);
      }
    } finally {
      await p.close();
    }
  }],

  ['after a chapter fails to show, turning the phone shows the page the reader was on', async () => {
    // A chapter that cannot be laid out (here its render fails, as for an
    // unreadable file) leaves the screen blank. epub.js kept that display
    // pending, holding up what was queued after it, and as the one in
    // progress, so a resize showed the failed chapter again.
    const p = await openBook('book.epub', `"", "rtl", "paginated", false, "18", "#000000", null, 28, 28, false, "book", 1, null`);
    try {
      const place = await p.evaluate(() => {
        book.spine.get(1).render = () => Promise.reject(new Error('unreadable'));
        toCfi('c2.xhtml');
        return rendition.location.start.cfi;
      });
      await p.waitForFunction(() => rendition.manager.views.all().every((v) => !v.contents));
      await p.setViewportSize({ width: 800, height: 412 });
      await p.waitForFunction(() => rendition.manager.views.all().some((v) => v.contents), null, { timeout: 5000 })
        .catch(() => { throw new Error('the resize showed no page'); });
      const shown = await p.evaluate((asked) => {
        const { start, end } = rendition.currentLocation();
        const cfi = new ePub.CFI();
        return { index: start.index, holds: cfi.compare(start.cfi, asked) <= 0 && cfi.compare(asked, end.cfi) <= 0 };
      }, place);
      expect(shown.index === 0 && shown.holds, `the resize showed ${JSON.stringify(shown)}, not the page with ${place}`);
    } finally {
      await p.close();
    }
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

  ['next() shows every page of a chapter before the next one', async () => {
    // The book again, in horizontal text. A page turn there lands on the
    // nearest device pixel, and epub.js added that error up turn by turn
    // until it left each chapter from its second to last page.
    await page.goto('http://viewer.localhost/reader.html');
    await until(0, `c.name === 'readyToLoad'`);
    const bytes = fs.readFileSync(path.join(here, 'book.epub'));
    await page.evaluate(`beginEpubTransfer(${bytes.length}); appendEpubChunk('${bytes.toString('base64')}')`);
    // What Dart sends with vertical text off: ltr, the horizontal axis, and
    // a writing-mode override (reader_display_settings_mapper.dart).
    const css = JSON.stringify({ html: { 'writing-mode': 'horizontal-tb !important' } });
    await page.evaluate(`loadBook("", "ltr", "paginated", false, "28", "#000000", ${css}, 28, 28, true, "off", 1, null)`);
    await until(0, `c.name === 'pageChars'`, 15000);
    const where = () => page.evaluate(() => {
      const s = rendition.currentLocation().start;
      return [s.index, s.displayed.page, s.displayed.total];
    });
    let [index, shown, total] = await where();
    const pages = [];
    while (index === 0 && pages.length <= total) {
      pages.push(shown);
      const at = await mark();
      await page.evaluate('next()');
      await until(at, `c.name === 'pageChars'`);
      [index, shown] = await where();
    }
    const all = Array.from({ length: total }, (_, i) => i + 1).join();
    expect(total >= 3 && pages.join() === all, `chapter 1 showed pages ${pages.join()} of ${total}`);
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
