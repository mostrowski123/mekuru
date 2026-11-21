# Writes book.epub, the fixture run.mjs loads: two vertical-rl Japanese
# chapters (the first two pages long at run.mjs's viewport, with one
# authored ruby), and a nav. Entries carry a fixed date, so a rerun
# writes the same bytes. Run it only to change the fixture; commit both.
import pathlib
import zipfile

out = pathlib.Path(__file__).with_name('book.epub')
para = ('吾輩は猫である。名前はまだ無い。どこで生れたかとんと見当がつかぬ。'
        '何でも薄暗いじめじめした所でニャーニャー泣いていた事だけは記憶している。') * 4


def chapter(title, n, ruby=False):
    body = ''.join(f'<p>{para}</p>' for _ in range(n))
    if ruby:
        body = '<p><ruby>漢字<rt>かんじ</rt></ruby>を読む。</p>' + body
    return f'''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="ja"><head><title>{title}</title>
<style>html{{writing-mode:vertical-rl;-webkit-writing-mode:vertical-rl;}}</style></head>
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
with zipfile.ZipFile(out, 'w') as z:
    for name, text, method in entries:
        info = zipfile.ZipInfo(name, date_time=(2026, 1, 1, 0, 0, 0))
        info.compress_type = method
        z.writestr(info, text)
print(out, out.stat().st_size)
