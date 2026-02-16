// Clean epub.js bridge — all page navigation driven by Dart.
// No custom swipe detection. No rendition method overrides.
// snap: false — epub.js does NOT handle any gestures.

var book = ePub();
var rendition;
var displayed;
var chapters = [];
var hasSelection = false;
var currentMargins = { horizontal: 28, vertical: 28 };
var _lastTappedBlock = null;       // block element from last getTextAtPoint
var _lastTappedDoc = null;         // document from last getTextAtPoint
var _currentWordHighlightCfi = null; // CFI of current word highlight

function callDart(name) {
  var args = Array.prototype.slice.call(arguments, 1);
  try {
    window.flutter_inappwebview.callHandler(name, ...args);
  } catch (e) {
    console.error('callDart error (' + name + '):', e);
  }
}

// ── Book loading ──────────────────────────────────────────────────────

function loadBook(data, cfi, direction, flow, snap, fontSize, foregroundColor, customCss, horizontalMargin, verticalMargin) {
  var uint8 = new Uint8Array(data);
  book.open(uint8);

  // Set initial margins from parameters
  if (typeof horizontalMargin === 'number') currentMargins.horizontal = horizontalMargin;
  if (typeof verticalMargin === 'number') currentMargins.vertical = verticalMargin;
  console.log('[EPUB_BRIDGE] initial margins h=' + currentMargins.horizontal + ' v=' + currentMargins.vertical);

  rendition = book.renderTo('viewer', {
    manager: 'default',
    flow: flow || 'paginated',
    spread: 'none',
    width: '100vw',
    height: '100vh',
    snap: false,
    allowScriptedContent: false,
    defaultDirection: direction || 'ltr'
  });

  console.log('[EPUB_BRIDGE] rendition created with snap:false flow:' + (flow || 'paginated') + ' dir:' + (direction || 'ltr'));

  // Apply initial theme
  updateTheme(foregroundColor, customCss);

  // Apply initial font size
  if (fontSize) {
    rendition.themes.fontSize(fontSize + 'px');
  }

  // Apply initial margins to .epub-container CSS before first display,
  // so Stage.size() reads the correct padding when calculating layout.
  applyMargins();

  // Display at CFI or beginning
  if (cfi) {
    displayed = rendition.display(cfi);
  } else {
    displayed = rendition.display();
  }

  // ── Events ────────────────────────────────────────────────────────

  rendition.on('displayed', function () {
    console.log('[EPUB_BRIDGE] displayed event fired');
    callDart('loaded');
  });

  rendition.on('relocated', function (location) {
    if (!location || !location.start) return;
    var percent = location.start.percentage;
    var page = location.start.displayed ? location.start.displayed.page : '?';
    var total = location.start.displayed ? location.start.displayed.total : '?';
    console.log('[EPUB_BRIDGE] relocated cfi=' + location.start.cfi +
      ' sectionIndex=' + location.start.index +
      ' page=' + page + '/' + total +
      ' progress=' + percent);
    callDart('relocated', {
      startCfi: location.start.cfi,
      endCfi: location.end ? location.end.cfi : location.start.cfi,
      progress: percent
    });
  });

  rendition.on('displayError', function () {
    console.log('[EPUB_BRIDGE] displayError event');
    callDart('displayError');
  });

  // ── TOC ───────────────────────────────────────────────────────────

  book.loaded.navigation.then(function (toc) {
    chapters = parseToc(toc);
    console.log('[EPUB_BRIDGE] TOC parsed, ' + chapters.length + ' top-level chapters');
    callDart('chapters', chapters);
  }).catch(function (err) {
    console.error('[EPUB_BRIDGE] TOC loading failed:', err);
    callDart('chapters', []);
  });

  // ── Locations (for progress) ──────────────────────────────────────

  book.ready.then(function () {
    book.locations.generate(1600).then(function () {
      console.log('[EPUB_BRIDGE] locations generated');
      callDart('locationsReady');
    });
  });

  // ── Selection ─────────────────────────────────────────────────────

  rendition.on('selected', function (cfiRange, contents) {
    hasSelection = true;
    try {
      var selectedText = '';
      var rect = null;
      var sel = contents.window.getSelection();
      if (sel && sel.rangeCount > 0) {
        selectedText = sel.toString();
        var range = sel.getRangeAt(0);
        var clientRect = range.getBoundingClientRect();
        var iframe = contents.document.defaultView.frameElement;
        var iframeRect = iframe.getBoundingClientRect();
        var ww = window.innerWidth;
        var wh = window.innerHeight;
        rect = {
          left: (iframeRect.left + clientRect.left) / ww,
          top: (iframeRect.top + clientRect.top) / wh,
          width: clientRect.width / ww,
          height: clientRect.height / wh
        };
      }
      callDart('selection', {
        cfi: cfiRange.toString(),
        text: selectedText,
        rect: rect
      });
    } catch (e) {
      callDart('selection', {
        cfi: cfiRange.toString(),
        text: '',
        rect: null
      });
    }
  });

  // Monitor for selection clearing
  rendition.hooks.content.register(function (contents) {
    contents.window.document.addEventListener('selectionchange', function () {
      var sel = contents.window.getSelection();
      var text = sel ? sel.toString() : '';
      if (!text && hasSelection) {
        hasSelection = false;
        callDart('selectionCleared');
      }
    });

    // ── Touch events (forward to Dart for tap-zone navigation) ────

    var doc = contents.document;

    doc.addEventListener('touchstart', function (e) {
      if (e.touches && e.touches.length > 0) {
        var coords = normalizedCoords(e.touches[0], contents);
        if (coords) {
          console.log('[EPUB_BRIDGE] touchDown x=' + coords.x.toFixed(3) + ' y=' + coords.y.toFixed(3));
          callDart('touchDown', coords.x, coords.y);
        }
      }
    }, { passive: true });

    doc.addEventListener('touchend', function (e) {
      if (e.changedTouches && e.changedTouches.length > 0) {
        var touch = e.changedTouches[0];
        var coords = normalizedCoords(touch, contents);
        if (coords) {
          // Check if tap landed on text
          var textInfo = getTextAtPoint(touch.clientX, touch.clientY, doc);
          if (textInfo) {
            console.log('[EPUB_BRIDGE] wordTapped char="' + textInfo.tappedChar +
              '" offset=' + textInfo.charOffset +
              ' textLen=' + textInfo.surroundingText.length);
            callDart('wordTapped', {
              x: coords.x,
              y: coords.y,
              surroundingText: textInfo.surroundingText,
              charOffset: textInfo.charOffset,
              blockCharOffset: textInfo.blockCharOffset,
              tappedChar: textInfo.tappedChar
            });
          } else {
            // No text at tap point — send regular touchUp for page navigation
            console.log('[EPUB_BRIDGE] touchUp x=' + coords.x.toFixed(3) + ' y=' + coords.y.toFixed(3));
            callDart('touchUp', coords.x, coords.y);
          }
        }
      }
    }, { passive: true });
  });
}

