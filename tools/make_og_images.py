# Per la Maglia - disegna le immagini di anteprima dei link (1200x630): una per squadra + quella generale.
# Uso: python3 tools/make_og_images.py   (serve Playwright con Chromium)
import json, os, re, subprocess, sys
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
src = open(os.path.join(root, "index.html"), encoding="utf-8").read()
kit = re.search(r"const KIT = \{.*?\n\};", src, re.S).group(0)
kit2 = re.search(r"Object\.assign\(KIT, \{.*?\n\}\);", src, re.S).group(0)
jer = re.search(r"function jerseySVG\(k, size = 22\)\{.*?\n\}", src, re.S).group(0)
teams = json.load(open(os.path.join(root, "tools", "teams.json"), encoding="utf-8"))
page = os.path.join(root, "tools", "og.html")
open(page, "w", encoding="utf-8").write("""<!doctype html><html><head><meta charset="utf-8"><style>
@font-face{font-family:BS;src:url(../fonts/bigshouldersdisplay.woff)}@font-face{font-family:BC;src:url(../fonts/barlowcondensed-Bold.woff);font-weight:700}
html,body{margin:0;background:#000}canvas{display:block}</style></head><body><canvas id="c" width="1200" height="630"></canvas><script>
let jid = 0;
""" + kit + "\n" + kit2 + "\n" + jer + """
const TEAMS = """ + json.dumps(teams, ensure_ascii=False) + """;
async function draw(t){
  const c = document.getElementById("c"), g = c.getContext("2d"), W = 1200, H = 630, c1 = t.c1, c2 = t.c2 === t.c1 ? "#ffffff" : t.c2;
  g.fillStyle = c1; g.fillRect(0, 0, W, H); g.globalAlpha = .18; g.fillStyle = c2;
  for (let x = -H; x < W; x += 120) { g.beginPath(); g.moveTo(x, 0); g.lineTo(x + 60, 0); g.lineTo(x + 60 + H * .5, H); g.lineTo(x + H * .5, H); g.fill(); }
  g.globalAlpha = 1; const sh = g.createLinearGradient(0, 0, W, 0); sh.addColorStop(0, "rgba(5,10,20,.88)"); sh.addColorStop(.62, "rgba(5,10,20,.55)"); sh.addColorStop(1, "rgba(5,10,20,.15)"); g.fillStyle = sh; g.fillRect(0, 0, W, H);
  const img = new Image(); img.src = "data:image/svg+xml;charset=utf-8," + encodeURIComponent(jerseySVG(KIT[t.name] || ["plain", t.c1, t.c2], 460).replace("<svg ", '<svg xmlns="http://www.w3.org/2000/svg" '));
  await new Promise(r => { img.onload = r; img.onerror = r; }); g.drawImage(img, 720, 90, 460, 460);
  const fit = (s, size, max, font) => { let z = size; g.font = font(z); while (g.measureText(s).width > max && z > 30) { z -= 2; g.font = font(z); } return z; };
  g.textAlign = "left"; g.fillStyle = "#ffc24b"; g.font = "700 44px BC"; g.fillText("PER LA MAGLIA", 70, 100);
  const head = (t.the + " ti chiama").toUpperCase(), z = fit(head, 104, 700, s => "900 " + s + "px BS");
  g.lineJoin = "round"; g.strokeStyle = "#0b1530"; g.lineWidth = z * .12; g.strokeText(head, 70, 225); g.fillStyle = "#ffffff"; g.fillText(head, 70, 225);
  g.font = "700 42px BC"; g.fillStyle = "#ffffff"; g.fillText("Servono i tuoi gol: scegli " + t.the.charAt(0).toLowerCase() + t.the.slice(1) + ",", 72, 305); g.fillText("fai il cucchiaio al portiere e scala la classifica.", 72, 358);
  g.fillStyle = "#ffc24b"; g.beginPath(); g.roundRect(70, 425, 400, 96, 48); g.fill(); g.fillStyle = "#1a1205"; g.font = "900 56px BS"; g.textAlign = "center"; g.fillText("GIOCA ORA", 270, 490);
}
window.draw = draw; window.TEAMS = TEAMS;
</script></body></html>""")
os.makedirs(os.path.join(root, "og"), exist_ok=True)
js = """
const { chromium } = require('playwright');
(async () => {
  const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium', args: ['--allow-file-access-from-files'] });
  const p = await b.newPage({ viewport: { width: 1200, height: 630 } }); const errs = []; p.on('pageerror', e => errs.push(e.message));
  await p.goto('file://""" + page + """'); await p.evaluate(() => Promise.all([document.fonts.load('900 50px BS'), document.fonts.load('700 50px BC')]));
  const teams = await p.evaluate(() => TEAMS.map(t => t.slug));
  for (let i = 0; i < teams.length; i++) { await p.evaluate(i => draw(TEAMS[i]), i); await p.screenshot({ path: '""" + os.path.join(root, "og") + """/' + teams[i] + '.jpg', type: 'jpeg', quality: 85 }); }
  console.log(teams.length, errs); await b.close();
})();"""
open("/tmp/og_shots.js", "w").write(js)
subprocess.run(["node", "/tmp/og_shots.js"], check=True, env=dict(os.environ, NODE_PATH=subprocess.check_output(["npm", "root", "-g"]).decode().strip()))
