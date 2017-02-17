#!/bin/bash -e
# This script is used to build and test the OpenShift Docker images.
#
# Name of resulting image will be: 'NAMESPACE/OS-BASE_IMAGE_NAME:NODE_VERSION'.
#
# VERSION - Specifies the image version
# TEST_MODE - If set, build a candidate image and test it
# TAG_ON_SUCCESS - If set, tested image will be re-tagged as a non-candidate
#       image, if the tests pass.
# VERSIONS - a list of possible versions, can be provided instead of VERSION

OS=${1-$OS}
VERSION=${2-$VERSION}

DOCKERFILE="Dockerfile"
if [[ ! -z "$ONBUILD" ]]; then
  BASE_IMAGE_NAME="${ONBUILD_IMAGE_NAME}"
  DOCKERFILE+=".onbuild"
fi

# Cleanup the temporary Dockerfile created by docker build with version
trap "rm -f ${DOCKERFILE}.${version}" SIGINT SIGQUIT EXIT

# Perform docker build but append the LABEL with GIT commit id at the end
function docker_build_with_version {
  cp ${DOCKERFILE} "${DOCKERFILE}.${version}"
  git_version=$(git rev-parse HEAD)
  sed -i.bak -e "s/NODE_VERSION *= *.*/NODE_VERSION=${version} \\\/" "${DOCKERFILE}.${version}"
  echo "LABEL io.origin.builder-version=\"${git_version}\"" >> "${DOCKERFILE}.${version}"
  docker build -t ${IMAGE_NAME}:${version} -f "${DOCKERFILE}.${version}" .
  rm -f "${DOCKERFILE}.${version}" "${DOCKERFILE}.${version}.bak"
}

# Specify a VERSION variable to build a specific nodejs.org release
# or specify a list of VERSIONS
versions=${VERSION:-$VERSIONS}

for version in ${versions}; do
  IMAGE_NAME="${NAMESPACE}/${OS}-${BASE_IMAGE_NAME}"

  if [[ ! -z "$TEST_MODE" ]]; then
    IMAGE_NAME+="-candidate"
  fi

  echo "-> Building ${IMAGE_NAME}:${version} ..."

  pushd "nodejs.org" > /dev/null
  if [ "$OS" == "fedora" -o "$OS" == "fedora-candidate" ]; then
    docker_build_with_version Dockerfile.fedora
  else
    docker_build_with_version Dockerfile
  fi

  if [[ ! -z "$TEST_MODE" ]]; then
    IMAGE_NAME=${IMAGE_NAME} NODE_VERSION=${version} test/run

    if [[ $? -eq 0 ]] && [[ "${TAG_ON_SUCCESS}" == "true" ]]; then
      echo "-> Re-tagging ${IMAGE_NAME}:${version} image to ${IMAGE_NAME%"-candidate"}:${version}"
      docker tag -f $IMAGE_NAME:$version ${IMAGE_NAME%"-candidate"}:${version}
    fi

    if [[ ! -z "${REGISTRY}" ]]; then
      echo "-> Tagging image as" ${REGISTRY}/${IMAGE_NAME%"-candidate"}
      docker tag -f $IMAGE_NAME ${REGISTRY}/${IMAGE_NAME%"-candidate"}
    fi
  fi

  popd > /dev/null
done