// ── Navigation (section-aware — bypasses epub.js broken scroll-delta logic) ──

function next() {
  if (!rendition || !rendition.location || !rendition.location.start) {
    console.log('[EPUB_BRIDGE] next() called but no location yet');
    return;
  }
  var loc = rendition.location;
  var currentPage = loc.start.displayed ? loc.start.displayed.page : 1;
  var totalPages = loc.start.displayed ? loc.start.displayed.total : 1;
  console.log('[EPUB_BRIDGE] next() page=' + currentPage + '/' + totalPages +
    ' sectionIndex=' + loc.start.index + ' cfi=' + loc.start.cfi);

  if (currentPage < totalPages) {
    // More pages within this section — epub.js scroll-within-section works fine
    console.log('[EPUB_BRIDGE] next() scrolling within section');
    rendition.next();
  } else {
    // At last page of section — directly navigate to next spine item
    // This bypasses the broken DefaultViewManager.next() delta comparison
    var spineItem = book.spine.get(loc.start.index);
    if (spineItem) {
      var nextItem = spineItem.next();
      if (nextItem) {
        console.log('[EPUB_BRIDGE] next() jumping to section index=' +
          nextItem.index + ' href=' + nextItem.href);
        rendition.display(nextItem.href);
      } else {
        console.log('[EPUB_BRIDGE] next() already at last section');
      }
    } else {
      console.log('[EPUB_BRIDGE] next() could not get spine item at index=' + loc.start.index);
    }
  }
}

