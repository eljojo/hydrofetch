#! /usr/bin/env nix-shell
#! nix-shell ../shell.nix -i bash

set -eu

OCI_ARCHIVE=$(nix-build --no-out-link -A packages.x86_64-linux.ociImage)
DOCKER_REPOSITORY="docker://ghcr.io/eljojo/hydrofetch"

skopeo copy --dest-creds="eljojo:${GITHUB_TOKEN}" "docker-archive:${OCI_ARCHIVE}" "${DOCKER_REPOSITORY}"

