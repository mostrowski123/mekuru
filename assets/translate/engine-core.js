/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Mekuru's driver for Mozilla's Bergamot translation engine, adapted from
// Firefox's toolkit/components/translations/content/translations-engine.worker.js.
// Shared by the WebView worker and the desktop test harness.

const MODEL_FILE_ALIGNMENTS = {
  model: 256,
  lex: 64,
  vocab: 64,
  srcvocab: 64,
  trgvocab: 64,
};

/** Loads the engine; resolves with the Bergamot module. */
function initBergamot(loadBergamot, wasmBinary) {
  return new Promise((resolve, reject) => {
    const bergamot = loadBergamot({
      // Firefox starts at 40 MiB and lets the memory grow.
      INITIAL_MEMORY: 41_943_040,
      print: () => {},
      printErr: () => {},
      onAbort() {
        reject(new Error("Error loading Bergamot wasm module."));
      },
      onRuntimeInitialized: async () => {
        await Promise.resolve();
        resolve(bergamot);
      },
      wasmBinary,
    });
  });
}

function textConfig(config) {
  const indent = "            ";
  let result = "\n";
  for (const [key, value] of Object.entries(config)) {
    result += `${indent}${key}: ${value}\n`;
  }
  return result + indent;
}

/**
 * Builds a TranslationModel from its files: {model, lex, vocab} or
 * {model, lex, srcvocab, trgvocab}, each an ArrayBuffer.
 */
function createModel(bergamot, from, to, files) {
  const aligned = {};
  for (const [type, buffer] of Object.entries(files)) {
    const memory = new bergamot.AlignedMemory(
      buffer.byteLength,
      MODEL_FILE_ALIGNMENTS[type]
    );
    memory.getByteArrayView().set(new Uint8Array(buffer));
    aligned[type] = memory;
  }
  const vocabs = new bergamot.AlignedMemoryList();
  if (aligned.vocab) {
    vocabs.push_back(aligned.vocab);
  } else {
    vocabs.push_back(aligned.srcvocab);
    vocabs.push_back(aligned.trgvocab);
  }
  const config = textConfig({
    "beam-size": "1",
    normalize: "1.0",
    "word-penalty": "0",
    "max-length-break": "128",
    "mini-batch-words": "1024",
    workspace: "128",
    "max-length-factor": "2.0",
    "skip-cost": "true",
    "cpu-threads": "0",
    quiet: "true",
    "quiet-translation": "true",
    "gemm-precision": "int8shiftAlphaAll",
    alignment: "soft",
  });
  return new bergamot.TranslationModel(
    from,
    to,
    config,
    aligned.model,
    aligned.lex ?? null,
    vocabs,
    null
  );
}

/**
 * Translates [text] with one model, or two when pivoting through English
 * (ja→en→es).
 */
function translateText(bergamot, service, models, text) {
  // Firefox: soft hyphens break tokenization, and Intl.Segmenter keeps a
  // “ after 。 with the wrong sentence unless a space separates them.
  // Novels' full-width spaces (after ！ and ？) would come out in the English.
  const cleaned = text
    .trim()
    .replaceAll("­", "")
    .replaceAll("　", " ")
    .replaceAll(/([。！？])“/g, "$1 “");
  if (!cleaned) return "";
  const messages = new bergamot.VectorString();
  const options = new bergamot.VectorResponseOptions();
  messages.push_back(cleaned);
  options.push_back({ qualityScores: false, alignment: true, html: false });
  let responses;
  try {
    responses =
      models.length === 1
        ? service.translate(models[0], messages, options)
        : service.translateViaPivoting(models[0], models[1], messages, options);
    return responses.get(0).getTranslatedText();
  } finally {
    messages.delete();
    options.delete();
    responses?.delete();
  }
}

if (typeof module !== "undefined") {
  module.exports = { initBergamot, createModel, translateText };
}