function previous() {
  if (!rendition || !rendition.location || !rendition.location.start) {
    console.log('[EPUB_BRIDGE] previous() called but no location yet');
    return;
  }
  var loc = rendition.location;
  var currentPage = loc.start.displayed ? loc.start.displayed.page : 1;
  var totalPages = loc.start.displayed ? loc.start.displayed.total : 1;
  console.log('[EPUB_BRIDGE] previous() page=' + currentPage + '/' + totalPages +
    ' sectionIndex=' + loc.start.index + ' cfi=' + loc.start.cfi);

  if (currentPage > 1) {
    // More pages before this one in the section — scroll backwards within section
    console.log('[EPUB_BRIDGE] previous() scrolling within section');
    rendition.prev();
  } else {
    // At first page of section — navigate to LAST page of previous spine item
    var spineItem = book.spine.get(loc.start.index);
    if (spineItem) {
      var prevItem = spineItem.prev();
      if (prevItem) {
        console.log('[EPUB_BRIDGE] previous() jumping to end of section index=' +
          prevItem.index + ' href=' + prevItem.href);
        // Display the previous section, then scroll the manager's container
        // to the last page. epub.js paginates using CSS columns; the axis
        // determines whether pagination is horizontal or vertical.
        // For vertical Japanese text (writing-mode: vertical-rl), the axis
        // is "vertical" and pages scroll top-to-bottom.
        rendition.display(prevItem.href).then(function () {
          var manager = rendition.manager;
          if (!manager || !manager.container) return;

          var container = manager.container;
          var axis = manager.settings.axis;
          var dir = manager.settings.direction;

          if (axis === 'vertical') {
            // Vertical pagination (e.g. Japanese vertical text):
            // pages go top-to-bottom, so scroll to the bottom.
            var lastPageOffset = container.scrollHeight - container.offsetHeight;
            if (lastPageOffset < 0) lastPageOffset = 0;
            manager.scrollTo(0, lastPageOffset, true);
            console.log('[EPUB_BRIDGE] previous() vertical snap scrollTop=' +
              lastPageOffset + ' scrollHeight=' + container.scrollHeight);
          } else {
            // Horizontal pagination
            var delta = manager.layout ? manager.layout.delta : container.offsetWidth;
            if (dir === 'rtl') {
              if (manager.settings.rtlScrollType === 'default') {
                // "default" RTL: scrollLeft starts at scrollWidth-clientWidth
                // and decreases toward 0. First page is at max, last page at 0.
                manager.scrollTo(0, 0, true);
              } else {
                // "negative" RTL: scrollLeft is negative.
                var maxScroll = container.scrollWidth - delta;
                manager.scrollTo(-maxScroll, 0, true);
              }
              console.log('[EPUB_BRIDGE] previous() RTL snap scrollLeft=' +
                container.scrollLeft + ' scrollWidth=' + container.scrollWidth);
            } else {
              var lastPageOffset = container.scrollWidth - delta;
              if (lastPageOffset < 0) lastPageOffset = 0;
              manager.scrollTo(lastPageOffset, 0, true);
              console.log('[EPUB_BRIDGE] previous() LTR snap scrollLeft=' +
                lastPageOffset + ' scrollWidth=' + container.scrollWidth);
            }
          }
          rendition.reportLocation();
        });
      } else {
        console.log('[EPUB_BRIDGE] previous() already at first section');
      }
    } else {
      console.log('[EPUB_BRIDGE] previous() could not get spine item at index=' + loc.start.index);
    }
  }
}

