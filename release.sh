#!/bin/zsh
# 배포 파일을 dist/ 에 만든다: 앱 DMG·zip, 크롬 웹스토어에 올릴 확장 zip, 체크섬.
# 공증하지 않은 빌드라서 받은 사람은 처음 한 번 '그래도 열기'를 해야 한다(README 참고).
set -euo pipefail
cd "$(dirname "$0")"

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
EXT_VERSION=$(python3 -c "import json; print(json.load(open('Extension/manifest.json'))['version'])")
if [[ "$VERSION" != "$EXT_VERSION" ]]; then
    echo "버전이 다릅니다: 앱 $VERSION, 확장 $EXT_VERSION" >&2
    exit 1
fi

./build.sh
codesign --verify --deep --strict build/MediaPicker.app

DIST=dist
rm -rf "$DIST"
mkdir -p "$DIST"

ditto -c -k --keepParent build/MediaPicker.app "$DIST/MediaPicker-$VERSION.zip"

STAGE=$(mktemp -d)
cp -R build/MediaPicker.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "MediaPicker $VERSION" -srcfolder "$STAGE" -format UDZO "$DIST/MediaPicker-$VERSION.dmg"
rm -rf "$STAGE"

(cd Extension && zip -qr -X "../$DIST/MediaPicker-Extension-$VERSION.zip" . -x '.*')

(cd "$DIST" && shasum -a 256 * > SHA256SUMS.txt)
ls -lh "$DIST"
