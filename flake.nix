{
  description = "The contents of https://thewagner.net";

  inputs.nixpkgs.url = "nixpkgs/nixos-21.11";
  inputs.flake-utils.url = "github:numtide/flake-utils";
  inputs.flake-compat = {
    url = github:edolstra/flake-compat;
    flake = false;
  };

  outputs = { self, nixpkgs, flake-utils, flake-compat }: flake-utils.lib.eachDefaultSystem
    (system:
      let
        revision = "${self.lastModifiedDate}-${self.shortRev or "dirty"}";

        pkgs = nixpkgs.legacyPackages.${system};

        ruby = pkgs.ruby_3_0;

        rubyEnv = pkgs.bundlerEnv {
          name = "hydro-bundler-env";
          inherit ruby;
          gemdir = ./.;
          gemset = ./nix/gemset.nix;
          groups = ["default" "development" "test"];

          gemConfig.nokogiri = attrs: {
            buildInputs = [ pkgs.libiconv pkgs.zlib ];
          };

          gemConfig.openssl = attrs: {
            buildInputs = [ pkgs.openssl ];
          };
        };

        buildGem = { }: pkgs.stdenv.mkDerivation {
          name = "hydrofetch-${self.shortRev or "dirty"}";

          nativeBuildInputs = [ rubyEnv ];

          src = builtins.path {
            filter = path: type: type != "directory" || baseNameOf path != "archive";
            path = ./.;
            name = "src";
          };

          dontBuild = true;

          installPhase = ''
            mkdir -p $out/{bin,share/hydrofetch}
            cp -r * $out/share/hydrofetch
            bin=$out/bin/hydrofetch
            # we are using bundle exec to start in the bundled environment
            cat > $bin <<EOF
#!/bin/sh -e
exec ${rubyEnv}/bin/bundle exec ${rubyEnv}/bin/ruby $out/share/exe/hydrofetch "\$@"
EOF
            chmod +x $bin
          '';
        };

        buildImage =
          let
            port = "8000";
            hydrofetch = buildGem { };
          in
          pkgs.dockerTools.buildLayeredImage
            {
              name = "hydrofetch";
              tag = revision;
              config = {
                Cmd = [
                  "${hydrofetch}/bin/hydrofetch"
                  "--port"
                  port
                ];
                ExposedPorts = {
                  "${port}/tcp" = { };
                };
              };
            };
      in
      {

        devShells.default = with pkgs; mkShell {
          buildInputs = [
            rubyEnv (lowPrio rubyEnv.wrappedRuby) skopeo
          ];
        };

        packages = {
          ociImage = buildImage;
          # default = rubyEnv;
          default = buildGem { };
        };
      });
}