function toCfi(cfi) {
  console.log('[EPUB_BRIDGE] toCfi: ' + cfi);
  if (rendition) rendition.display(cfi);
}

function toProgress(progress) {
  console.log('[EPUB_BRIDGE] toProgress: ' + progress);
  if (book && book.locations) {
    var cfi = book.locations.cfiFromPercentage(progress);
    if (rendition) rendition.display(cfi);
  }
}

function getCurrentLocation() {
  if (!rendition || !rendition.location || !rendition.location.start) return;
  var loc = rendition.location;
  callDart('currentLocation', {
    startCfi: loc.start.cfi,
    endCfi: loc.end ? loc.end.cfi : loc.start.cfi,
    progress: loc.start.percentage
  });
}

// ── TOC parsing ───────────────────────────────────────────────────────

function parseToc(toc) {
  // epub.js may pass a Navigation object with .toc property, or a plain array
  console.log('[EPUB_BRIDGE] parseToc raw type=' + typeof toc +
    ' isArray=' + Array.isArray(toc) +
    ' has .toc=' + !!(toc && toc.toc) +
    ' length=' + (toc ? (toc.length || (toc.toc && toc.toc.length) || 0) : 0));
  var items = Array.isArray(toc) ? toc : (toc && toc.toc ? toc.toc : []);
  function walk(list) {
    var result = [];
    for (var i = 0; i < list.length; i++) {
      var item = list[i];
      if (!item) continue;
      result.push({
        title: (item.label || item.title || '').trim(),
        href: item.href || '',
        id: item.id || '',
        subitems: item.subitems ? walk(item.subitems) : []
      });
    }
    return result;
  }
  return walk(items);
}

function getChapters() {
  return chapters;
}

// ── Display settings ──────────────────────────────────────────────────

function setFontSize(size) {
  if (rendition) {
    rendition.themes.fontSize(size + 'px');
  }
}

function updateTheme(foregroundColor, customCss) {
  if (!rendition) return;
  var rules = {};
  if (customCss) {
    try {
      var parsed = typeof customCss === 'string' ? JSON.parse(customCss) : customCss;
      for (var selector in parsed) {
        if (parsed.hasOwnProperty(selector)) {
          rules[selector] = parsed[selector];
        }
      }
    } catch (e) {
      console.error('updateTheme parse error:', e);
    }
  }
  if (foregroundColor) {
    if (!rules['body']) rules['body'] = {};
    rules['body']['color'] = foregroundColor + ' !important';
  }
  rendition.themes.register('default', rules);
  rendition.themes.select('default');
}

// ── Background color ─────────────────────────────────────────────────

function setBodyBackground(color) {
  document.body.style.background = color;
  var viewer = document.getElementById('viewer');
  if (viewer) viewer.style.background = color;
  console.log('[EPUB_BRIDGE] setBodyBackground: ' + color);
}

// ── Margins ──────────────────────────────────────────────────────────

function applyMargins() {
  // Shrink .epub-container to create visible margins around it.
  // The white space of #viewer around the smaller container acts as margins.
  // Using width/height instead of padding avoids the CSS overflow:hidden
  // padding-box clipping issue (overflow:hidden clips at the padding edge,
  // not the content edge, so padding-based margins let content bleed through).
  // epub.js Stage.size() reads container.clientWidth/clientHeight which
  // reflects the reduced dimensions, so pagination is correct.
  var styleEl = document.getElementById('marginStyle');
  if (!styleEl) return;
  var h = currentMargins.horizontal;
  var v = currentMargins.vertical;
  styleEl.textContent =
    '.epub-container {' +
    '  width: calc(100vw - ' + (h * 2) + 'px) !important;' +
    '  height: calc(100vh - ' + (v * 2) + 'px) !important;' +
    '  position: absolute !important;' +
    '  top: ' + v + 'px !important;' +
    '  left: ' + h + 'px !important;' +
    '}';
  console.log('[EPUB_BRIDGE] applyMargins container h=' + h + ' v=' + v);
}

