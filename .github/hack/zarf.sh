#!/usr/bin/env bash

set -u
set -o pipefail

# renovate: dep
export BB_VERSION="3.2.0"

rm -rf ./.direnv/bigbang
mkdir -p ./.direnv/bigbang

curl -s -L -o ./.direnv/bigbang/package-images.yaml  https://umbrella-bigbang-releases.s3-us-gov-west-1.amazonaws.com/umbrella/$BB_VERSION/package-images.yaml
curl -s -L -o ./.direnv/bigbang/oci_package_list.txt https://umbrella-bigbang-releases.s3.us-gov-west-1.amazonaws.com/umbrella/$BB_VERSION/oci_package_list.txt

yq -i '.x-tra[0].images = []' zarf.yaml

for chart in $(cat .direnv/bigbang/oci_package_list.txt); do
  export yq_chart=$(printf '.x-tra[0].images += "%s"' "$chart")
  echo "::debug::yq_chart='${yq_chart}'"
  yq -i "$yq_chart" zarf.yaml
done

yq -i '.components = .x-tra' zarf.yaml

for pkg in $(yq '.package-image-list | keys | .[]' .direnv/bigbang/package-images.yaml); do
  export normalized_name=$(echo $pkg | sed 's/\([^[:blank:]]\)\([[:upper:]]\)/\1-\2/g; s/\(.*\)/\L\1/')
  if [ "$pkg" = "istioCRDs" ]; then
    export normalized_name="istio-crds"
  fi
  echo "::debug::normalized_name='${normalized_name}'"
  export yq_images=$(printf '(select(fi == 1) | .package-image-list.%s.images | ... head_comment="") as $img' "$pkg")
  echo "::debug::yq_images='${yq_images}'"
  export yq_update=$(printf '(select(fi == 0) | .components += ([{"name": "%s", "required": false, "images": $img}]))' "$normalized_name")
  echo "::debug::yq_update='${yq_update}'"
  echo "::debug::yq_together='$yq_images | $yq_update'"
  yq ea -i "$yq_images | $yq_update" zarf.yaml .direnv/bigbang/package-images.yaml
done
