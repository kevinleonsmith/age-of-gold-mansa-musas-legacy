#!/usr/bin/env python3
"""Generate campaign sprites for Age of Gold (Pillow): the large Hajj caravan
(camel train with a canopied litter and gold chests) and city skyline markers
for Niani, Walata, Cairo and Mecca.
Output: assets/missions/. Deterministic."""
import os

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.join(ROOT, "assets", "missions")

OUT = (30, 20, 12, 255)  # dark outline
CAMEL = (196, 150, 90, 255)
CAMEL_DARK = (150, 105, 60, 255)
GOLD = (255, 205, 30, 255)
GOLD_LIGHT = (255, 235, 120, 255)
GOLD_DARK = (190, 130, 20, 255)
MUD = (176, 112, 60, 255)
MUD_DARK = (130, 78, 40, 255)
MUD_LIGHT = (205, 145, 85, 255)
STONE = (222, 208, 180, 255)
STONE_DARK = (170, 150, 120, 255)
WHITE = (245, 242, 230, 255)
GREEN = (40, 130, 70, 255)


def draw_camel(d, x, y):
	"""Side-view camel facing right, (x, y) = top-left of a 24x22 box."""
	for lx in (x + 5, x + 8, x + 15, x + 18):
		d.line([(lx, y + 14), (lx, y + 21)], fill=CAMEL_DARK, width=2)
	d.ellipse([x + 3, y + 7, x + 21, y + 16], fill=CAMEL, outline=OUT)
	d.ellipse([x + 8, y + 3, x + 16, y + 11], fill=CAMEL, outline=OUT)
	d.rectangle([x + 9, y + 8, x + 15, y + 11], fill=CAMEL)
	d.polygon([(x + 19, y + 10), (x + 22, y + 4), (x + 24, y + 5), (x + 22, y + 12)], fill=CAMEL, outline=OUT)
	d.ellipse([x + 21, y + 1, x + 27, y + 6], fill=CAMEL, outline=OUT)
	d.point([(x + 25, y + 3)], fill=OUT)
	d.line([(x + 3, y + 10), (x + 1, y + 14)], fill=CAMEL_DARK)


def draw_hajj_caravan():
	"""96x56: three camels roped nose-to-tail, the middle one carrying a red
	and gold canopied litter; gold chests on the others; banner bearer ahead."""
	im = Image.new("RGBA", (96, 56), (0, 0, 0, 0))
	d = ImageDraw.Draw(im)
	d.ellipse([2, 49, 94, 55], fill=(0, 0, 0, 70))
	ys = 30
	camels = (0, 26, 52)
	for cx in camels:
		draw_camel(d, cx, ys)
	for a, b in ((22, 26), (48, 52)):
		d.line([(a + 1, ys + 5), (b + 5, ys + 10)], fill=(90, 60, 30, 255))
	# gold chests on the outer camels
	for cx in (0, 52):
		d.rectangle([cx + 7, ys + 1, cx + 16, ys + 8], fill=GOLD, outline=OUT)
		d.line([(cx + 7, ys + 4), (cx + 16, ys + 4)], fill=GOLD_DARK)
		d.point([(cx + 11, ys + 5)], fill=OUT)
		d.point([(cx + 9, ys + 2), (cx + 14, ys + 2)], fill=GOLD_LIGHT)
	# canopied litter on the middle camel
	lx = 26
	d.rectangle([lx + 6, ys - 4, lx + 18, ys + 6], fill=(150, 25, 30, 255), outline=OUT)
	d.line([(lx + 6, ys + 2), (lx + 18, ys + 2)], fill=GOLD)
	d.line([(lx + 7, ys - 14), (lx + 7, ys - 4)], fill=GOLD_DARK)
	d.line([(lx + 17, ys - 14), (lx + 17, ys - 4)], fill=GOLD_DARK)
	d.polygon([(lx + 3, ys - 13), (lx + 12, ys - 22), (lx + 21, ys - 13)], fill=GOLD, outline=OUT)
	d.rectangle([lx + 3, ys - 14, lx + 21, ys - 11], fill=(200, 35, 40, 255), outline=OUT)
	for fx in range(lx + 4, lx + 21, 3):
		d.point([(fx, ys - 10)], fill=GOLD)
	d.ellipse([lx + 10, ys - 26, lx + 14, ys - 22], fill=GOLD_LIGHT, outline=OUT)
	# the Mansa inside the litter (tiny gold-crowned head)
	d.ellipse([lx + 9, ys - 9, lx + 15, ys - 4], fill=(110, 70, 40, 255), outline=OUT)
	d.rectangle([lx + 9, ys - 10, lx + 15, ys - 8], fill=GOLD)
	# banner bearer walking in front with a green banner
	bx = 84
	d.line([(bx + 6, ys - 16), (bx + 6, ys + 20)], fill=(90, 60, 30, 255))
	d.polygon([(bx + 6, ys - 16), (bx + 11, ys - 13), (bx + 6, ys - 9)], fill=GREEN, outline=OUT)
	d.ellipse([bx, ys + 2, bx + 5, ys + 7], fill=(110, 70, 40, 255), outline=OUT)
	d.polygon([(bx + 2, ys + 7), (bx + 6, ys + 20), (bx - 2, ys + 20)], fill=WHITE, outline=OUT)
	return im


def new_city():
	im = Image.new("RGBA", (72, 56), (0, 0, 0, 0))
	d = ImageDraw.Draw(im)
	d.ellipse([2, 49, 70, 55], fill=(0, 0, 0, 60))
	return im, d


