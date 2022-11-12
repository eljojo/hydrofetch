with (import <nixpkgs> {});
let
  ruby = ruby_3_1;

  env = bundlerEnv {
    name = "hydro-bundler-env";
    inherit ruby;
    gemdir = ./.;
    gemset = ./nix/gemset.nix;
    groups = ["default" "development" "test"];

    gemConfig.nokogiri = attrs: {
      buildInputs = [ libiconv zlib ];
    };

    gemConfig.openssl = attrs: {
      buildInputs = [ openssl ];
    };
  };

in pkgs.mkShell {
  buildInputs = [ env (lowPrio env.wrappedRuby) google-chrome chromedriver ];

  BUNDLE_FORCE_RUBY_PLATFORM = true;
}
