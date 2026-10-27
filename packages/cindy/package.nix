{
  lib,
  flake,
  stdenv,
  fetchFromGitHub,
  fetchPnpmDeps,
  pnpmConfigHook,
  pnpm_10,
  nodejs_22,
  electron_42,
  ripgrep,
  sqlite-vec,
  makeWrapper,
  copyDesktopItems,
  makeDesktopItem,
  zip,
  pkg-config,
  python3,
  gnumake,
  git,
  wayland-scanner,
  wayland,
  libxkbcommon,
  json_c,
  libjpeg_turbo,
  libpng,
  desktop-file-utils,
  dpkg,
  fakeroot,

  adwaita-icon-theme,
  alsa-lib,
  at-spi2-atk,
  at-spi2-core,
  atk,
  cairo,
  cups,
  dbus,
  expat,
  glib,
  gsettings-desktop-schemas,
  gtk3,
  libdrm,
  libgbm,
  libayatana-appindicator,
  libglvnd,
  libX11,
  libxcb,
  libXcomposite,
  libXcursor,
  libXdamage,
  libXext,
  libXfixes,
  libXi,
  libXrandr,
  libXrender,
  libXtst,
  libnotify,
  libsecret,
  libxshmfence,
  nspr,
  nss,
  pango,
  mesa,
  libpulseaudio,
  pipewire,
  systemdLibs,
  xdg-utils,
}:

let
  pname = "cindy";
  version = "0.1.118-beta";
  electron = electron_42;
  pnpm = pnpm_10;

  src = fetchFromGitHub {
    owner = "makecindy";
    repo = "cindy";
    tag = "v${version}";
    hash = "sha256-hfNPXIjtYI4Gestkgup0EvfDrUJMCaMlt3tFYBBWjck=";
  };

  runtimeLibraries = [
    adwaita-icon-theme
    alsa-lib
    at-spi2-atk
    at-spi2-core
    atk
    cairo
    cups
    dbus
    expat
    json_c
    stdenv.cc.cc.lib
    glib
    gsettings-desktop-schemas
    gtk3
    libdrm
    libgbm
    libayatana-appindicator
    libglvnd
    libX11
    libxcb
    libXcomposite
    libXcursor
    libXdamage
    libXext
    libXfixes
    libXi
    libXrandr
    libXrender
    libXtst
    libnotify
    libsecret
    libxkbcommon
    libxshmfence
    libjpeg_turbo
    libpng
    nspr
    nss
    pango
    mesa
    libpulseaudio
    pipewire
    systemdLibs
    wayland
  ];

  systemKey =
    if stdenv.hostPlatform.isx86_64 then
      "x64"
    else if stdenv.hostPlatform.isAarch64 then
      "arm64"
    else
      throw "Unsupported platform for cindy: ${stdenv.hostPlatform.system}";

  desktopItem = makeDesktopItem {
    name = "cindy";
    desktopName = "Cindy";
    genericName = "AI Assistant";
    comment = "Open-source AI agent desktop client";
    exec = "cindy %U";
    icon = "cindy";
    categories = [ "Development" ];
    mimeTypes = [
      "x-scheme-handler/cindy"
      "x-scheme-handler/xdt-maker"
    ];
    startupNotify = true;
    startupWMClass = "Cindy";
  };

  pnpmDeps = fetchPnpmDeps {
    inherit
      pname
      version
      src
      pnpm
      ;
    fetcherVersion = 3;
    hash = "sha256-KKRcSqR52S1bsfApdUqm5gSAHkWjPaaq5c3uwjweFC0=";
  };

