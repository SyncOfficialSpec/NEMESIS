# Pack the 48px icon PNGs into <=1000px spritesheets + emit a Lua index.
# Cell is 50px (48px icon + 1px margin all round) so bilinear sampling of one
# icon never bleeds into its neighbour. 20x20 cells per 1000x1000 sheet.
import os, math
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "png48")
OUT = os.path.join(HERE, "sheets")
os.makedirs(OUT, exist_ok=True)

CELL, ICON, COLS = 50, 48, 20
PER_SHEET = COLS * COLS  # 400

names = sorted(f[:-4] for f in os.listdir(SRC) if f.endswith(".png"))
sheets = math.ceil(len(names) / PER_SHEET)
index = {}

for s in range(sheets):
    chunk = names[s * PER_SHEET:(s + 1) * PER_SHEET]
    rows = math.ceil(len(chunk) / COLS)
    sheet = Image.new("RGBA", (COLS * CELL, rows * CELL), (0, 0, 0, 0))
    for i, name in enumerate(chunk):
        col, row = i % COLS, i // COLS
        icon = Image.open(os.path.join(SRC, name + ".png")).convert("RGBA")
        if icon.size != (ICON, ICON):
            icon = icon.resize((ICON, ICON), Image.LANCZOS)
        x, y = col * CELL + 1, row * CELL + 1
        sheet.paste(icon, (x, y))
        index[name] = (s + 1, x, y)
    sheet.save(os.path.join(OUT, f"icons_{s + 1}.png"), optimize=True)
    print(f"icons_{s + 1}.png {sheet.size} {len(chunk)} icons")

with open(os.path.join(OUT, "index.lua"), "w") as f:
    f.write("-- NEMESIS icon index: name -> {sheet, x, y} (48x48 cells)\n")
    f.write("return {\n")
    for name in names:
        s, x, y = index[name]
        f.write(f'\t["{name}"]={{{s},{x},{y}}},\n')
    f.write("}\n")
print("index.lua:", len(names), "entries,", sheets, "sheets")
