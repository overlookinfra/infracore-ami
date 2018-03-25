#!/bin/bash

set -e

if [ -z "$1" ] ; then
  echo Must specify var file
  exit 1
fi

source $(command -v assume-role)

for release in "$@" ; do
  assume-role ops Administrator
  export AUTOSIGN_TOKEN=$(./generate-autosign-token.sh)
  packer build -var-file "$release" ami.json
done

echo Purging build nodes
ssh pe-mom1-prod.ops.puppetlabs.net \
  'sudo puppet query nodes "group=template and function=aws and stage=dev" \
  | xargs -r sudo puppet node purge'
