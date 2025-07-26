#!/usr/bin/env bash

set -u
set -o pipefail

export BB_VERSION="3.2.0"

rm -rf   .direnv/bigbang
mkdir -p .direnv/bigbang/charts

curl -s -L -o ./.direnv/bigbang/oci_package_list.txt https://umbrella-bigbang-releases.s3.us-gov-west-1.amazonaws.com/umbrella/$BB_VERSION/oci_package_list.txt

rm -rf components

yq -i '.packages= []' uds-bundle.yaml

for chart in $(cat .direnv/bigbang/oci_package_list.txt | sort | uniq); do
  export chart_name=$(echo $chart | sed -E 's#registry1.dso.mil/bigbang/##g; s#:.+##g')
  echo "::debug::chart_name='${chart_name}'"

  export chart_version=$(echo $chart | sed -E 's#.+:##g')
  echo "::debug::chart_version='${chart_version}'"

  mkdir -p components/$chart_name
  cp template/zarf.yaml components/$chart_name/zarf.yaml

  export yq_name=$(printf '.metadata.name = "%s"' "$chart_name")
  echo "::debug::yq_name='${yq_name}'"

  export yq_version=$(printf '.metadata.version = "%s"' "$chart_version")
  echo "::debug::yq_version='${yq_version}'"

  yq -i "$yq_name | $yq_version" components/$chart_name/zarf.yaml
  helm show chart oci://registry1.dso.mil/bigbang/$chart_name --version $chart_version 2>/dev/null >> .direnv/bigbang/charts/$chart_name.yaml

  export annotations="helm.sh/images"
  if [ $(yq e '.annotations | has("images")' .direnv/bigbang/charts/$chart_name.yaml) = "true" ]; then
    export annotations="images"
  fi

  export yq_images=$(printf '(select(fi == 1) | .annotations."%s" | from_yaml | [.[].image] | sort) as $img' "$annotations")
  echo "::debug::yq_images='${yq_images}'"

  export yq_update=$(printf '(select(fi == 0) | .components = ([{"name": "%s", "required": true, "images": (["%s"] + $img)}]))' "$chart_name" "$chart")
  echo "::debug::yq_update='${yq_update}'"

  yq ea -i "$yq_images | $yq_update" components/$chart_name/zarf.yaml .direnv/bigbang/charts/$chart_name.yaml

  export yq_uds_component=$(printf '(.packages += ([{"name": "%s", "repository": "ghcr.io/colonel-byte/zarf/%s", "ref": "%s"}]))' "$chart_name" "$chart_name" "$chart_version")
  echo "::debug::yq_update='${yq_uds_component}'"

  yq -i "$yq_uds_component" uds-bundle.yaml
  yq -i '.packages[-1].publicKey alias = "public"' uds-bundle.yaml
done
