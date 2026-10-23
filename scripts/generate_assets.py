#!/usr/bin/env python3
"""Generate the original Personal Browser icon and logo from simple shapes."""
from pathlib import Path
from PIL import Image, ImageDraw

root = Path(__file__).resolve().parents[1]
assets = root / "Browser/Resources/Assets.xcassets"
svg = '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256">
<rect width="256" height="256" rx="56" fill="#F4FAF8"/>
<rect x="36" y="50" width="184" height="156" rx="30" fill="none" stroke="#123E42" stroke-width="12"/>
<path d="M36 90h184" stroke="#123E42" stroke-width="12"/>
<circle cx="128" cy="145" r="42" fill="none" stroke="#00A88F" stroke-width="10"/>
<path d="M86 145h84M128 103c-22 22-22 62 0 84M128 103c22 22 22 62 0 84" fill="none" stroke="#00A88F" stroke-width="7" stroke-linecap="round"/>
</svg>'''
(assets / "BrowserLogo.imageset/personal-browser-logo.svg").write_text(svg + "\n")
(assets / "BrowserLogo.imageset/Contents.json").write_text('''{
  "images": [{"filename": "personal-browser-logo.svg", "idiom": "universal"}],
  "info": {"author": "xcode", "version": 1},
  "properties": {"preserves-vector-representation": true}
}\n''')

size = 1024
scale = size / 256
im = Image.new("RGB", (size, size), "#F4FAF8")
d = ImageDraw.Draw(im)
box = lambda coords: tuple(round(v * scale) for v in coords)
d.rounded_rectangle(box((36, 50, 220, 206)), radius=round(30*scale), outline="#123E42", width=round(12*scale))
d.line(box((36, 90, 220, 90)), fill="#123E42", width=round(12*scale))
d.ellipse(box((86, 103, 170, 187)), outline="#00A88F", width=round(10*scale))
d.line(box((86, 145, 170, 145)), fill="#00A88F", width=round(7*scale))
d.arc(box((105, 103, 151, 187)), 80, 280, fill="#00A88F", width=round(7*scale))
d.arc(box((105, 103, 151, 187)), 260, 100, fill="#00A88F", width=round(7*scale))
im.save(assets / "AppIcon.appiconset/personal-browser-app-icon.png")
(assets / "AppIcon.appiconset/Contents.json").write_text('''{
  "images": [{"filename": "personal-browser-app-icon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
  "info": {"author": "xcode", "version": 1}
}\n''')
