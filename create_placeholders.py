from PIL import Image
import os

# Create a 16x16 white image for the salt icon
salt_icon = Image.new('RGB', (16, 16), color = 'white')
salt_icon.save("/home/kls-sce/Age of Gold: Mansa Musa's Legacy/assets/ui/salt_icon.png")

# Create a 16x16 brown image for the manuscript icon
manuscript_icon = Image.new('RGB', (16, 16), color = 'saddlebrown')
manuscript_icon.save("/home/kls-sce/Age of Gold: Mansa Musa's Legacy/assets/ui/manuscript_icon.png")

# Create a 16x16 gold image for the gold icon
gold_icon = Image.new('RGB', (16, 16), color = 'gold')
gold_icon.save("/home/kls-sce/Age of Gold: Mansa Musa's Legacy/assets/ui/gold_icon.png")

# Create a 32x32 dark red image for the player sprite
os.makedirs("/home/kls-sce/Age of Gold: Mansa Musa's Legacy/assets/sprites", exist_ok=True)
player_sprite = Image.new('RGB', (32, 32), color = 'darkred')
player_sprite.save("/home/kls-sce/Age of Gold: Mansa Musa's Legacy/assets/sprites/player.png")
