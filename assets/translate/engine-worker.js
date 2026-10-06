/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Runs Mozilla's Bergamot engine off the page's thread. Each message is
// {id, text, pairs: [{name: "ja-en", files: {model, lex, vocab}}]} with file
// URLs; models load on first use and stay loaded for the worker's life.
importScripts("bergamot-translator.js", "engine-core.js");

let engine;
const models = new Map();

async function fetchBuffer(url) {
  const response = await fetch(url);
  if (!response.ok) throw new Error(`${response.status} for ${url}`);
  return response.arrayBuffer();
}

async function loadEngine() {
  const bergamot = await initBergamot(
    loadBergamot,
    await fetchBuffer("bergamot-translator.wasm")
  );
  return { bergamot, service: new bergamot.BlockingService({ cacheSize: 0 }) };
}

async function loadModel({ name, files }) {
  const buffers = {};
  for (const [type, url] of Object.entries(files)) {
    buffers[type] = await fetchBuffer(url);
  }
  const [from, to] = name.split("-");
  return createModel(engine.bergamot, from, to, buffers);
}

onmessage = async ({ data: { id, text, pairs } }) => {
  try {
    engine ??= await loadEngine();
    const chain = [];
    for (const pair of pairs) {
      if (!models.has(pair.name)) models.set(pair.name, await loadModel(pair));
      chain.push(models.get(pair.name));
    }
    postMessage({
      id,
      text: translateText(engine.bergamot, engine.service, chain, text),
    });
  } catch (error) {
    postMessage({ id, error: String(error?.message ?? error) });
  }
};
