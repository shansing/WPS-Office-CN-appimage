#!/usr/bin/env bash

APP=wps-office-cn
VERSION=$(wget -q https://aur.archlinux.org/cgit/aur.git/plain/PKGBUILD?h=wps-office-cn -O - | grep "pkgver=" | head -1 | cut -c 8-)
if test -z "$VERSION"; then
	echo "Failed to resolve WPS version"
	exit 1
fi

# CREATE A TEMPORARY DIRECTORY
mkdir -p tmp
cd tmp

WPS_DOWNLOAD_BASE_URL=$(wget -q https://aur.archlinux.org/packages/wps-office-cn -O - | grep -Eo "(http|https)://[a-zA-Z0-9./?=_%:-]*" | grep -i "amd64.deb" | head -1)
if test -z "$WPS_DOWNLOAD_BASE_URL"; then
	echo "Failed to resolve WPS download URL"
	exit 1
fi
WPS_DOWNLOAD_BASE_URL="${WPS_DOWNLOAD_BASE_URL%%\?*}"
WPS_DOWNLOAD_URI="${WPS_DOWNLOAD_BASE_URL#https://wps-linux-personal.wpscdn.cn}"
# https://aur.archlinux.org/cgit/aur.git/plain/PKGBUILD?h=wps-office-cn
WPS_DOWNLOAD_SECURITY_KEY="7f8faaaa468174dc1c9cd62e5f218a5b"
WPS_DOWNLOAD_T=$(date '+%s')
WPS_DOWNLOAD_K=$(printf '%s' "${WPS_DOWNLOAD_SECURITY_KEY}${WPS_DOWNLOAD_URI}${WPS_DOWNLOAD_T}" | md5sum | cut -d ' ' -f 1)
WPS_DOWNLOAD_URL="${WPS_DOWNLOAD_BASE_URL}?t=${WPS_DOWNLOAD_T}&k=${WPS_DOWNLOAD_K}"

# DOWNLOADING THE DEPENDENCIES
if test -f ./appimagetool; then
	echo " appimagetool already exists" 1> /dev/null
else
	echo " Downloading appimagetool..."
	wget -q https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage -O appimagetool
fi
if test -f ./pkg2appimage; then
	echo " pkg2appimage already exists" 1> /dev/null
else
	echo " Downloading pkg2appimage..."
	wget -q "$(curl -Ls https://api.github.com/repos/AppImageCommunity/pkg2appimage/releases/latest | sed 's/[()",{} ]/\n/g' | grep -io "http.*x86_64.*appimage$" | head -1)" -O pkg2appimage
fi
chmod a+x ./appimagetool ./pkg2appimage
rm -f ./recipe.yml

wget "$WPS_DOWNLOAD_URL" -O upstream-wps-office.deb

# CREATING THE HEAD OF THE RECIPE
cat >> recipe.yml << 'EOF'
app: wps-office-cn
binpatch: true

ingredients:

  dist: bookworm
  sources:
    - deb http://ftp.debian.org/debian/ bookworm main contrib non-free
    - deb http://security.debian.org/debian-security/ bookworm-security main contrib non-free
    - deb http://ftp.debian.org/debian/ bookworm-updates main contrib non-free
  script:
    - URL="WPS_DOWNLOAD_URL_PLACEHOLDER"
    - wget "$URL" -O wps-office.deb
    # http://kdl.cc.ksosoft.com/wps-community/download/fonts/wps-office-fonts_1.0_all.deb
    - wget https://repo.debiancn.org/pool/main/w/wps-office-fonts/wps-office-fonts_1.0_all.deb -O wps-office-fonts.deb
  packages:
    - wps-office
    - wps-office-fonts
    - libtiff-dev
    - libxml2
    - libbz2-1.0
    - poppler-data
    # - fonts-noto
    - libtiff5-dev

script:
  # From https://github.com/AppImageCommunity/pkg2appimage/blob/master/recipes/wps-office.yml
  - cp ./opt/kingsoft/wps-office/desktops/wps-office-prometheus.desktop ./
  - cp ./usr/share/icons/hicolor/256x256/apps/wps-office2023-kprometheus.png ./
  # Patch startup script to make sure it will start normally. Make the path be relative.
  # patching et
  - sed -i "2i#WPS startup script modified by linlinger " ./usr/bin/et
  - sed -i '3i currdir="$(dirname "$(readlink -f "${0}")")" ' ./usr/bin/et
  - sed -i 's|gInstallPath=/opt/kingsoft/wps-office|gInstallPath=$currdir/../../opt/kingsoft/wps-office|' ./usr/bin/et
  # patching wpp
  - sed -i "2i#WPS startup script modified by linlinger " ./usr/bin/wpp
  - sed -i '3i currdir="$(dirname "$(readlink -f "${0}")")" ' ./usr/bin/wpp
  - sed -i 's|gInstallPath=/opt/kingsoft/wps-office|gInstallPath=$currdir/../../opt/kingsoft/wps-office|' ./usr/bin/wpp
  # patching wps
  - sed -i "2i#WPS startup script modified by linlinger " ./usr/bin/wps
  - sed -i '3i currdir="$(dirname "$(readlink -f "${0}")")" ' ./usr/bin/wps
  - sed -i 's|gInstallPath=/opt/kingsoft/wps-office|gInstallPath=$currdir/../../opt/kingsoft/wps-office|' ./usr/bin/wps
  # patching wpspdf
  - sed -i "2i#WPS startup script modified by linlinger " ./usr/bin/wpspdf
  - sed -i '3i currdir="$(dirname "$(readlink -f "${0}")")" ' ./usr/bin/wpspdf
  - sed -i 's|gInstallPath=/opt/kingsoft/wps-office|gInstallPath=$currdir/../../opt/kingsoft/wps-office|' ./usr/bin/wpspdf
EOF
sed -i "s|WPS_DOWNLOAD_URL_PLACEHOLDER|$WPS_DOWNLOAD_URL|g" recipe.yml

# DOWNLOAD ALL THE NEEDED PACKAGES AND COMPILE THE APPDIR
./pkg2appimage ./recipe.yml

# pkg2appimage/AppRun cleanup can leave dangling symlinks for WPS' bundled
# compiler runtimes. Restore these from the upstream deb before packaging.
WPS_DEB_EXTRACT_DIR=$(mktemp -d)
dpkg-deb -x upstream-wps-office.deb "$WPS_DEB_EXTRACT_DIR"
cp -a "$WPS_DEB_EXTRACT_DIR"/opt/kingsoft/wps-office/office6/libstdc++.so.6* ./$APP/$APP.AppDir/opt/kingsoft/wps-office/office6/
cp -a "$WPS_DEB_EXTRACT_DIR"/opt/kingsoft/wps-office/office6/libgcc_s.so.1 ./$APP/$APP.AppDir/opt/kingsoft/wps-office/office6/
rm -rf "$WPS_DEB_EXTRACT_DIR"

if test -e ./$APP/$APP.AppDir/lib/x86_64-linux-gnu/libbz2.so.1.0.4; then
	cp -a ./$APP/$APP.AppDir/lib/x86_64-linux-gnu/libbz2.so.1.0.4 ./$APP/$APP.AppDir/opt/kingsoft/wps-office/office6/
elif test -e ./$APP/$APP.AppDir/usr/lib/x86_64-linux-gnu/libbz2.so.1.0.4; then
	cp -a ./$APP/$APP.AppDir/usr/lib/x86_64-linux-gnu/libbz2.so.1.0.4 ./$APP/$APP.AppDir/opt/kingsoft/wps-office/office6/
else
	echo "Missing libbz2.so.1.0.4"
	exit 1
fi

# LIBUNIONPRELOAD
#wget https://github.com/project-portable/libunionpreload/releases/download/amd64/libunionpreload.so
#chmod a+x libunionpreload.so
#mv ./libunionpreload.so ./$APP/$APP.AppDir/

# COMPILE SCHEMAS
glib-compile-schemas ./$APP/$APP.AppDir/usr/share/glib-2.0/schemas/ || echo "No ./usr/share/glib-2.0/schemas/"

# CUSTOMIZE THE APPRUN
rm -R -f ./$APP/$APP.AppDir/AppRun
cat >> ./$APP/$APP.AppDir/AppRun << 'EOF'
#!/usr/bin/env bash
HERE="$(dirname "$(readlink -f "${0}")")"
# export QT_FONT_DPI=96
export LD_LIBRARY_PATH="$HERE/usr/lib":"$HERE/usr/lib/x86_64-linux-gnu":"$HERE/lib":"$HERE/lib/x86_64-linux-gnu":"$HERE/lib64":$LD_LIBRARY_PATH
case $1 in
	'')
		"$HERE/opt/kingsoft/wps-office/office6/wpsoffice" 2>/dev/null;;
	'et')
		"$HERE/usr/bin/et" "$2" 2>/dev/null;;
	'wpp')
		"$HERE/usr/bin/wpp" "$2" 2>/dev/null;;
	'wps')
		"$HERE/usr/bin/wps" "$2" 2>/dev/null;;
	'wpspdf')
		"$HERE/usr/bin/wpspdf" "$2" 2>/dev/null;;
	'help'|'-h'|'--help')
		echo -e "\n USAGE:		[OPTION]"
		echo -e "\n 		[OPTION] /path/to/document"
		echo -e "\n OPTIONS:	-h,--help	Show this message"
		echo -e "\n 		-v,--version	Show the version"
		echo -e "\n 		et		Open WPS Spreadsheets"
		echo -e "\n 		wpp		Open WPS Presentation"
		echo -e "\n 		wps		Open WPS Writer"
		echo -e "\n 		wpspdf		Open WPS PDF\n";;
	'-v'|'--version')
		echo "WPS Office vVREPLACE";;
