// Runs before the viewer's scripts and stands in for flutter_inappwebview:
// records every callHandler call in window.__calls, with its arguments
// JSON round-tripped as the plugin sends them to Dart, and answers the
// handlers that return something the way custom_epub_viewer.dart does.
(function () {
  var calls = (window.__calls = []);
  // False plays MeCab not being up: FuriganaGenerator.generate answers null.
  window.__mecabReady = true;
  var KANJI = /([一-龯々]+)|([^一-龯々]+)/g;
  // Dart accepts either ['a', 'b'] or [['a', 'b']].
  function inputs(args) { return Array.isArray(args[0]) ? args[0] : args; }
  var replies = {
    // A reading for every kanji run, in FuriganaGenerator.generate's shape.
    generateFurigana: function (args) {
      if (!window.__mecabReady) return null;
      return inputs(args).map(function (text) {
        var segments = [];
        String(text).replace(KANJI, function (m, kanji, other) {
          segments.push(kanji ? { t: kanji, f: 'ふり' } : { t: other });
        });
        return { source: text, segments: segments };
      });
    },
    needsFurigana: function (args) {
      return inputs(args).map(function () { return true; });
    },
  };
  window.flutter_inappwebview = {
    callHandler: function (name) {
      var args = Array.prototype.slice.call(arguments, 1);
      calls.push({ name: name, args: JSON.parse(JSON.stringify(args)) });
      var reply = replies[name];
      return Promise.resolve(reply ? reply(args) : null);
    },
  };
})();
