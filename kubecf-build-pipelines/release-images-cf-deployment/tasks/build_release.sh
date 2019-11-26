#!/usr/bin/env bash

set -o errexit -o nounset

GREEN='\033[0;32m'
NC='\033[0m'

function build_release() {
  cf_version="${1}"
  registry="${2}"
  organization="${3}"
  stemcell_image="${4}"
  release_name="${5}"
  release_url="${6}"
  release_version="${7}"
  release_sha1="${8}"

  echo -e "Release information:"
  echo -e "  - CF Version:      ${GREEN}${cf_version}${NC}"
  echo -e "  - Release name:    ${GREEN}${release_name}${NC}"
  echo -e "  - Release version: ${GREEN}${release_version}${NC}"
  echo -e "  - Release URL:     ${GREEN}${release_url}${NC}"
  echo -e "  - Release SHA1:    ${GREEN}${release_sha1}${NC}"

  build_args=(
    --stemcell="${stemcell_image}"
    --name="${release_name}"
    --version="${release_version}"
    --sha1="${release_sha1}"
    --url="${release_url}"
    --docker-registry="${registry}"
    --docker-organization="${organization}"
  )

  built_image=$(fissile build release-images --dry-run "${build_args[@]}" | cut -d' ' -f3)
  built_image_tag="${built_image#*:}"

  export DOCKER_CLI_EXPERIMENTAL=enabled;  
  # Only build and push the container image if doesn't exits already.
  if docker manifest inspect "${built_image}" 2>&1 | grep --quiet "no such manifest"; then
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