function setMargins(horizontal, vertical) {
  currentMargins.horizontal = horizontal;
  currentMargins.vertical = vertical;
  console.log('[EPUB_BRIDGE] setMargins h=' + horizontal + ' v=' + vertical);

  // Update the container CSS rule
  applyMargins();

  // Trigger epub.js re-layout at current position
  if (rendition && rendition.manager) {
    // Invalidate cached stage size so resize() recalculates with new padding
    rendition.manager._stageSize = undefined;
    // Save current reading position before resize (which clears views)
    var cfi = rendition.location && rendition.location.start
        ? rendition.location.start.cfi : null;
    console.log('[EPUB_BRIDGE] setMargins resizing, will restore cfi=' + cfi);
    rendition.resize();
    // Restore position after re-layout
    if (cfi) rendition.display(cfi);
  }
}

// ── Search ────────────────────────────────────────────────────────────

function searchInBook(query) {
  if (!book || !book.spine) {
    callDart('searchResults', []);
    return;
  }
  Promise.all(
    book.spine.spineItems.map(function (item) {
      return item.load(book.load.bind(book))
        .then(item.find.bind(item, query))
        .finally(item.unload.bind(item));
    })
  ).then(function (results) {
    var flat = [].concat.apply([], results);
    callDart('searchResults', flat);
  }).catch(function () {
    callDart('searchResults', []);
  });
}

// ── Annotations ───────────────────────────────────────────────────────

function addHighlight(cfi, color, opacity) {
  if (!rendition) return;
  rendition.annotations.highlight(
    cfi, {},
    function () {},
    'epub-highlight',
    { 'fill': color || 'yellow', 'fill-opacity': opacity || '0.3' }
  );
}

function removeHighlight(cfi) {
  if (!rendition) return;
  rendition.annotations.remove(cfi, 'highlight');
}

function addUnderline(cfi) {
  if (!rendition) return;
  rendition.annotations.underline(cfi, {}, function () {}, 'epub-underline');
}

function removeUnderline(cfi) {
  if (!rendition) return;
  rendition.annotations.remove(cfi, 'underline');
}

// ── Selection ─────────────────────────────────────────────────────────

function clearSelection() {
  if (!rendition) return;
  try {
    rendition.getContents().forEach(function (contents) {
      try {
        var sel = contents.window.getSelection();
        if (sel) sel.removeAllRanges();
      } catch (e) { /* ignore */ }
    });
  } catch (e) { /* ignore */ }
  hasSelection = false;
  callDart('selectionCleared');
}

function getSelectionState() {
  return hasSelection;
}

// ── Text extraction ───────────────────────────────────────────────────

function getCurrentPageText() {
  if (!rendition || !rendition.location) return;
  var startCfi = rendition.location.start.cfi;
  var endCfi = rendition.location.end ? rendition.location.end.cfi : startCfi;
  getTextFromCfi(startCfi, endCfi);
}

function getTextFromCfi(startCfi, endCfi) {
  if (!book) return;
  book.getRange(startCfi + ',' + endCfi).then(function (range) {
    var text = range ? range.toString() : '';
    callDart('pageText', { text: text, startCfi: startCfi, endCfi: endCfi });
  }).catch(function () {
    callDart('pageText', { text: '', startCfi: startCfi, endCfi: endCfi });
  });
}

// ── Word-at-point detection ───────────────────────────────────────────

