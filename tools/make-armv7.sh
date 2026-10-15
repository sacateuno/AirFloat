#!/bin/bash
# Builds AirFloat for armv7 / iOS 9 with clang and an iPhoneOS 9.3 SDK, without Xcode, and packages
# it as a .deb for a jailbroken device. Xcode 14 and later cannot build armv7 apps any more.
#
#   tools/make-armv7.sh            release build: the log is off until it is switched on in Settings
#   tools/make-armv7.sh dev        development build: log on by default, also logs the RTSP traffic
#
# Needs: clang (Xcode Command Line Tools), python3, ldid and dpkg-deb (brew install ldid dpkg), and
# the iPhoneOS9.3.sdk folder from https://github.com/theos/sdks.
#
# Paths (override them with environment variables):
#   SDK      the iPhoneOS9.3.sdk folder          default: <repo>/../sdks/iPhoneOS9.3.sdk
#   NIBS     compiled .nib files                 default: <repo>/../nibs
#   OUT      objects, package contents           default: <repo>/../out
#   DEB_DIR  where the .deb is written           default: <repo>/..
#
# The .nib files are compiled from the .xib files with ibtool, which only comes with Xcode:
#   xcrun ibtool --minimum-deployment-target 9.0 --target-device iphone --target-device ipad \
#       --compile NIBS/AppViewController.nib AirFloat/AppViewController.xib   (and the other two)
set -eu

MODE=${1:-release}
SRC="$(cd "$(dirname "$0")/.." && pwd)"
SDK="${SDK:-$SRC/../sdks/iPhoneOS9.3.sdk}"
NIBS="${NIBS:-$SRC/../nibs}"
OUT="${OUT:-$SRC/../out}"
DEB_DIR="${DEB_DIR:-$SRC/..}"
PKG="$OUT/deb-package"

case "$MODE" in
    release) EXTRA=""; SUFFIX="" ;;
    dev)     EXTRA="-DLOG_HTTP -DAIRFLOAT_LOG_DEFAULT_ON"; SUFFIX="+log" ;;
    *) echo "usage: $0 [release|dev]"; exit 1 ;;
esac

[ -d "$SDK" ] || { echo "SDK not found: $SDK"; exit 1; }
[ -d "$NIBS" ] || { echo "compiled nibs not found: $NIBS"; exit 1; }

# The trimmed SDK from theos/sdks is missing two things the linker needs. Both fixes are idempotent.
if [ ! -f "$SDK/usr/lib/system/liblaunch.tbd" ]; then
    cat > "$SDK/usr/lib/system/liblaunch.tbd" <<'EOF'
---
archs:                 [ armv7, armv7s, arm64, i386, x86_64 ]
platform:              ios
install-name:          /usr/lib/system/liblaunch.dylib
current-version:       1
compatibility-version: 1
exports:
  - archs:              [ armv7, armv7s, arm64, i386, x86_64 ]
    symbols:            [ ]
...
EOF
fi
if ! grep -q "_memcpy," "$SDK/usr/lib/system/libsystem_platform.tbd"; then
    python3 - "$SDK/usr/lib/system/libsystem_platform.tbd" <<'EOF'
import sys
path = sys.argv[1]
text = open(path).read()
extra = ("_memcpy, _memset, _memcmp, _memmove, _bzero, _memchr, _memccpy, _strlen, _strcmp, _strcpy, _strncpy, "
         "_strcat, _strncat, _strchr, _strrchr, _strstr, _strncmp, _strnlen, _strlcpy, _strlcat, "
         "_memset_pattern4, _memset_pattern8, _memset_pattern16, ")
open(path, "w").write(text.replace("symbols:            [ ", "symbols:            [ " + extra, 1))
EOF
fi

VERSION=$(plutil -extract CFBundleShortVersionString raw -o - "$SRC/AirFloat/AirFloat-Info.plist")
DEB="$DEB_DIR/com.tren.airfloat_${VERSION}${SUFFIX}_iphoneos-arm.deb"

