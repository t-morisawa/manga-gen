#!/usr/bin/env python3
"""
Add speech bubbles to manga images.

Usage:
    python3 add_speech_bubbles.py <image_path> <bubbles_json>

Example bubbles_json:
    '[{"text": "やばい！", "speaker_id": "hana", "position_hint": "upper_right"}]'
"""

import sys
import json
import os
from PIL import Image, ImageDraw, ImageFont


def find_japanese_font():
    """Find a suitable Japanese font on the system."""
    candidates = [
        "/System/Library/Fonts/Hiragino Sans GB.ttc",  # macOS
        "/System/Library/Fonts/ヒラギノ角ゴシック W3.ttc",  # macOS JP
        "/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc",  # Linux
        "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
        "/usr/share/fonts/noto-cjk/NotoSansCJK-Regular.ttc",
        "/Windows/Fonts/msgothic.ttc",  # Windows
        "/Windows/Fonts/YuGothR.ttc",
    ]
    for path in candidates:
        if os.path.exists(path):
            return path
    return None


def get_font(size):
    """Get a font with Japanese support."""
    font_path = find_japanese_font()
    if font_path:
        try:
            return ImageFont.truetype(font_path, size)
        except Exception:
            pass
    return ImageFont.load_default()


def calculate_position(hint, img_width, img_height, bubble_w, bubble_h):
    """Calculate bubble position based on hint."""
    positions = {
        'upper_left': (int(img_width * 0.05), int(img_height * 0.05)),
        'upper_right': (int(img_width * 0.55), int(img_height * 0.05)),
        'lower_left': (int(img_width * 0.05), int(img_height * 0.60)),
        'lower_right': (int(img_width * 0.55), int(img_height * 0.60)),
        'near_speaker': (int(img_width * 0.55), int(img_height * 0.10)),
    }
    return positions.get(hint, positions['near_speaker'])


def draw_speech_bubble(draw, x, y, w, h, text, font):
    """Draw a speech bubble (ellipse with tail)."""
    padding = 15
    # Calculate text size
    bbox = draw.textbbox((0, 0), text, font=font)
    text_w = bbox[2] - bbox[0]
    text_h = bbox[3] - bbox[1]

    # Bubble size based on text
    bubble_w = max(w, text_w + padding * 2)
    bubble_h = max(h, text_h + padding * 2)

    # Ensure bubble stays within image bounds
    img_w, img_h = draw.im.size
    x = min(x, img_w - bubble_w - 10)
    y = min(y, img_h - bubble_h - 10)

    # Draw bubble shadow (offset)
    shadow_offset = 3
    draw.ellipse(
        [x + shadow_offset, y + shadow_offset,
         x + bubble_w + shadow_offset, y + bubble_h + shadow_offset],
        fill=(200, 200, 200, 180)
    )

    # Draw bubble body (white with black border)
    draw.ellipse(
        [x, y, x + bubble_w, y + bubble_h],
        fill=(255, 255, 255, 255),
        outline=(0, 0, 0, 255),
        width=2
    )

    # Draw tail (small triangle pointing down-left)
    tail_x = x + bubble_w // 4
    tail_y = y + bubble_h
    draw.polygon(
        [(tail_x, tail_y), (tail_x - 8, tail_y + 12), (tail_x + 8, tail_y + 12)],
        fill=(255, 255, 255, 255),
        outline=(0, 0, 0, 255)
    )

    # Draw text centered
    text_x = x + (bubble_w - text_w) // 2
    text_y = y + (bubble_h - text_h) // 2
    draw.text((text_x, text_y), text, fill=(0, 0, 0, 255), font=font)

    return bubble_w, bubble_h


def add_speech_bubbles(image_path, bubbles_json):
    """Add speech bubbles to an image."""
    # Parse bubbles
    bubbles = json.loads(bubbles_json)
    if not bubbles:
        print("No bubbles to add.")
        return

    # Open image
    img = Image.open(image_path).convert("RGBA")
    overlay = Image.new("RGBA", img.size, (255, 255, 255, 0))
    draw = ImageDraw.Draw(overlay)

    # Font size based on image width
    font_size = max(16, img.width // 40)
    font = get_font(font_size)

    # Draw each bubble
    for bubble in bubbles:
        text = bubble.get("text", "")
        hint = bubble.get("position_hint", "near_speaker")
        speaker = bubble.get("speaker_id", "")

        if not text:
            continue

        # Calculate position
        x, y = calculate_position(hint, img.width, img.height, 100, 60)

        # Draw bubble
        draw_speech_bubble(draw, x, y, 100, 60, text, font)

        print(f"Added bubble for {speaker}: '{text[:20]}...' at {hint} ({x}, {y})")

    # Composite overlay onto original
    result = Image.alpha_composite(img, overlay)

    # Save (convert back to RGB if needed)
    if result.mode == "RGBA":
        # Create white background
        background = Image.new("RGB", result.size, (255, 255, 255))
        background.paste(result, mask=result.split()[3])
        result = background

    result.save(image_path, "PNG")
    print(f"Saved to {image_path}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python3 add_speech_bubbles.py <image_path> <bubbles_json>")
        sys.exit(1)

    image_path = sys.argv[1]
    bubbles_json = sys.argv[2]

    if not os.path.exists(image_path):
        print(f"Error: Image not found: {image_path}")
        sys.exit(1)

    add_speech_bubbles(image_path, bubbles_json)