function getTextAtPoint(clientX, clientY, doc) {
  try {
    var range = doc.caretRangeFromPoint(clientX, clientY);
    if (!range) return null;

    var node = range.startContainer;
    var offset = range.startOffset;

    // Must be a text node
    if (node.nodeType !== 3) return null;

    // If inside <rt> (furigana annotation), use the base text from <ruby>
    var parent = node.parentElement;
    while (parent) {
      if (parent.tagName === 'RT') {
        var ruby = parent.closest('ruby');
        if (ruby) {
          // Find the first direct text node child of <ruby> (the base text)
          var baseNode = null;
          for (var i = 0; i < ruby.childNodes.length; i++) {
            var child = ruby.childNodes[i];
            if (child.nodeType === 3 && child.textContent.trim().length > 0) {
              baseNode = child;
              break;
            }
          }
          if (baseNode) {
            node = baseNode;
            offset = Math.min(offset, node.textContent.length - 1);
            if (offset < 0) offset = 0;
          }
        }
        break;
      }
      parent = parent.parentElement;
    }

    // Find the nearest block-level ancestor
    var blockTags = ['P', 'DIV', 'LI', 'TD', 'TH', 'BLOCKQUOTE', 'SECTION',
                     'ARTICLE', 'H1', 'H2', 'H3', 'H4', 'H5', 'H6', 'BODY'];
    var block = node.parentElement;
    while (block && blockTags.indexOf(block.tagName) === -1) {
      block = block.parentElement;
    }
    if (!block) block = doc.body;

    // Collect full text content and compute character offset
    // by walking text nodes in document order
    var walker = doc.createTreeWalker(block, NodeFilter.SHOW_TEXT, null, false);
    var charOffset = 0;
    var foundTarget = false;
    var current;

    while ((current = walker.nextNode())) {
      // Skip text nodes inside <rt> elements (furigana)
      var isRt = false;
      var p = current.parentElement;
      while (p && p !== block) {
        if (p.tagName === 'RT') { isRt = true; break; }
        p = p.parentElement;
      }
      if (isRt) continue;

      if (current === node) {
        charOffset += offset;
        foundTarget = true;
        break;
      }
      charOffset += current.textContent.length;
    }

    if (!foundTarget) return null;

    // Store block reference for later highlighting
    _lastTappedBlock = block;
    _lastTappedDoc = doc;

    // The raw offset within the block text (before any trimming)
    var blockCharOffset = charOffset;

    // Build surrounding text (excluding <rt> content)
    var surroundingText = getBlockTextWithoutRt(block);

    // Limit to ~500 characters around the tap point
    var maxLen = 500;
    if (surroundingText.length > maxLen) {
      var sentenceDelimiters = '\u3002\uff01\uff1f\n';
      var start = Math.max(0, charOffset - Math.floor(maxLen / 2));
      var end = Math.min(surroundingText.length, charOffset + Math.floor(maxLen / 2));

      // Try to snap to sentence boundaries
      for (var s = start; s > Math.max(0, start - 100); s--) {
        if (sentenceDelimiters.indexOf(surroundingText[s]) !== -1) {
          start = s + 1;
          break;
        }
      }
      for (var e = end; e < Math.min(surroundingText.length, end + 100); e++) {
        if (sentenceDelimiters.indexOf(surroundingText[e]) !== -1) {
          end = e + 1;
          break;
        }
      }

      charOffset = charOffset - start;
      surroundingText = surroundingText.substring(start, end);
    }

    var tappedChar = charOffset < surroundingText.length
        ? surroundingText[charOffset]
        : '';

    // If the resolved character is empty or whitespace, the tap landed on
    // blank space (caretRangeFromPoint snaps to the nearest text node even
    // when tapping far from any text).  Treat this as "no text at point".
    if (!tappedChar || !tappedChar.trim()) return null;

    return {
      surroundingText: surroundingText,
      charOffset: charOffset,
      blockCharOffset: blockCharOffset,
      tappedChar: tappedChar
    };
  } catch (e) {
    console.error('[EPUB_BRIDGE] getTextAtPoint error:', e);
    return null;
  }
}

