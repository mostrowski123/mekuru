"""Builds assets/fonts/NotoSansJP-{Regular,Bold}.otf.

Input: NotoSansJP-Regular.otf and NotoSansJP-Bold.otf from
https://github.com/notofonts/noto-cjk/tree/main/Sans/SubsetOTF/JP in the
current directory. Keeps kana, CJK punctuation, full-width forms and every
kanji Shift_JIS (cp932) can encode; drops Latin so the system font still
draws it. Needs fontTools (pip install fonttools).
"""

from fontTools import subset
from fontTools.ttLib import TTFont


def wanted(cp):
    if 0x3000 <= cp <= 0x30FF or 0x31F0 <= cp <= 0x31FF or 0xFF00 <= cp <= 0xFFEF:
        return True
    if 0x3400 <= cp <= 0x9FFF or 0xF900 <= cp <= 0xFAFF:
        try:
            chr(cp).encode('cp932')
            return True
        except UnicodeEncodeError:
            return False
    return False


for weight in ('Regular', 'Bold'):
    font = TTFont(f'NotoSansJP-{weight}.otf')
    options = subset.Options()
    options.layout_features = ['*']
    options.name_IDs = ['*']  # keeps the OFL notice in the font itself
    options.notdef_outline = True
    subsetter = subset.Subsetter(options)
    subsetter.populate(unicodes=[cp for cp in font.getBestCmap() if wanted(cp)])
    subsetter.subset(font)
    font.save(f'assets/fonts/NotoSansJP-{weight}.otf')
