{
  system ? builtins.currentSystem,
  nixpkgs
}:
let
  staticOverride = (pkg: rest@{override ? {}, overrideAttrs ? {}}:
    (pkg.override override)
      .overrideAttrs (self: super:
        {
          dontDisableStatic = true;
          configureFlags = (super.configureFlags or []) ++ ["--enable-static" "--disable-shared"];
          cmakeFlags =     (super.cmakeFlags     or []) ++ ["-DBUILD_SHARED_LIBS:BOOL=OFF"];
          mesonFlags =     (super.mesonFlags     or []) ++ ["-Ddefault_library=static"];
        } // (if builtins.isFunction overrideAttrs
              then (overrideAttrs self super)
              else overrideAttrs)));
in
nixpkgs // rec {
  libidn2 = staticOverride nixpkgs.libidn2 {};
  libssh2 = staticOverride nixpkgs.libssh2 {};
  libiconv = nixpkgs.libiconv.override {
    enableStatic = true;
    enableShared = false;
  };
  libunistring = staticOverride nixpkgs.libunistring {
    override = { libiconv = libiconv; };
  };
  zstd = nixpkgs.zstd
    .override { static = true; };
  zlib = nixpkgs.zlib
    .override { shared = false; };
  openssl = nixpkgs.openssl
    .override { static = true; };
  curl = staticOverride nixpkgs.curl
    {
      override = {
        brotliSupport = false;
        gssSupport = false;
      };
      overrideAttrs = {
        outputs = [ "out" "dev" ];
        doCheck = false; # checks take forever!
      };
    };
  libnghttp2 = (nixpkgs.nghttp2
    .override { enableApp = false; enableTests = false; })
    .lib # only need the `lib`-part
    .overrideAttrs (self: super: {
      configureFlags = [ # completely override configFlags
        "--enable-shared=no"
        "--enable-static=yes"
        "--enable-lib-only"
        "--disable-examples"
      ];
      dontDisableStatic=true;
      outputs = [ "lib" "out"];
    });
}