function getBlockTextWithoutRt(block) {
  var text = '';
  var walker = block.ownerDocument.createTreeWalker(
    block, NodeFilter.SHOW_TEXT, null, false
  );
  var current;
  while ((current = walker.nextNode())) {
    var isRt = false;
    var p = current.parentElement;
    while (p && p !== block) {
      if (p.tagName === 'RT') { isRt = true; break; }
      p = p.parentElement;
    }
    if (!isRt) {
      text += current.textContent;
    }
  }
  return text;
}

// ── Word highlighting ─────────────────────────────────────────────────

function highlightWordInBlock(blockCharStart, wordLength) {
  try {
    // Clear any previous word highlight
    clearWordHighlight();

    if (!_lastTappedBlock || !_lastTappedDoc) {
      console.warn('[EPUB_BRIDGE] highlightWordInBlock: no stored block');
      return;
    }
    if (!rendition) return;

    var block = _lastTappedBlock;
    var doc = _lastTappedDoc;

    // Walk text nodes (skipping <rt>) to find the Range for the word
    var walker = doc.createTreeWalker(block, NodeFilter.SHOW_TEXT, null, false);
    var runningOffset = 0;
    var startNode = null, startOffset = 0;
    var endNode = null, endOffset = 0;
    var current;
    var wordEnd = blockCharStart + wordLength;

    while ((current = walker.nextNode())) {
      // Skip <rt> text nodes
      var isRt = false;
      var p = current.parentElement;
      while (p && p !== block) {
        if (p.tagName === 'RT') { isRt = true; break; }
        p = p.parentElement;
      }
      if (isRt) continue;

      var nodeLen = current.textContent.length;
      var nodeEnd = runningOffset + nodeLen;

      // Find start node
      if (!startNode && blockCharStart >= runningOffset && blockCharStart < nodeEnd) {
        startNode = current;
        startOffset = blockCharStart - runningOffset;
      }

      // Find end node
      if (!endNode && wordEnd > runningOffset && wordEnd <= nodeEnd) {
        endNode = current;
        endOffset = wordEnd - runningOffset;
      }

      runningOffset = nodeEnd;
      if (startNode && endNode) break;
    }

    if (!startNode || !endNode) {
      console.warn('[EPUB_BRIDGE] highlightWordInBlock: could not find text nodes');
      return;
    }

    // Create a Range spanning the word
    var range = doc.createRange();
    range.setStart(startNode, startOffset);
    range.setEnd(endNode, endOffset);

    // Convert Range to CFI using epub.js contents
    var contents = rendition.getContents();
    if (contents && contents.length > 0) {
      var cfi = contents[0].cfiFromRange(range);
      if (cfi) {
        addHighlight(cfi, '#4FC3F7', '0.4');
        _currentWordHighlightCfi = cfi;
        console.log('[EPUB_BRIDGE] highlighted word CFI: ' + cfi);
      }
    }
  } catch (e) {
    console.error('[EPUB_BRIDGE] highlightWordInBlock error:', e);
  }
}

function clearWordHighlight() {
  if (_currentWordHighlightCfi) {
    try {
      removeHighlight(_currentWordHighlightCfi);
    } catch (e) { /* ignore */ }
    _currentWordHighlightCfi = null;
  }
}

// ── Helpers ───────────────────────────────────────────────────────────

function normalizedCoords(touch, contents) {
  try {
    var iframe = contents.document.defaultView.frameElement;
    var iframeRect = iframe.getBoundingClientRect();
    // Normalize against the outer viewport (not the iframe), so coordinates
    // reflect the actual screen position.  touch.clientX/Y are relative to
    // the iframe viewport, so add the iframe's offset first.
    var outerW = window.innerWidth || iframeRect.width;
    var outerH = window.innerHeight || iframeRect.height;
    var x = (iframeRect.left + touch.clientX) / outerW;
    var y = (iframeRect.top + touch.clientY) / outerH;
    x = Math.max(0, Math.min(1, x));
    y = Math.max(0, Math.min(1, y));
    return { x: x, y: y };
  } catch (e) {
    return null;
  }
}

// ── Init signal ───────────────────────────────────────────────────────

window.flutter_inappwebview.callHandler('readyToLoad');
