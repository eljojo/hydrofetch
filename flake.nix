{
  description = "web service that scrapes hydro";

  inputs.nixpkgs.url = "nixpkgs/nixos-unstable";
  inputs.flake-utils.url = "github:numtide/flake-utils";
  inputs.flake-compat = {
    url = github:edolstra/flake-compat;
    flake = false;
  };

  outputs = { self, nixpkgs, flake-utils, flake-compat }: flake-utils.lib.eachDefaultSystem
    (system:
      let
        revision = "${self.lastModifiedDate}-${self.shortRev or "dirty"}";

        # pkgs = nixpkgs.legacyPackages.${system};
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };

        ruby = pkgs.ruby_3_1;

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
          propagatedBuildInputs = [ ];

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
            cat > $bin <<EOF
#!/bin/sh -e
exec ${rubyEnv}/bin/bundle exec $out/share/hydrofetch/exe/hydrofetch "\$@"
EOF
            chmod +x $bin

            debugbin=$out/bin/dev
            cat > $debugbin <<EOF
#!/bin/sh -e
exec ${rubyEnv}/bin/bundle exec ${ruby}/bin/irb -I $out/share/hydrofetch/lib -r hydrofetch
EOF
            chmod +x $debugbin
          '';
        };

        hydrofetch = buildGem { };
        # buildChromeBase = pkgs.dockerTools.buildImage {
        #   name = "chromebase";
        #   tag = revision;
        #   copyToRoot = pkgs.buildEnv {
        #     name = "image-root";
        #     pathsToLink = [ "/bin" ];
        #     paths = with pkgs.dockerTools; [
        #       pkgs.google-chrome
        #       pkgs.chromedriver
        #       pkgs.dockerTools.caCertificates
        #     ];
        #   };
        #   config = {
        #     Env = [
        #       "DISPLAY=:99.0"
        #       "SE_BIND_HOST=false"
        #       "DBUS_SESSION_BUS_ADDRESS=/dev/null"
        #     ];
        #   };
        #   extraCommands = ''
        #     mkdir -p dev/shm
        #     chmod +x dev/shm
        #   '';
        # };
        chromeBaseImage = pkgs.dockerTools.pullImage {
          imageName = "selenium/standalone-chrome";
          imageDigest = "sha256:2e1f59fb711ba42fb68a6c8ee1820eb955d11e8da7db05c318b175650d5ec572";
          finalImageName = "standalone-chrome";
          finalImageTag = "107.0";
          sha256 = "sha256-aIamKtmPKanU4VefCwzqMrUnaOEFS0v4BW6aojJPem0=";
          os = "linux";
          arch = "x86_64";
        };
        hydrofetchDockerImage = pkgs.dockerTools.buildImage {
          name = "hydrofetch";
          tag = revision;
          # fromImage = buildChromeBase;
          fromImage = chromeBaseImage;
          copyToRoot = pkgs.buildEnv {
            name = "image-root";
            pathsToLink = [ "/bin" ];
            paths = with pkgs.dockerTools; [
              pkgs.which
              pkgs.bashInteractive
              pkgs.coreutils
              rubyEnv
              hydrofetch
            ];
          };
          config = {
            Cmd = [
              "/bin/hydrofetch"
              "server"
            ];
            ExposedPorts = {
              "8080/tcp" = { };
            };
          };
          extraCommands = ''
            mkdir -p tmp
          '';
        };
      in
      {

        devShells.default = with pkgs; mkShell {
          buildInputs = [
            rubyEnv (lowPrio rubyEnv.wrappedRuby) skopeo pkgs.chromedriver # hydrofetch
          ];
        };

        packages = {
          ociImage = hydrofetchDockerImage;
          # default = rubyEnv;
          default = hydrofetch;
        };
      });
}
