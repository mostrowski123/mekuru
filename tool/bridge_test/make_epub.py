# Writes the fixtures run.mjs loads. book.epub: two vertical-rl Japanese
# chapters (the first two pages long at run.mjs's viewport, with one
# authored ruby), and a nav. bad_href.epub: three chapters whose links
# carry a '%' that does not decode, see bad_href_entries. Entries carry a
# fixed date, so a rerun writes the same bytes. Run it only to change a
# fixture; commit it with the script.
import base64
import pathlib
import zipfile
from urllib.parse import quote

here = pathlib.Path(__file__).parent
para = ('吾輩は猫である。名前はまだ無い。どこで生れたかとんと見当がつかぬ。'
        '何でも薄暗いじめじめした所でニャーニャー泣いていた事だけは記憶している。') * 4


VERTICAL = '<style>html{writing-mode:vertical-rl;-webkit-writing-mode:vertical-rl;}</style>'


def chapter(title, n, ruby=False, style=VERTICAL, root='xml:lang="ja"', text=para):
    body = ''.join(f'<p>{text}</p>' for _ in range(n))
    if ruby:
        body = '<p><ruby>漢字<rt>かんじ</rt></ruby>を読む。</p>' + body
    return f'''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" {root}><head><title>{title}</title>
{style}</head>
<body><h1>{title}</h1>{body}</body></html>'''


opf = '''<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id" xml:lang="ja">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="id">bridge-test-1</dc:identifier>
<dc:title>試験</dc:title><dc:language>ja</dc:language><meta property="dcterms:modified">2026-01-01T00:00:00Z</meta></metadata>
<manifest><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
<item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/>
<item id="c2" href="c2.xhtml" media-type="application/xhtml+xml"/></manifest>
<spine page-progression-direction="rtl"><itemref idref="c1"/><itemref idref="c2"/></spine></package>'''

