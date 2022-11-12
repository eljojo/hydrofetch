with (import <nixpkgs> {});
let
  ruby = ruby_2_7;
  myBundler = bundler.override { inherit ruby; };
  myBundix = bundix.override { bundler = myBundler; };

in pkgs.mkShell {
  buildInputs = with pkgs;[
    myBundler
    myBundix
  ];

  #BUNDLE_USER_HOME = toString /Users/jojo/.cache/bundle-nix;
}
