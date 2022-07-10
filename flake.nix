{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    gourou-src = {
      url = "git://soutade.fr/libgourou.git";
      flake = false;
    };
    updfparser-src = {
      url = "git://soutade.fr/updfparser.git";
      flake = false;
    };
    base64-src = {
      url = "git+https://gist.github.com/f0fd86b6c73063283afe550bc5d77594.git";
      flake = false;
    };
    pugixml-src = {
      url = "github:zeux/pugixml/latest";
      flake = false;
    };
  };

  outputs =
    { nixpkgs, flake-utils, gourou-src, updfparser-src, base64-src, pugixml-src, ... }:
    let
      version = "1.3.0";
      _ = builtins // nixpkgs.lib;
      systems = [ "aarch64-linux" "x86_64-linux" "aarch64-darwin" "x86_64-darwin" ];
      eachSystem = flake-utils.lib.eachSystem;
      obj-flags = "-O2 -static";
      installPhase = ''
        mkdir -p $out
        find . -type f -maxdepth 1 -name "*.a" -exec install -D {} -t $out/lib \;
        find . -type f -maxdepth 1 -executable -exec install -D {} -t $out/bin \;
      '';
    in

    eachSystem systems (system:
    let
      nixpkgs-dyn = nixpkgs.legacyPackages.${system};
      nixpkgs-stat = if (!nixpkgs-dyn.stdenv.isDarwin)
                     then nixpkgs-dyn.pkgsStatic
                     else (nixpkgs-dyn.callPackage ./static-libs.nix {
                       nixpkgs = nixpkgs-dyn; });
      stdenv = nixpkgs-stat.stdenv;
      cc = "${stdenv.cc}/bin/${stdenv.cc.targetPrefix}c++";
      ar = "${stdenv.cc.bintools.bintools_bin}/bin/${stdenv.cc.targetPrefix}ar";
      mkDerivation = stdenv.mkDerivation;
      start-group = _.optionalString (stdenv.isLinux)
        ''-Wl,--as-needed -static \
          -Wl,--start-group'';
      end-group = _.optionalString (stdenv.isLinux)
        ''-static-libgcc -static-libstdc++ \
          -Wl,--end-group'';
    in
    rec {
      packages = {
        libzip-static = nixpkgs-stat.libzip.overrideAttrs (prev: {
          cmakeFlags = (prev.cmakeFlags or [ ]) ++ [
            "-DBUILD_SHARED_LIBS=OFF"
            "-DBUILD_EXAMPLES=OFF"
            "-DBUILD_DOC=OFF"
            "-DBUILD_TOOLS=OFF"
            "-DBUILD_REGRESS=OFF"
          ];
          outputs = [ "out" ];
        });

        base64 = mkDerivation {
          name = "base64";
          src = "${base64-src}";

          phases = [ "unpackPhase" "installPhase" ];

          installPhase = ''
            mkdir -p $out/include/base64
            cp Base64.h $out/include/base64/Base64.h
          '';
        };

        updfparser = mkDerivation {
          name = "updfparser";
          src = "${updfparser-src}";

          buildPhase = ''
            ${cc} \
              -c src/*.cpp \
              -I include \
              ${obj-flags}
            ${ar} crs lib$name.a *.o
          '';
          inherit installPhase;

        };

        gourou = mkDerivation {
          name = "gourou";
          src = "${gourou-src}";

          postPatch = "rm -f src/pugixml.cpp";

          patches = [ ./patches/gourou/0001-Update-get_mac_address-to-support-darwin.patch ];

          buildPhase = ''
            mkdir -p $out
            ${cc} \
              -c \
              src/*.cpp \
              ${pugixml-src}/src/pugixml.cpp \
              -I include \
              -I ${packages.base64}/include \
              -I ${pugixml-src}/src \
              -I ${updfparser-src}/include \
              ${obj-flags}
            ${ar} crs lib$name.a *.o
          '';
          inherit installPhase;
        };

        utils-common = mkDerivation {
          name = "utils-common";
          src = "${gourou-src}";

          buildPhase = ''
            ${cc} \
              -c utils/drmprocessorclientimpl.cpp \
                 utils/utils_common.cpp \
              -I utils \
              -I include \
              -I ${pugixml-src}/src \
              -I ${nixpkgs-stat.openssl.dev}/include \
              -I ${nixpkgs-stat.curl.dev}/include \
              -I ${nixpkgs-stat.zlib.dev}/include \
              -I ${packages.libzip-static}/include \
              ${obj-flags}
            ${ar} crs lib$name.a *.o
          '';
          inherit installPhase;
        };

        knock = mkDerivation {
          name = "knock";
          src = ./.;

          buildInputs = with nixpkgs-stat; [
            libnghttp2
            libidn2
            libunistring
            libssh2
            zlib
            openssl
            curl
          ];
          buildPhase = ''
            ${cc} \
              -o knock \
              src/knock.cpp \
              -D KNOCK_VERSION='"${version}"' \
              --std=c++17 \
              -I ${gourou-src}/utils \
              -I ${gourou-src}/include \
              -I ${pugixml-src}/src \
              -I ${nixpkgs-stat.openssl.dev}/include \
              -I ${nixpkgs-stat.curl.dev}/include \
              -I ${nixpkgs-stat.zlib.dev}/include \
              -I ${packages.libzip-static}/include \
              ${start-group} \
              -lzip \
              -lnghttp2 \
              -lidn2 \
              -lunistring \
              -lssh2 \
              -lzstd \
              -lz \
              -lcrypto \
              -lcurl \
              -lssl \
              ${packages.utils-common}/lib/lib${packages.utils-common.name}.a \
              ${packages.gourou}/lib/lib${packages.gourou.name}.a \
              ${packages.updfparser}/lib/lib${packages.updfparser.name}.a \
              -L${packages.libzip-static}/lib \
              -L${nixpkgs-stat.libnghttp2}/lib \
              -L${nixpkgs-stat.libidn2.out}/lib \
              -L${nixpkgs-stat.libunistring}/lib \
              -L${nixpkgs-stat.libssh2}/lib \
              -L${nixpkgs-stat.zstd.out}/lib \
              -L${nixpkgs-stat.zlib}/lib \
              -L${nixpkgs-stat.openssl.out}/lib \
              -L${nixpkgs-stat.openssl.out}/lib \
              -L${nixpkgs-stat.curl.out}/lib \
              ${end-group}
          '';
          inherit installPhase;
        };

        tests = mkDerivation {
          name = "tests";
          src = ./tests;
          buildInputs = [
            (nixpkgs-dyn.python3.withPackages (p: [
              p.beautifulsoup4
              p.requests
            ]))
          ];
          patchPhase = ''
            substituteInPlace tests.py --replace "./result/bin/knock" \
            "${packages.knock}/bin/knock"
          '';
          installPhase = ''
            mkdir -p $out/bin
            cp tests.py $out/bin/tests
            chmod +x $out/bin/tests
          '';
        };

        formatter = nixpkgs-stat.writeShellScriptBin "formatter" (''
          set -x
          ${nixpkgs-dyn.clang-tools}/bin/clang-format -i --verbose ./src/*.cpp
          ${nixpkgs-dyn.nixpkgs-fmt}/bin/nixpkgs-fmt .
        ''
        + _.optionalString (! (stdenv.isDarwin && stdenv.isAarch64)) ''
          ${nixpkgs-dyn.black}/bin/black ./tests
        ''); # pyopenssl is broken for Darwin && Aarch64
      };

      defaultPackage = packages.knock;
    });
}
