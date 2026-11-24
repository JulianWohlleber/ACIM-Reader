#!/usr/bin/env bash
# Build ACIM Reader for a physical iPhone, sign it with the team's Xcode-managed
# wildcard profile, and install it.
#
# Xcode refuses to consume an Xcode-managed profile under manual signing, and
# automatic signing needs an Apple ID configured in Xcode. So we build unsigned
# and sign the bundle ourselves afterwards.
#
#   ./Tools/build-install.sh [device-udid]
set -euo pipefail

TEAM="JYU2BQP99R"
BUNDLE_ID="com.julianwohlleber.acimreader"
DEVICE="${1:-}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DD="${DERIVED_DATA:-$ROOT/.build/dd-device}"

cd "$ROOT"

# --- 0. device ---------------------------------------------------------------
if [[ -z "$DEVICE" ]]; then
  DEVICE=$(xcrun devicectl list devices 2>/dev/null \
    | awk '/physical/ && (/available/ || /connected/) {for(i=1;i<=NF;i++) if($i ~ /^[0-9A-F]{8}-[0-9A-F]{16}$/) print $i}' \
    | head -1)
fi
if [[ -z "$DEVICE" ]]; then
  echo "No connected iPhone found. Plug it in, unlock it, and trust this Mac." >&2
  echo "Connected devices:" >&2
  xcrun devicectl list devices 2>/dev/null | grep -i physical >&2 || true
  exit 1
fi
echo "==> Device: $DEVICE"

# --- 1. signing material -----------------------------------------------------
CERT=$(security find-identity -v -p codesigning \
       | grep "Apple Development" | head -1 | awk '{print $2}')
[[ -n "$CERT" ]] || { echo "No 'Apple Development' certificate in the keychain." >&2; exit 1; }
echo "==> Certificate: $CERT"

PROFILE=""
for f in "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles/"*.mobileprovision; do
  [[ -f "$f" ]] || continue
  plist=$(security cms -D -i "$f" 2>/dev/null) || continue
  appid=$(printf '%s' "$plist" | plutil -extract Entitlements.application-identifier raw - 2>/dev/null) || continue
  [[ "$appid" == "$TEAM.*" ]] || continue
  # `-extract ... raw` does not list array elements one per line; xml1 does.
  printf '%s' "$plist" | plutil -extract ProvisionedDevices xml1 -o - - 2>/dev/null | grep -q "$DEVICE" || continue
  PROFILE="$f"; break
done
[[ -n "$PROFILE" ]] || {
  echo "No wildcard profile ($TEAM.*) covering device $DEVICE." >&2
  echo "Open Xcode once with this device attached so it refreshes the profile." >&2
  exit 1; }
echo "==> Profile: $(basename "$PROFILE")"

# --- 2. build (unsigned) -----------------------------------------------------
echo "==> Building..."
mkdir -p "$(dirname "$DD")"
xcodebuild -project ACIMAudio.xcodeproj -scheme ACIMAudio -configuration Debug \
  -destination 'generic/platform=iOS' -derivedDataPath "$DD" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  build > "$DD.log" 2>&1 || { tail -40 "$DD.log"; exit 1; }

APP=$(find "$DD/Build/Products/Debug-iphoneos" -maxdepth 1 -name "*.app" | head -1)
[[ -n "$APP" ]] || { echo "No .app produced." >&2; exit 1; }
echo "==> Built: $APP"

# --- 3. sign -----------------------------------------------------------------
cp "$PROFILE" "$APP/embedded.mobileprovision"
ENT="$DD/entitlements.plist"
cat > "$ENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>application-identifier</key>
	<string>$TEAM.$BUNDLE_ID</string>
	<key>com.apple.developer.team-identifier</key>
	<string>$TEAM</string>
	<key>get-task-allow</key>
	<true/>
	<key>keychain-access-groups</key>
	<array>
		<string>$TEAM.$BUNDLE_ID</string>
	</array>
</dict>
</plist>
PLIST

echo "==> Signing..."
# Nested code must be signed before the bundle that contains it, or installd
# rejects the app with "The executable contains an invalid signature".
# Frameworks get no entitlements of their own.
# Sign every piece of nested code wherever it sits, longest path first so a
# container is always signed after its contents.
#
# Not just Frameworks/: Xcode 16 splits a Debug build into a thin launcher plus
# ACIM.debug.dylib, and that dylib lands at the bundle ROOT. Left unsigned,
# dyld refuses the whole app at launch with "missing code signature" — the app
# installs fine and dies the moment you tap it.
while IFS= read -r nested; do
  echo "    ${nested#"$APP"/}"
  codesign --force --timestamp=none --sign "$CERT" "$nested"
done < <(find "$APP" -mindepth 1 \( -name '*.framework' -o -name '*.dylib' \) \
         | awk '{ print length "\t" $0 }' | sort -rn | cut -f2-)

codesign --force --timestamp=none --generate-entitlement-der \
  --sign "$CERT" --entitlements "$ENT" "$APP"
codesign --verify --verbose=2 "$APP"

# --- 4. install --------------------------------------------------------------
echo "==> Installing onto $DEVICE ..."
xcrun devicectl device install app --device "$DEVICE" "$APP"
echo "==> Done. Open 'ACIM' on the iPhone."
