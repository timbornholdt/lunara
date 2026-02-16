#!/bin/bash
# Quick script to get a Plex authentication token via OAuth

echo "🔐 Plex Token Generator"
echo "======================="

# Step 1: Request a PIN
echo -e "\n📍 Requesting PIN from Plex..."
PIN_RESPONSE=$(curl -s -X POST "https://plex.tv/api/v2/pins" \
  -H "X-Plex-Client-Identifier: Lunara-CLI" \
  -H "X-Plex-Product: Lunara" \
  -H "accept: application/json")

PIN_ID=$(echo $PIN_RESPONSE | grep -o '"id":[0-9]*' | cut -d':' -f2)
PIN_CODE=$(echo $PIN_RESPONSE | grep -o '"code":"[^"]*"' | cut -d'"' -f4)

if [ -z "$PIN_CODE" ]; then
  echo "❌ Failed to get PIN"
  exit 1
fi

echo "✅ PIN Code: $PIN_CODE"
echo ""
echo "👉 Visit: https://plex.tv/link"
echo "👉 Enter code: $PIN_CODE"
echo ""
echo -n "⏳ Waiting for authorization"

# Step 2: Poll for authorization
for i in {1..60}; do
  sleep 2
  echo -n "."

  CHECK_RESPONSE=$(curl -s "https://plex.tv/api/v2/pins/$PIN_ID" \
    -H "X-Plex-Client-Identifier: Lunara-CLI" \
    -H "accept: application/json")

  TOKEN=$(echo $CHECK_RESPONSE | grep -o '"authToken":"[^"]*"' | cut -d'"' -f4)

  if [ ! -z "$TOKEN" ] && [ "$TOKEN" != "null" ]; then
    echo ""
    echo ""
    echo "✅ Success! Your Plex Token:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "$TOKEN"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "💾 Save this in Lunara/LocalConfig.plist:"
    echo "<key>PLEX_AUTH_TOKEN</key>"
    echo "<string>$TOKEN</string>"
    exit 0
  fi
done

echo ""
echo "⏱️  Timeout - authorization took too long"
echo "Try running the script again"
exit 1