nav = '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>目次</title></head>
<body><nav epub:type="toc"><ol><li><a href="c1.xhtml">第一章</a></li><li><a href="c2.xhtml">第二章</a></li></ol></nav></body></html>'''

container = '''<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
<rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>'''

entries = [
    ('mimetype', 'application/epub+zip', zipfile.ZIP_STORED),  # stored, first
    ('META-INF/container.xml', container, zipfile.ZIP_DEFLATED),
    ('OEBPS/content.opf', opf, zipfile.ZIP_DEFLATED),
    ('OEBPS/nav.xhtml', nav, zipfile.ZIP_DEFLATED),
    ('OEBPS/c1.xhtml', chapter('第一章', 6, ruby=True), zipfile.ZIP_DEFLATED),
    ('OEBPS/c2.xhtml', chapter('第二章', 2), zipfile.ZIP_DEFLATED),
]

# bad_href.epub. The zip entries are named with the links' literal text:
# 'c%FF.xhtml' escapes a byte that is not UTF-8, '100%.xhtml' has a '%'
# that starts no escape, and chapter two's picture is 'i%FF.png'. The nav
# links chapter two with a fragment after the bad escape.
bad_opf = opf.replace('bridge-test-1', 'bridge-test-2').replace(
    '<item id="c2" href="c2.xhtml" media-type="application/xhtml+xml"/>',
    '<item id="c2" href="c%FF.xhtml" media-type="application/xhtml+xml"/>'
    '<item id="c3" href="100%.xhtml" media-type="application/xhtml+xml"/>'
    '<item id="i" href="i%FF.png" media-type="image/png"/>',
).replace('<itemref idref="c2"/>', '<itemref idref="c2"/><itemref idref="c3"/>')
bad_nav = nav.replace(
    '<a href="c2.xhtml">第二章</a></li>',
    '<a href="c%FF.xhtml#top">第二章</a></li><li><a href="100%.xhtml">第三章</a></li>',
)
png = base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==')
bad_href_entries = entries[:2] + [
    ('OEBPS/content.opf', bad_opf, zipfile.ZIP_DEFLATED),
    ('OEBPS/nav.xhtml', bad_nav, zipfile.ZIP_DEFLATED),
    ('OEBPS/c1.xhtml', chapter('第一章', 1), zipfile.ZIP_DEFLATED),
    ('OEBPS/c%FF.xhtml', chapter('第二章', 2).replace(
        '<h1>', '<h1 id="top"><img src="i%FF.png" alt=""/>'), zipfile.ZIP_DEFLATED),
    ('OEBPS/100%.xhtml', chapter('第三章', 1), zipfile.ZIP_DEFLATED),
    ('OEBPS/i%FF.png', png, zipfile.ZIP_STORED),
]

# horizontal_rtl.epub: book.epub's pages run right to left (the spine says
# rtl) but its text is horizontal, as no stylesheet makes it vertical.
# arabic_rtl.epub: the same, in Arabic, which its markup makes right to left.
horizontal_rtl_entries = entries[:2] + [
    ('OEBPS/content.opf', opf.replace('bridge-test-1', 'bridge-test-3'), zipfile.ZIP_DEFLATED),
    ('OEBPS/nav.xhtml', nav, zipfile.ZIP_DEFLATED),
    ('OEBPS/c1.xhtml', chapter('第一章', 6, style=''), zipfile.ZIP_DEFLATED),
    ('OEBPS/c2.xhtml', chapter('第二章', 2, style=''), zipfile.ZIP_DEFLATED),
]
arabic = 'هذه فقرة قصيرة باللغة العربية تتكرر حتى تملأ الصفحة. ' * 6 + 'النهاية.'
arabic_root = 'dir="rtl" xml:lang="ar" lang="ar"'
arabic_entries = entries[:2] + [
    ('OEBPS/content.opf', opf.replace('bridge-test-1', 'bridge-test-4')
     .replace('<dc:language>ja</dc:language>', '<dc:language>ar</dc:language>'), zipfile.ZIP_DEFLATED),
    ('OEBPS/nav.xhtml', nav, zipfile.ZIP_DEFLATED),
    ('OEBPS/c1.xhtml', chapter('الفصل الأول', 6, style='', root=arabic_root, text=arabic), zipfile.ZIP_DEFLATED),
    ('OEBPS/c2.xhtml', chapter('الفصل الثاني', 2, style='', root=arabic_root, text=arabic), zipfile.ZIP_DEFLATED),
]

# japanese_name.epub: book.epub with chapter one's file named in Japanese, as
# the manifest and the nav write it. Chapter two links to it as written and
# percent-encoded.
first = '第一章.xhtml'
japanese_name_entries = entries[:2] + [
    ('OEBPS/content.opf', opf.replace('bridge-test-1', 'bridge-test-5')
     .replace('href="c1.xhtml"', f'href="{first}"'), zipfile.ZIP_DEFLATED),
    ('OEBPS/nav.xhtml', nav.replace('href="c1.xhtml"', f'href="{first}"'), zipfile.ZIP_DEFLATED),
    (f'OEBPS/{first}', chapter('第一章', 6), zipfile.ZIP_DEFLATED),
    ('OEBPS/c2.xhtml', chapter('第二章', 2).replace(
        '<h1>', f'<p><a id="raw" href="{first}">一</a> <a id="encoded" href="{quote(first)}">一</a></p><h1>'),
     zipfile.ZIP_DEFLATED),
]

for file, files in [('book.epub', entries), ('bad_href.epub', bad_href_entries),
                    ('horizontal_rtl.epub', horizontal_rtl_entries), ('arabic_rtl.epub', arabic_entries),
                    ('japanese_name.epub', japanese_name_entries)]:
    out = here / file
    with zipfile.ZipFile(out, 'w') as z:
        for name, data, method in files:
            info = zipfile.ZipInfo(name, date_time=(2026, 1, 1, 0, 0, 0))
            info.compress_type = method
            z.writestr(info, data)
    print(out, out.stat().st_size)