in
stdenv.mkDerivation {
  inherit
    pname
    version
    src
    pnpmDeps
    ;

  strictDeps = true;

  nativeBuildInputs = [
    nodejs_22
    pnpm
    pnpmConfigHook
    makeWrapper
    copyDesktopItems
    zip
    pkg-config
    python3
    gnumake
    git
    wayland-scanner
    wayland
    libxkbcommon
    json_c
    libjpeg_turbo
    libpng
    desktop-file-utils
    dpkg
    fakeroot
  ];

  buildInputs = runtimeLibraries;
  dontStrip = true;

  env = {
    APP_VERSION = version;
    COREPACK_ENABLE = "0";
    ELECTRON_SKIP_BINARY_DOWNLOAD = "1";
    npm_config_build_from_source = "true";
    pnpm_config_manage_package_manager_versions = "false";
    npm_config_managePackageManagerVersions = "false";
    pnpm_config_managePackageManagerVersions = "false";
  };

  postPatch = ''
      sed -i '/"packageManager":/d' package.json
      sed -i '/onlyModules: modules,/a\    buildFromSource: true,' \
        apps/desktop/forge.config.ts
      sed -i '/packagerConfig: {/a\    electronZipDir: process.env.CINDY_ELECTRON_ZIP_DIR,' \
        apps/desktop/forge.config.ts

      # Use nixpkgs' ripgrep instead of Cindy's network downloader.
      sed -i 's/"version": "[^"]*"/"version": "${ripgrep.version}"/' \
        tools/ripgrep/latest.json

      # Keep the Nix package telemetry-free, including when it reuses a
      # user-data directory that has consented to analytics in another build.
      substituteInPlace apps/desktop/src/main/analytics-settings-store.ts \
        --replace-fail \
          'function isReportingBuild(): boolean {' \
          'function isReportingBuild(): boolean {
    if (process.env.CINDY_DISABLE_TELEMETRY === "1") return false;'
      substituteInPlace apps/desktop/src/main/analytics-settings-store.ts \
        --replace-fail \
          'analyticsEnabled: true,' \
          'analyticsEnabled: false,'

    install -Dm644 ${sqlite-vec}/lib/vec0.so \
      apps/desktop/native/sqlite-vec/linux-${systemKey}/vec0.so
  '';

  preBuild = ''
    export HOME="$TMPDIR/home"
    export XDG_CACHE_HOME="$TMPDIR/cache"
    mkdir -p "$HOME" "$XDG_CACHE_HOME"

    upstreamElectron=$(node -p "require('./apps/desktop/package.json').devDependencies.electron")
    if [[ "''${upstreamElectron%%.*}" != ${lib.versions.major electron.version} ]]; then
      echo "error: upstream expects Electron $upstreamElectron, but nixpkgs provides ${electron.version}" >&2
      exit 1
    fi

    # pnpm has already installed the lockfile's Electron package. Align the
    # build copy with nixpkgs without changing the fixed dependency store.
    sed -i 's/"electron": "[^"]*"/"electron": "${electron.version}"/' \
      apps/desktop/package.json
    sed -i '0,/"version": "[^"]*"/s//"version": "${electron.version}"/' \
      node_modules/electron/package.json

    electronDist="$TMPDIR/electron-dist"
    mkdir -p "$electronDist"
    cp -R ${electron}/libexec/electron/. "$electronDist/"
    chmod -R u+w "$electronDist"
    mkdir -p node_modules/electron/dist
    cp -R "$electronDist"/. node_modules/electron/dist/
    printf 'electron\n' > node_modules/electron/path.txt
    printf '%s\n' '${electron.version}' > node_modules/electron/dist/version
    mkdir -p "$TMPDIR/electron-zips"
    (cd "$electronDist" && zip -X -qr \
      "$TMPDIR/electron-zips/electron-v${electron.version}-linux-${systemKey}.zip" .)
    export CINDY_ELECTRON_ZIP_DIR="$TMPDIR/electron-zips"
    export npm_config_nodedir=${electron.headers}

    mkdir -p apps/ripgrep-bin/linux-${systemKey}
    install -Dm755 ${ripgrep}/bin/rg \
      apps/ripgrep-bin/linux-${systemKey}/rg
    printf '%s\n' '${ripgrep.version}' > apps/ripgrep-bin/linux-${systemKey}/.version
  '';

  buildPhase = ''
    runHook preBuild
    pnpm --config.manage-package-manager-versions=false --filter desktop build
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    appDir="apps/desktop/out/Cindy-linux-${systemKey}"
    test -x "$appDir/Cindy"
    mkdir -p "$out/lib/cindy" "$out/bin"
    cp -R "$appDir"/. "$out/lib/cindy/"
    install -Dm644 apps/desktop/resources/icon.png \
      "$out/share/icons/hicolor/512x512/apps/cindy.png"
    makeWrapper "$out/lib/cindy/Cindy" "$out/bin/cindy" \
      --chdir "$out/lib/cindy" \
      --set CINDY_DISABLE_TELEMETRY 1 \
      --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath runtimeLibraries}" \
      --prefix PATH : "${
        lib.makeBinPath [
          git
          xdg-utils
        ]
      }" \
      --prefix XDG_DATA_DIRS : "$XDG_ICON_DIRS:$GSETTINGS_SCHEMAS_PATH" \
      --add-flags "--no-sandbox --disable-setuid-sandbox"
    runHook postInstall
  '';

  desktopItems = [ desktopItem ];

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    test -x "$out/bin/cindy"
    test -x "$out/lib/cindy/Cindy"
    test -f "$out/lib/cindy/resources/app.asar"
    test -f "$out/share/applications/cindy.desktop"
    test -f "$out/share/icons/hicolor/512x512/apps/cindy.png"
    grep -q 'CINDY_DISABLE_TELEMETRY' "$out/bin/cindy"

    runHook postInstallCheck
  '';

  passthru.category = "AI Assistants";

  meta = with lib; {
    description = "Open-source AI agent desktop client";
    homepage = "https://cindy.app";
    changelog = "https://github.com/makecindy/cindy/releases/tag/v${version}";
    license = licenses.asl20;
    sourceProvenance = with sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ rucadi ];
    mainProgram = "cindy";
    platforms = platforms.unix;
  };
}
