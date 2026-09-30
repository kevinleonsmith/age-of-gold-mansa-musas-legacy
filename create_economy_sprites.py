#!/usr/bin/env python3
"""Generate economy sprites for Age of Gold (Pillow): a camel caravan with
trade bundles, a trade post (tents + stall) and a gold ingot icon.
Output: Age of Gold Game/assets/economy/. Deterministic."""
import os

from PIL import Image, ImageDraw

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Age of Gold Game")
OUT_DIR = os.path.join(ROOT, "assets", "economy")

OUT = (30, 20, 12, 255)  # dark outline
CAMEL = (196, 150, 90, 255)
CAMEL_DARK = (150, 105, 60, 255)
GOLD = (255, 205, 30, 255)
GOLD_LIGHT = (255, 235, 120, 255)
GOLD_DARK = (190, 130, 20, 255)


def draw_camel(d, x, y):
	"""Side-view camel facing right, (x, y) = top-left of a 24x22 box."""
	# legs
	for lx in (x + 5, x + 8, x + 15, x + 18):
		d.line([(lx, y + 14), (lx, y + 21)], fill=CAMEL_DARK, width=2)
	# body + hump
	d.ellipse([x + 3, y + 7, x + 21, y + 16], fill=CAMEL, outline=OUT)
	d.ellipse([x + 8, y + 3, x + 16, y + 11], fill=CAMEL, outline=OUT)
	d.rectangle([x + 9, y + 8, x + 15, y + 11], fill=CAMEL)
	# neck + head
	d.polygon([(x + 19, y + 10), (x + 22, y + 4), (x + 24, y + 5), (x + 22, y + 12)], fill=CAMEL, outline=OUT)
	d.ellipse([x + 21, y + 1, x + 27, y + 6], fill=CAMEL, outline=OUT)
	d.point([(x + 25, y + 3)], fill=OUT)
	# tail
	d.line([(x + 3, y + 10), (x + 1, y + 14)], fill=CAMEL_DARK)


def draw_caravan():
	im = Image.new("RGBA", (48, 32), (0, 0, 0, 0))
	d = ImageDraw.Draw(im)
	d.ellipse([2, 27, 46, 31], fill=(0, 0, 0, 70))
	# rear camel (smaller offset) then lead camel
	draw_camel(d, 0, 8)
	draw_camel(d, 15, 8)
	# rope between camels
	d.line([(22, 14), (20, 17)], fill=(90, 60, 30, 255))
	# bundles slung over each hump: striped sacks, a salt slab, a gold chest
	for bx, col in ((0, (170, 40, 40, 255)), (15, (40, 90, 160, 255))):
		d.rectangle([bx + 6, 12, bx + 11, 19], fill=col, outline=OUT)
		d.line([(bx + 6, 15), (bx + 11, 15)], fill=GOLD)
	d.rectangle([12, 13, 16, 18], fill=(240, 240, 235, 255), outline=OUT)  # salt slab
	d.rectangle([27, 13, 31, 18], fill=GOLD, outline=OUT)  # gold chest
	d.line([(8, 11), (14, 11)], fill=(90, 60, 30, 255))  # straps over humps
	d.line([(23, 11), (29, 11)], fill=(90, 60, 30, 255))
	# tiny driver walking in front
	d.ellipse([42, 12, 46, 16], fill=(110, 70, 40, 255), outline=OUT)
	d.polygon([(44, 16), (47, 27), (41, 27)], fill=(235, 230, 215, 255), outline=OUT)
	return im


def draw_trade_post():
	im = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
	d = ImageDraw.Draw(im)
	d.ellipse([2, 52, 62, 62], fill=(0, 0, 0, 60))
	# back tent (indigo, Tuareg style)
	d.polygon([(6, 50), (20, 22), (34, 50)], fill=(60, 70, 140, 255), outline=OUT)
	d.polygon([(17, 50), (20, 38), (23, 50)], fill=(25, 25, 50, 255))
	d.line([(20, 22), (20, 16)], fill=(90, 60, 30, 255))
	d.polygon([(20, 16), (26, 18), (20, 20)], fill=(200, 40, 40, 255))  # pennant
	# front tent (striped cream/red)
	d.polygon([(28, 56), (44, 26), (60, 56)], fill=(230, 215, 180, 255), outline=OUT)
	for i in range(3):
		t = 32 + i * 9
		d.line([(44, 26), (t, 56)], fill=(180, 60, 40, 255))
	d.polygon([(40, 56), (44, 44), (48, 56)], fill=(40, 25, 15, 255))
	# market stall with awning and goods
	d.rectangle([4, 46, 26, 56], fill=(140, 95, 50, 255), outline=OUT)
	d.polygon([(2, 44), (28, 44), (26, 40), (4, 40)], fill=(220, 170, 40, 255), outline=OUT)
	d.rectangle([7, 43, 11, 46], fill=(245, 245, 240, 255), outline=OUT)  # salt slab
	d.ellipse([14, 42, 18, 46], fill=GOLD, outline=OUT)  # gold pile
	d.ellipse([19, 42, 23, 46], fill=(120, 170, 60, 255), outline=OUT)  # kola nuts
	return im


def draw_ingot():
	im = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
	d = ImageDraw.Draw(im)
	# trapezoid bar in slight perspective
	d.polygon([(3, 24), (29, 24), (25, 13), (7, 13)], fill=GOLD, outline=OUT)
	d.polygon([(7, 13), (25, 13), (22, 9), (10, 9)], fill=GOLD_LIGHT, outline=OUT)
	d.line([(4, 23), (28, 23)], fill=GOLD_DARK)
	d.line([(9, 16), (14, 16)], fill=(255, 250, 210, 255))
	d.point([(24, 11), (25, 12)], fill=(255, 255, 255, 255))
	return im


def main():
	os.makedirs(OUT_DIR, exist_ok=True)
	for name, fn in (("caravan", draw_caravan), ("trade_post", draw_trade_post), ("ingot_icon", draw_ingot)):
		path = os.path.join(OUT_DIR, name + ".png")
		fn().save(path)
		print("wrote", path)


if __name__ == "__main__":
	main()
