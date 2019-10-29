#!/usr/bin/env bash

set -o errexit -o nounset

GREEN='\033[0;32m'
NC='\033[0m'

function build_release() {
  registry="${1}"
  organization="${2}"
  username="${3}"
  password="${4}"
  stemcell_image="${5}"
  release_name="${6}"
  release_url="${7}"
  release_version="${8}"
  release_sha1="${9}"

  echo -e "Release information:"
  echo -e "  - Release name:    ${GREEN}${release_name}${NC}"
  echo -e "  - Release version: ${GREEN}${release_version}${NC}"
  echo -e "  - Release URL:     ${GREEN}${release_url}${NC}"
  echo -e "  - Release SHA1:    ${GREEN}${release_sha1}${NC}"

  build_args=(
    --stemcell="${stemcell_image}"
    --name="${release_name}"
    --version="${release_version}"
    --url="${release_url}"
    --sha1="${release_sha1}"
    --docker-registry="${registry}"
    --docker-organization="${organization}"
  )

  built_image=$(fissile build release-images --dry-run "${build_args[@]}" | cut -d' ' -f3)
  built_image_tag="${built_image#*:}"
  creds_string=""${username}":"${password}""

  # Only build and push the container image if doesn't exits already.
  if docker manifest inspect "${built_image}" 2>&1 >/dev/null | grep -q "no such manifest"; then
      # Build the release image.
      fissile build release-images "${build_args[@]}"
      echo -e "Built image: ${GREEN}${built_image}${NC}"
      docker push "${built_image}"
      docker rmi "${built_image}"
  else
      echo -e "Skipping push for ${GREEN}${built_image}${NC} as it is already present in the registry..."
  fi

  echo '----------------------------------------------------------------------------------------------------'
}
