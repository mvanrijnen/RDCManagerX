"""Turns a manual (Docs/RDCManagerX-Manual.html or -Handleiding.html) into the page for the GitHub Pages site,
laid out like a CHM viewer: a fixed contents tree on the left (h2 sections with their h3 subsections, the current
one highlighted while scrolling), the text on the right, and a top bar with Home, the language switch and the PDF.
The manual in the app (CHM/HTML) is not changed; this only runs in .github/workflows/pages.yml.

Usage: python3 Tools/site-layout.py <manual.html> <out.html> <en|nl> <pdf file name>
"""
import html
import re
import sys

src, out, lang, pdf = sys.argv[1:5]
with open(src, encoding='utf-8') as handle:
    text = handle.read()

labels = {
    'en': {'contents': 'Contents', 'home': 'Home', 'menu': 'Contents'},
    'nl': {'contents': 'Inhoud', 'home': 'Home', 'menu': 'Inhoud'},
}[lang]

# The in-page table of contents is replaced by the side pane.
text = re.sub(r'<nav class="toc">.*?</nav>', '', text, count=1, flags=re.DOTALL)

# Headings: every h2 and h3 needs an id for the tree.
used = set(re.findall(r'id="([^"]+)"', text))
counter = [0]


def ensure_id(match):
    tag, attrs, inner = match.group(1), match.group(2), match.group(3)
    if 'id="' not in attrs:
        counter[0] += 1
        new_id = f's{counter[0]}'
        while new_id in used:
            counter[0] += 1
            new_id = f's{counter[0]}'
        used.add(new_id)
        attrs = f'{attrs} id="{new_id}"'
    return f'<{tag}{attrs}>{inner}</{tag}>'


text = re.sub(r'<(h[23])([^>]*)>(.*?)</\1>', ensure_id, text, flags=re.DOTALL)

items = []
for match in re.finditer(r'<(h[23])[^>]*id="([^"]+)"[^>]*>(.*?)</\1>', text, flags=re.DOTALL):
    level, hid, inner = match.group(1), match.group(2), match.group(3)
    title = html.unescape(re.sub(r'<[^>]+>', '', inner)).strip()
    items.append((level, hid, title))

tree = ['<ul class="tree">']
open_sub = False
for level, hid, title in items:
    if level == 'h2':
        if open_sub:
            tree.append('</ul></li>')
            open_sub = False
        tree.append(f'<li><a href="#{hid}">{html.escape(title)}</a>')
        # closed when the next h2 starts (or the subsection list ends)
        tree.append('<!--h2-->')
    else:
        if not open_sub:
            tree.append('<ul>')
            open_sub = True
        tree.append(f'<li><a href="#{hid}">{html.escape(title)}</a></li>')
tree_html = ''.join(tree)
# Close every h2 <li>: replace markers so that an h2 without subsections closes immediately.
parts = tree_html.split('<!--h2-->')
fixed = [parts[0]]
for part in parts[1:]:
    if part.startswith('<ul>'):
        fixed.append(part)
    else:
        fixed.append('</li>' + part)
tree_html = ''.join(fixed)
if open_sub:
    tree_html += '</ul></li>'
tree_html += '</ul>'

other = 'nl' if lang == 'en' else 'en'
lang_links = ('<strong>English</strong> &middot; <a href="../nl/">Nederlands</a>' if lang == 'en'
              else '<a href="../en/">English</a> &middot; <strong>Nederlands</strong>')
topbar = (f'<div class="topbar"><button class="menu" type="button" aria-label="{labels["menu"]}">&#9776;</button>'
          f'<a class="brand" href="../">RDCManagerX</a><span class="links"><a href="../">{labels["home"]}</a> &middot; '
          f'{lang_links} &middot; <a href="{pdf}">PDF</a></span></div>')
side = f'<nav class="side" aria-label="{labels["contents"]}"><div class="side-title">{labels["contents"]}</div>{tree_html}</nav>'

css = """
<style>
  .topbar { position: fixed; top: 0; left: 0; right: 0; height: 48px; display: flex; align-items: center; gap: 14px;
    padding: 0 16px; background: var(--panel); border-bottom: 1px solid var(--line); z-index: 10; }
  .topbar .brand { font-weight: 700; color: var(--text); text-decoration: none; }
  .topbar .links { margin-left: auto; color: var(--muted); font-size: 14px; }
  .topbar a { color: var(--accent); text-decoration: none; }
  .topbar .menu { display: none; background: none; border: 1px solid var(--line); border-radius: 6px; color: var(--text);
    font-size: 18px; padding: 2px 9px; cursor: pointer; }
  nav.side { position: fixed; top: 48px; bottom: 0; left: 0; width: 290px; overflow-y: auto; padding: 12px 8px 24px;
    background: var(--panel); border-right: 1px solid var(--line); font-size: 14px; }
  nav.side .side-title { font-weight: 600; padding: 4px 10px 8px; color: var(--muted); text-transform: uppercase;
    font-size: 12px; letter-spacing: 0.5px; }
  nav.side ul { list-style: none; margin: 0; padding: 0; }
  nav.side ul ul { padding-left: 14px; }
  nav.side a { display: block; padding: 4px 10px; border-radius: 6px; color: var(--text); text-decoration: none;
    line-height: 1.35; }
  nav.side a:hover { background: var(--line); }
  nav.side a.active { background: var(--accent); color: #fff; }
  body > .page { margin-left: 290px; max-width: none; padding: 72px 40px 64px; }
  body > .page > * { max-width: 880px; }
  h2, h3 { scroll-margin-top: 60px; }
  @media (max-width: 900px) {
    .topbar .menu { display: inline-block; }
    nav.side { transform: translateX(-100%); transition: transform .2s; z-index: 9; box-shadow: 2px 0 12px rgba(0,0,0,.2); }
    body.side-open nav.side { transform: none; }
    body > .page { margin-left: 0; padding: 64px 16px 48px; }
    .topbar .links { font-size: 13px; }
  }
</style>
"""

js = """
<script>
(function () {
  var links = Array.prototype.slice.call(document.querySelectorAll('nav.side a'));
  var byId = {};
  links.forEach(function (a) { byId[a.getAttribute('href').slice(1)] = a; });
  var heads = Array.prototype.slice.call(document.querySelectorAll('h2[id], h3[id]'));
  function update() {
    var current = null;
    heads.forEach(function (h) { if (h.getBoundingClientRect().top < 90) current = h; });
    links.forEach(function (a) { a.classList.remove('active'); });
    if (current && byId[current.id]) {
      byId[current.id].classList.add('active');
      var side = document.querySelector('nav.side');
      var r = byId[current.id].getBoundingClientRect();
      if (r.top < 60 || r.bottom > window.innerHeight) byId[current.id].scrollIntoView({ block: 'nearest' });
    }
  }
  window.addEventListener('scroll', update, { passive: true });
  update();
  document.querySelector('.topbar .menu').addEventListener('click', function () { document.body.classList.toggle('side-open'); });
  links.forEach(function (a) { a.addEventListener('click', function () { document.body.classList.remove('side-open'); }); });
})();
</script>
"""

text = text.replace('</head>', css + '</head>', 1)
text = text.replace('<div class="page">', topbar + side + '<div class="page">', 1)
text = text.replace('</body>', js + '</body>', 1)
with open(out, 'w', encoding='utf-8') as handle:
    handle.write(text)
print(f'{out}: {len(items)} entries in the contents tree')