def mud_tower(d, x, y0, w, y1, spikes=True):
	"""Sudano-Sahelian tapering tower with toron beams."""
	d.polygon([(x, y1), (x + 2, y0), (x + w - 2, y0), (x + w, y1)], fill=MUD, outline=OUT)
	d.line([(x + 2, y0 + 1), (x + 2, y1 - 1)], fill=MUD_LIGHT)
	if spikes:
		for yy in range(y0 + 4, y1 - 2, 6):
			d.point([(x - 1, yy), (x + w + 1, yy)], fill=MUD_DARK)
	d.polygon([(x + 1, y0), (x + w // 2, y0 - 5), (x + w - 1, y0)], fill=MUD_DARK, outline=OUT)
	d.ellipse([x + w // 2 - 1, y0 - 8, x + w // 2 + 1, y0 - 6], fill=(240, 235, 225, 255))


def draw_niani():
	im, d = new_city()
	# round huts with conical thatch and the royal palace tower
	for hx in (4, 46):
		d.rectangle([hx, 36, hx + 18, 50], fill=MUD, outline=OUT)
		d.polygon([(hx - 3, 37), (hx + 9, 24), (hx + 21, 37)], fill=(190, 160, 80, 255), outline=OUT)
		d.rectangle([hx + 7, 42, hx + 11, 50], fill=MUD_DARK)
	mud_tower(d, 26, 16, 18, 50)
	d.rectangle([32, 40, 38, 50], fill=(70, 40, 20, 255))
	d.line([(35, 2), (35, 10)], fill=(90, 60, 30, 255))
	d.polygon([(35, 2), (42, 4), (35, 6)], fill=GOLD, outline=OUT)
	return im


def draw_walata():
	im, d = new_city()
	# flat-roofed ochre houses with red-painted doorframes (Walata style)
	d.rectangle([2, 28, 30, 50], fill=MUD_LIGHT, outline=OUT)
	d.rectangle([28, 22, 52, 50], fill=MUD, outline=OUT)
	d.rectangle([50, 32, 70, 50], fill=MUD_LIGHT, outline=OUT)
	for x0, y0 in ((10, 40), (36, 38), (56, 42)):
		d.rectangle([x0, y0, x0 + 6, 50], fill=(70, 40, 20, 255))
		d.rectangle([x0 - 2, y0 - 2, x0 + 8, y0], fill=(170, 35, 30, 255))
	for x in range(4, 30, 5):
		d.point([(x, 28)], fill=WHITE)
	for x in range(30, 52, 5):
		d.point([(x, 22)], fill=WHITE)
	# small minaret
	mud_tower(d, 40, 8, 10, 22, spikes=False)
	# salt slabs stacked outside
	d.rectangle([60, 46, 70, 50], fill=(240, 240, 235, 255), outline=OUT)
	return im


def draw_cairo():
	im, d = new_city()
	# stone city: large dome and two slender pencil minarets
	d.rectangle([4, 34, 68, 50], fill=STONE, outline=OUT)
	d.pieslice([18, 14, 52, 50], 180, 360, fill=STONE, outline=OUT)
	d.line([(22, 26), (48, 26)], fill=STONE_DARK)
	d.line([(35, 6), (35, 14)], fill=GOLD_DARK)
	d.ellipse([33, 3, 37, 7], fill=GOLD, outline=OUT)
	for mx in (8, 58):
		d.rectangle([mx, 10, mx + 6, 50], fill=STONE, outline=OUT)
		d.rectangle([mx - 1, 20, mx + 7, 22], fill=STONE_DARK, outline=OUT)
		d.polygon([(mx, 10), (mx + 3, 2), (mx + 6, 10)], fill=STONE_DARK, outline=OUT)
	for x0 in (18, 30, 42):
		d.pieslice([x0, 38, x0 + 8, 50], 180, 360, fill=(70, 55, 40, 255))
		d.rectangle([x0, 44, x0 + 8, 50], fill=(70, 55, 40, 255))
	# gold coins spilling (Cairo's gold glut)
	for gx, gy in ((6, 47), (12, 48), (62, 47)):
		d.ellipse([gx, gy, gx + 3, gy + 3], fill=GOLD, outline=GOLD_DARK)
	return im


def draw_mecca():
	im, d = new_city()
	# the Kaaba (black cube with gold band) inside a white colonnade
	d.rectangle([4, 38, 68, 50], fill=WHITE, outline=OUT)
	for x in range(8, 66, 6):
		d.pieslice([x, 40, x + 5, 48], 180, 360, fill=STONE_DARK)
	d.rectangle([24, 18, 48, 44], fill=(20, 18, 20, 255), outline=OUT)
	d.rectangle([24, 23, 48, 26], fill=GOLD)
	d.line([(26, 24), (46, 24)], fill=GOLD_LIGHT)
	d.rectangle([40, 32, 44, 44], fill=GOLD_DARK)
	for mx in (6, 62):
		d.rectangle([mx, 12, mx + 4, 38], fill=WHITE, outline=OUT)
		d.polygon([(mx, 12), (mx + 2, 5), (mx + 4, 12)], fill=GOLD, outline=OUT)
	return im


def main():
	os.makedirs(OUT_DIR, exist_ok=True)
	sprites = {
		"hajj_caravan.png": draw_hajj_caravan(),
		"city_niani.png": draw_niani(),
		"city_walata.png": draw_walata(),
		"city_cairo.png": draw_cairo(),
		"city_mecca.png": draw_mecca(),
	}
	for name, im in sprites.items():
		path = os.path.join(OUT_DIR, name)
		im.save(path)
		print("wrote", path)


if __name__ == "__main__":
	main()
