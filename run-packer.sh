#!/bin/bash

set -e

if [ -z "$1" ] ; then
  echo Must specify var file
  exit 1
fi

source $(command -v assume-role)
assume-role ops Administrator

export AUTOSIGN_TOKEN=$(./generate-autosign-token.sh)

packer build -var-file "$1" ami.json

echo Purging build nodes
ssh pe-mom1-prod.ops.puppetlabs.net \
  'sudo puppet query nodes "group=aws and function=template and stage=dev" \
  | xargs -r echo sudo puppet node purge'
