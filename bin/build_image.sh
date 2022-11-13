#! /usr/bin/env nix-shell
#! nix-shell ../shell.nix -i bash

set -eu

echo "Building Docker Image"
OCI_ARCHIVE=$(nix-build --no-out-link -A packages.x86_64-linux.ociImage)
DOCKER_REPOSITORY="docker://ghcr.io/eljojo/hydrofetch"

echo "Pushing docker image to GitHub Container Registry"
skopeo copy --dest-creds="eljojo:${GITHUB_TOKEN}" "docker-archive:${OCI_ARCHIVE}" "${DOCKER_REPOSITORY}"

