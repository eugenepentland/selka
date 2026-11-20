// highlight.js grammar for Selka, so a fenced block marked `selka` is coloured like the other languages. mdBook loads this
// after its bundled highlight.js and book.js, and book.js has already highlighted every block by then (a `selka` block fell
// back to plain text), so the blocks of this language are highlighted again once it is registered. It reads the page only;
// nothing is fetched.
(function () {
    if (typeof hljs === 'undefined') return;
    hljs.registerLanguage('selka', function (hljs) {
        var ESCAPE = { className: 'subst', begin: /\\(?:x[0-9a-fA-F]{2}|u\{[0-9a-fA-F]+\}|.)/, relevance: 0 };
        var NUMBER = {
            className: 'number', relevance: 0,
            begin: /\b(?:0[xX][0-9a-fA-F_]+|0[bB][01_]+|0[oO][0-7_]+|\d[\d_]*(?:\.\d[\d_]*)?(?:[eE][+-]?\d+)?)(?:[iuf]\d+)?\b/
        };
        var KEYWORDS = {
            keyword: 'func def record union enum type domain import public private const mut extern fails try fail return ' +
                'if elif else while for in is not and or match case assert pass break continue with as arena wrap todo ' +
                'conversion where bit_and bit_or bit_xor bit_not shift_left shift_right wrapping_add wrapping_sub ' +
                'wrapping_mul saturating_add saturating_sub saturating_mul',
            type: 'int float f32 f64 bool str bytes list dict set tuple i8 i16 i32 i64 u8 u16 u32 u64',
            literal: 'True False None',
            built_in: 'print debug copy range len ok err'
        };
        // A string may start with f, b or r; in an f string the braces hold code.
        function string(quote, prefix, contains) {
            return { className: 'string', begin: prefix + quote, end: quote, contains: contains, relevance: 0 };
        }
        var SUBST = { className: 'subst', begin: /\{(?!\{)/, end: /\}/, keywords: KEYWORDS, contains: [NUMBER] };
        var TRIPLE = ['"""', "'''"].map(function (q) { return string(q, '[fbr]?', [ESCAPE]); });
        return {
            name: 'Selka',
            keywords: KEYWORDS,
            contains: [].concat(
                [hljs.HASH_COMMENT_MODE],
                TRIPLE,
                [string('"', 'f', [ESCAPE, SUBST]), string("'", 'f', [ESCAPE, SUBST])],
                [string('"', '[br]?', [ESCAPE]), string("'", '[br]?', [ESCAPE])],
                [{ className: 'meta', begin: /@[a-z_]+/ }],
                [{ className: 'function', beginKeywords: 'func def', end: /[(\[]/, excludeEnd: true,
                    contains: [hljs.UNDERSCORE_TITLE_MODE] }],
                [{ className: 'class', beginKeywords: 'record union enum', end: /[:\[]/, excludeEnd: true,
                    contains: [hljs.UNDERSCORE_TITLE_MODE] }],
                [{ className: 'type', begin: /\b(?!True\b|False\b|None\b)[A-Z]\w*/, relevance: 0 }],
                [NUMBER]
            )
        };
    });
    document.querySelectorAll('code.language-selka').forEach(function (block) { hljs.highlightBlock(block); });
})();