COMMON="-arch armv7 -miphoneos-version-min=9.0 -isysroot $SDK -fobjc-arc -fno-objc-msgsend-selector-stubs -include stddef.h -include stdint.h -include stdbool.h -w -DUSE_BSD_SOCKETS -DALLOW_LOCALHOST $EXTRA -I$SRC/libairfloat -I$SRC/libairfloat/libairfloat -I$SRC/libairfloat/openssl"

rm -rf "$OUT"
mkdir -p "$OUT/obj" "$OUT/AirFloat.app"

echo "== compiling ($MODE, version $VERSION$SUFFIX)"
for f in "$SRC"/libairfloat/libairfloat/*.c "$SRC"/libairfloat/libairfloat/*.m; do
    b=$(basename "$f")
    case "$b" in crypt_openssl.c|decoder_alac_other.c) continue ;; esac
    clang $COMMON -std=gnu99 -c "$f" -o "$OUT/obj/$b.o"
done
for f in "$SRC"/AirFloat/*.m; do
    clang $COMMON -include "$SRC/AirFloat/AirFloat-Prefix.pch" -c "$f" -o "$OUT/obj/$(basename "$f").o"
done

echo "== linking"
clang -arch armv7 -miphoneos-version-min=9.0 -isysroot "$SDK" -ObjC "$OUT"/obj/*.o "$SRC/libairfloat/libcrypto.a" \
    -framework Foundation -framework UIKit -framework CoreGraphics -framework QuartzCore \
    -framework AVFoundation -framework AudioToolbox -framework CoreAudio -framework CFNetwork \
    -framework MediaPlayer -framework SystemConfiguration -framework CoreImage -framework OpenGLES \
    -framework Security -o "$OUT/AirFloat.app/AirFloat" 2>&1 | grep -v "warning: building for iOS" || true
file "$OUT/AirFloat.app/AirFloat" | grep -q arm_v7

echo "== packaging"
APP="$PKG/Applications/AirFloat.app"
mkdir -p "$PKG/DEBIAN" "$APP"

cat > "$PKG/DEBIAN/control" <<EOF
Package: com.tren.airfloat
Name: AirFloat
Version: ${VERSION}${SUFFIX}
Architecture: iphoneos-arm
Description: AirPlay receiver for iOS. Fixes crashes and lost packet recovery on 32-bit devices.
Maintainer: sacateuno
Author: Kristian Trenskow, patched by sacateuno
Section: Networking
Depends: firmware (>= 9.0)
EOF
printf '#!/bin/sh\nexit 0\n' > "$PKG/DEBIAN/postinst"
chmod 755 "$PKG/DEBIAN/postinst"

cp "$OUT/AirFloat.app/AirFloat" "$APP/AirFloat"
sed -e 's/\${PRODUCT_NAME}/AirFloat/g' -e 's/\${EXECUTABLE_NAME}/AirFloat/g' \
    -e 's/\$(PRODUCT_BUNDLE_IDENTIFIER)/com.tren.AirFloat/g' "$SRC/AirFloat/AirFloat-Info.plist" > "$APP/Info.plist"
plutil -lint "$APP/Info.plist" > /dev/null

cp "$SRC"/AirFloat/*.png "$SRC"/AirFloat/*.jpg "$SRC/AirFloat/Images.plist" "$SRC/AirFloat/Images~ipad.plist" "$SRC/AirFloat/Support.html" "$APP/"
cp "$SRC"/Icon*.png "$SRC"/Default*.png "$APP/"
cp -R "$NIBS"/*.nib "$APP/"
printf 'APPL????' > "$APP/PkgInfo"

ldid -S "$APP/AirFloat"
chmod 755 "$APP/AirFloat"

rm -f "$DEB_DIR"/com.tren.airfloat_*_iphoneos-arm.deb
dpkg-deb --root-owner-group -Zgzip -b "$PKG" "$DEB" > /dev/null
echo "== done: $DEB"
