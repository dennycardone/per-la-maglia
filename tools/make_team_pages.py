# Per la Maglia - genera le pagine di squadra (link da condividere con anteprima) e i dati per le immagini di anteprima.
# Uso: python3 tools/make_team_pages.py https://indirizzo-del-gioco/
import json, re, sys, os, unicodedata, html
SITE = (sys.argv[1] if len(sys.argv) > 1 else "https://perlamaglia.com/").rstrip("/") + "/"
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
src = open(os.path.join(root, "index.html"), encoding="utf-8").read()
teams = []
for name in ("TEAMS_A", "TEAMS_B", "TEAMS_C"):
    block = re.search(r"const " + name + r" = \[(.*?)\];", src, re.S).group(1)
    teams += re.findall(r'\["([^"]+)","(#[0-9a-f]{6})","(#[0-9a-f]{6})"\]', block)
art = dict(re.findall(r'"?([A-Z][A-Za-zü ]+)"?: "(l\'|la|lo)"', re.search(r"const ART = \{(.*?)\};", src, re.S).group(1)))
def slug(n): return re.sub(r"[^a-z0-9]+", "-", unicodedata.normalize("NFD", n).encode("ascii", "ignore").decode().lower()).strip("-")
def the(n, cap=True):
    a = art.get(n, "il"); s = (a + n) if a == "l'" else (a + " " + n)
    return s[0].upper() + s[1:] if cap else s
def per(n):
    a = art.get(n, "il"); return {"il": "il ", "la": "la ", "lo": "lo ", "l'": "l'"}[a] + n
out = []
for n, c1, c2 in teams:
    s = slug(n); d = os.path.join(root, s); os.makedirs(d, exist_ok=True)
    title = f"{the(n)} ti chiama · Per la Maglia"
    desc = f"Servono i tuoi gol: scegli {per(n)}, fai il cucchiaio al portiere e scala la classifica dei tifosi."
    e = html.escape
    open(os.path.join(d, "index.html"), "w", encoding="utf-8").write(f'''<!doctype html>
<html lang="it"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>{e(title)}</title><meta name="description" content="{e(desc)}">
<meta property="og:type" content="website"><meta property="og:site_name" content="Per la Maglia">
<meta property="og:title" content="{e(title)}"><meta property="og:description" content="{e(desc)}">
<meta property="og:image" content="{SITE}og/{s}.jpg"><meta property="og:image:width" content="1200"><meta property="og:image:height" content="630">
<meta property="og:url" content="{SITE}{s}/"><meta name="twitter:card" content="summary_large_image">
<meta name="theme-color" content="{c1}"><link rel="icon" href="../icon-192.png">
<script>location.replace("../?team=" + encodeURIComponent({json.dumps(n)}) + (location.search ? "&" + location.search.slice(1) : ""));</script>
</head><body style="margin:0;background:#070b12;color:#eef2ea;font:18px system-ui,sans-serif;display:grid;place-items:center;min-height:100vh">
<a style="color:#ffc24b" href="../?team={e(n)}">Gioca {e(per(n))} su Per la Maglia</a></body></html>
''')
    out.append({"name": n, "slug": s, "c1": c1, "c2": c2, "the": the(n)})
json.dump(out, open(os.path.join(root, "tools", "teams.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=0)
print(len(out), "pagine di squadra per", SITE)
