#!/bin/zsh
# MediaPicker.app을 빌드해 build/ 에 만든다. 인자로 --install 을 주면 /Applications 에 복사하고 실행한다.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP=build/MediaPicker.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/MediaPicker "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
mkdir -p "$APP/Contents/Resources"
cp -R Extension "$APP/Contents/Resources/"
cp -R Resources/*.lproj "$APP/Contents/Resources/"

# 사파리 웹 확장(.appex): 같은 확장 파일을 앱 안의 PlugIns에 넣는다.
APPEX="$APP/Contents/PlugIns/MediaPickerSafari.appex"
mkdir -p "$APPEX/Contents/MacOS" "$APPEX/Contents/Resources"
cp Safari/Info.plist "$APPEX/Contents/"
cp -R Extension/ "$APPEX/Contents/Resources/"
swiftc -O -parse-as-library -application-extension -module-name MediaPickerSafari \
    -target "$(uname -m)-apple-macos14.0" \
    -Xlinker -e -Xlinker _NSExtensionMain \
    Safari/SafariWebExtensionHandler.swift -o "$APPEX/Contents/MacOS/MediaPickerSafari"

# 같은 인증서로 서명해야 재빌드해도 손쉬운 사용 권한이 유지된다.
IDENTITY=$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development|Developer ID Application/ {print $2; exit}')
codesign --force --sign "${IDENTITY:--}" --entitlements Safari/Safari.entitlements "$APPEX"
codesign --force --sign "${IDENTITY:--}" "$APP"
echo "built $APP (${IDENTITY:-ad-hoc})"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x MediaPicker || true
    rm -rf /Applications/MediaPicker.app
    cp -R "$APP" /Applications/
    open /Applications/MediaPicker.app
    echo "installed /Applications/MediaPicker.app"
fi
