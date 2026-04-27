#!/bin/bash
# Generate AppIcon.icns from SVG using sips + iconutil
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ICONSET_DIR="$SCRIPT_DIR/AppIcon.iconset"
SVG_FILE="$SCRIPT_DIR/AppIcon.svg"
ICNS_FILE="$SCRIPT_DIR/AppIcon.icns"

# Create the SVG
cat > "$SVG_FILE" << 'SVGEOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">
  <defs>
    <!-- macOS-style rounded rect clip -->
    <clipPath id="iconClip">
      <rect x="0" y="0" width="1024" height="1024" rx="228" ry="228"/>
    </clipPath>
    <!-- Background gradient -->
    <linearGradient id="bgGrad" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%" stop-color="#3B4D6B"/>
      <stop offset="100%" stop-color="#1E2A3E"/>
    </linearGradient>
    <!-- Funnel gradient -->
    <linearGradient id="funnelGrad" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%" stop-color="#D4956A"/>
      <stop offset="100%" stop-color="#C47840"/>
    </linearGradient>
    <!-- Glow -->
    <radialGradient id="glow" cx="0.5" cy="0.35" r="0.5">
      <stop offset="0%" stop-color="#5A7BA8" stop-opacity="0.3"/>
      <stop offset="100%" stop-color="#1E2A3E" stop-opacity="0"/>
    </radialGradient>
  </defs>

  <g clip-path="url(#iconClip)">
    <!-- Background -->
    <rect width="1024" height="1024" fill="url(#bgGrad)"/>
    <rect width="1024" height="1024" fill="url(#glow)"/>

    <!-- Subtle grid lines for "sieve" texture -->
    <g stroke="#4A6080" stroke-width="1" opacity="0.15">
      <line x1="200" y1="0" x2="200" y2="1024"/>
      <line x1="350" y1="0" x2="350" y2="1024"/>
      <line x1="500" y1="0" x2="500" y2="1024"/>
      <line x1="650" y1="0" x2="650" y2="1024"/>
      <line x1="824" y1="0" x2="824" y2="1024"/>
      <line x1="0" y1="200" x2="1024" y2="200"/>
      <line x1="0" y1="350" x2="1024" y2="350"/>
      <line x1="0" y1="500" x2="1024" y2="500"/>
      <line x1="0" y1="650" x2="1024" y2="650"/>
      <line x1="0" y1="824" x2="1024" y2="824"/>
    </g>

    <!-- Funnel / Sieve shape -->
    <path d="M 220 280 L 804 280 Q 820 280 820 296 L 820 340 L 580 580 L 580 740 L 620 800 Q 625 810 615 815 L 512 850 L 409 815 Q 399 810 404 800 L 444 740 L 444 580 L 204 340 L 204 296 Q 204 280 220 280 Z"
          fill="url(#funnelGrad)" opacity="0.9"/>

    <!-- Funnel rim highlight -->
    <rect x="204" y="275" width="616" height="12" rx="6" fill="#E8B88A" opacity="0.6"/>

    <!-- Sieve holes in funnel -->
    <g fill="#1E2A3E" opacity="0.4">
      <circle cx="350" cy="340" r="14"/>
      <circle cx="420" cy="340" r="14"/>
      <circle cx="490" cy="340" r="14"/>
      <circle cx="560" cy="340" r="14"/>
      <circle cx="680" cy="340" r="14"/>
      <circle cx="310" cy="390" r="12"/>
      <circle cx="380" cy="395" r="12"/>
      <circle cx="450" cy="400" r="12"/>
      <circle cx="520" cy="400" r="12"/>
      <circle cx="590" cy="395" r="12"/>
      <circle cx="660" cy="390" r="12"/>
      <circle cx="420" cy="450" r="10"/>
      <circle cx="490" cy="455" r="10"/>
      <circle cx="560" cy="450" r="10"/>
    </g>

    <!-- PR merge icon (git pull request symbol) above funnel -->
    <!-- Three dots flowing in -->
    <g opacity="0.85">
      <!-- Priority dot (amber) -->
      <circle cx="360" cy="180" r="28" fill="#E8A655"/>
      <circle cx="360" cy="180" r="12" fill="#1E2A3E" opacity="0.5"/>

      <!-- Low dot (slate blue) -->
      <circle cx="512" cy="155" r="28" fill="#7A9EC2"/>
      <circle cx="512" cy="155" r="12" fill="#1E2A3E" opacity="0.5"/>

      <!-- Noise dot (gray) -->
      <circle cx="664" cy="180" r="28" fill="#8A8A8E"/>
      <circle cx="664" cy="180" r="12" fill="#1E2A3E" opacity="0.5"/>

      <!-- Flow lines into funnel -->
      <path d="M 360 208 Q 360 244 400 260" stroke="#E8A655" stroke-width="4" fill="none" opacity="0.5"/>
      <path d="M 512 183 L 512 258" stroke="#7A9EC2" stroke-width="4" fill="none" opacity="0.5"/>
      <path d="M 664 208 Q 664 244 624 260" stroke="#8A8A8E" stroke-width="4" fill="none" opacity="0.5"/>
    </g>

    <!-- Output arrow below funnel -->
    <g opacity="0.8">
      <path d="M 512 850 L 512 920" stroke="#E8A655" stroke-width="8" stroke-linecap="round"/>
      <path d="M 490 900 L 512 930 L 534 900" stroke="#E8A655" stroke-width="8" stroke-linecap="round" stroke-linejoin="round" fill="none"/>
    </g>
  </g>
