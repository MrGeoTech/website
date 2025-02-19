with import <nixpkgs> {};
stdenv.mkDerivation rec {
    name = "website-dev-env";
    version = "0.2.0";

    # Build dependencies
    buildInputs = with pkgs; [ 
        zig
        md4c
    ];
}

