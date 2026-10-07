/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Runs Mozilla's Bergamot engine off the page's thread. Each message is
// {id, text, pairs: [{name: "ja-en", files: {model, lex, vocab}}]} with file
// URLs; models load on first use and stay loaded for the worker's life.
importScripts("bergamot-translator.js", "engine-core.js");

// Promises, so a message that comes while the first one still loads waits
// for that load instead of starting a second engine. A failed load is
// forgotten, and the next message tries again.
let engine;
const models = new Map();

function forgetOnFailure(promise, forget) {
  return promise.catch((error) => {
    forget();
    throw error;
  });
}

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

async function loadModel(bergamot, { name, files }) {
  const buffers = {};
  for (const [type, url] of Object.entries(files)) {
    buffers[type] = await fetchBuffer(url);
  }
  const [from, to] = name.split("-");
  return createModel(bergamot, from, to, buffers);
}

onmessage = async ({ data: { id, text, pairs } }) => {
  try {
    engine ??= forgetOnFailure(loadEngine(), () => (engine = undefined));
    const { bergamot, service } = await engine;
    const chain = [];
    for (const pair of pairs) {
      if (!models.has(pair.name)) {
        models.set(
          pair.name,
          forgetOnFailure(loadModel(bergamot, pair), () =>
            models.delete(pair.name)
          )
        );
      }
      chain.push(await models.get(pair.name));
    }
    postMessage({
      id,
      text: translateText(bergamot, service, chain, text),
    });
  } catch (error) {
    postMessage({ id, error: String(error?.message ?? error) });
  }
};