esac
EOF
sed -i "s/VREPLACE/$VERSION/g" ./$APP/$APP.AppDir/AppRun

# MADE THE APPRUN EXECUTABLE
chmod a+x ./$APP/$APP.AppDir/AppRun
# END OF THE PART RELATED TO THE APPRUN, NOW WE WELL SEE IF EVERYTHING WORKS ----------------------------------------------------------------------

# IMPORT THE LAUNCHER AND THE ICON TO THE APPDIR IF THEY NOT EXIST
if test -f ./$APP/$APP.AppDir/*.desktop; then
	echo "The desktop file exists"
else
	echo "Trying to get the .desktop file"
	cp ./$APP/$APP.AppDir/opt/kingsoft/wps-office/desktops/wps-office-prometheus.desktop ./$APP/$APP.AppDir/ 2>/dev/null ||
		cp ./$APP/$APP.AppDir/usr/share/applications/*$(ls . | grep -i $APP | cut -c -4)*desktop ./$APP/$APP.AppDir/ 2>/dev/null
fi

ICONNAME=$(cat ./$APP/$APP.AppDir/*desktop | grep "Icon=" | head -1 | cut -c 6-)
cp ./$APP/$APP.AppDir/usr/share/icons/hicolor/22x22/apps/*$ICONNAME* ./$APP/$APP.AppDir/ 2>/dev/null
cp ./$APP/$APP.AppDir/usr/share/icons/hicolor/24x24/apps/*$ICONNAME* ./$APP/$APP.AppDir/ 2>/dev/null
cp ./$APP/$APP.AppDir/usr/share/icons/hicolor/32x32/apps/*$ICONNAME* ./$APP/$APP.AppDir/ 2>/dev/null
cp ./$APP/$APP.AppDir/usr/share/icons/hicolor/48x48/apps/*$ICONNAME* ./$APP/$APP.AppDir/ 2>/dev/null
cp ./$APP/$APP.AppDir/usr/share/icons/hicolor/64x64/apps/*$ICONNAME* ./$APP/$APP.AppDir/ 2>/dev/null
cp ./$APP/$APP.AppDir/usr/share/icons/hicolor/128x128/apps/*$ICONNAME* ./$APP/$APP.AppDir/ 2>/dev/null
cp ./$APP/$APP.AppDir/usr/share/icons/hicolor/256x256/apps/*$ICONNAME* ./$APP/$APP.AppDir/ 2>/dev/null
cp ./$APP/$APP.AppDir/usr/share/icons/hicolor/512x512/apps/*$ICONNAME* ./$APP/$APP.AppDir/ 2>/dev/null
cp ./$APP/$APP.AppDir/usr/share/icons/hicolor/scalable/apps/*$ICONNAME* ./$APP/$APP.AppDir/ 2>/dev/null
cp ./$APP/$APP.AppDir/usr/share/applications/*$ICONNAME* ./$APP/$APP.AppDir/ 2>/dev/null
sed -i '/^X-AppImage-Version=/d' ./$APP/$APP.AppDir/*.desktop

BROKEN_LINKS=$(find ./$APP/$APP.AppDir/opt/kingsoft/wps-office/office6 -maxdepth 1 -type l -print | while IFS= read -r link; do
	target=$(readlink "$link")
	case "$target" in
		/*) resolved="./$APP/$APP.AppDir$target" ;;
		*) resolved="$(dirname "$link")/$target" ;;
	esac
	test -e "$resolved" || printf '%s -> %s\n' "$link" "$target"
done)
if test -n "$BROKEN_LINKS"; then
	echo "Broken office6 symlinks:"
	echo "$BROKEN_LINKS"
	exit 1
fi

## MUI PATCH
#cp ./$APP/$APP.AppDir/opt/kingsoft/wps-office/office6/mui/lang_list/lang_list_community.json ./opt/kingsoft/wps-office/office6/mui/lang_list/lang_list_community.json.backup
#lang_list=$(wget -q https://api.github.com/repos/wachin/wps-office-all-mui-win-language/releases -O - | grep browser_download_url | grep "lang_list_community.json" | cut -d '"' -f 4 | head -1)
#wget -c $lang_list
#cp lang_list_community.json ./$APP/$APP.AppDir/opt/kingsoft/wps-office/office6/mui/lang_list/
#dicts=$(wget -q https://api.github.com/repos/wachin/wps-office-all-mui-win-language/releases -O - | grep browser_download_url | grep "dicts.7z" | cut -d '"' -f 4 | head -1)
#wget -q $dicts
#7za x dicts.7z
#rsync -av ./dicts/* ./$APP/$APP.AppDir/opt/kingsoft/wps-office/office6/dicts/spellcheck/
#mui=$(wget -q https://api.github.com/repos/wachin/wps-office-all-mui-win-language/releases -O - | grep browser_download_url | grep "mui.7z" | cut -d '"' -f 4 | head -1)
#wget -q $mui
#7za x mui.7z
#rsync -av ./mui/* ./$APP/$APP.AppDir/opt/kingsoft/wps-office/office6/mui/
#rm -f -R ./*.7z

# EXPORT THE APP TO AN APPIMAGE
VERSION="$VERSION" ARCH=x86_64 ./appimagetool --comp zstd --mksquashfs-opt -Xcompression-level --mksquashfs-opt 20 \
	-u "gh-releases-zsync|$GITHUB_REPOSITORY_OWNER|WPS-Office-CN-appimage|continuous|*x86_64.AppImage.zsync" \
	./"$APP"/"$APP".AppDir WPS-Office-CN_"$VERSION"-x86_64.AppImage
cd ..
mv ./tmp/*.AppImage* ./