</svg>
SVGEOF

echo "Created SVG: $SVG_FILE"

# Create iconset directory
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

# Render PNG at 1024x1024 using rsvg-convert if available, otherwise try python/cairosvg
MASTER_PNG="$ICONSET_DIR/master.png"

if command -v rsvg-convert &>/dev/null; then
    rsvg-convert -w 1024 -h 1024 "$SVG_FILE" -o "$MASTER_PNG"
elif command -v python3 &>/dev/null && python3 -c "import cairosvg" 2>/dev/null; then
    python3 -c "
import cairosvg
cairosvg.svg2png(url='$SVG_FILE', write_to='$MASTER_PNG', output_width=1024, output_height=1024)
"
elif command -v /Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome &>/dev/null; then
    # Use qlmanage as fallback (built into macOS, handles SVG)
    # Actually use sips approach: convert SVG to PDF first, then to PNG
    echo "No SVG renderer found. Trying qlmanage..."
    qlmanage -t -s 1024 -o "$ICONSET_DIR" "$SVG_FILE" 2>/dev/null && mv "$ICONSET_DIR/AppIcon.svg.png" "$MASTER_PNG"
else
    echo "Error: Need rsvg-convert (brew install librsvg) or cairosvg (pip3 install cairosvg)"
    echo "Install with: brew install librsvg"
    exit 1
fi

if [ ! -f "$MASTER_PNG" ]; then
    echo "Failed to render PNG"
    exit 1
fi

echo "Rendered master PNG"

# Generate all required icon sizes
declare -a SIZES=(
    "icon_16x16:16"
    "icon_16x16@2x:32"
    "icon_32x32:32"
    "icon_32x32@2x:64"
    "icon_128x128:128"
    "icon_128x128@2x:256"
    "icon_256x256:256"
    "icon_256x256@2x:512"
    "icon_512x512:512"
    "icon_512x512@2x:1024"
)

for entry in "${SIZES[@]}"; do
    NAME="${entry%%:*}"
    SIZE="${entry##*:}"
    sips -z "$SIZE" "$SIZE" "$MASTER_PNG" --out "$ICONSET_DIR/${NAME}.png" >/dev/null 2>&1
    echo "  Generated ${NAME}.png (${SIZE}x${SIZE})"
done

# Clean up master
rm "$MASTER_PNG"

# Convert to icns
iconutil -c icns "$ICONSET_DIR" -o "$ICNS_FILE"
rm -rf "$ICONSET_DIR"

echo "Created: $ICNS_FILE"
