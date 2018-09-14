#!/bin/bash

set -e

if [ -z "$1" ] ; then
  echo Must specify var file
  exit 1
fi

source $(command -v assume-role)

consul_kv="https://consul.service.consul.puppet.net:8500/v1/kv"

mkdir -p logs

for release in "$@" ; do
  assume-role ops Administrator
  export AUTOSIGN_TOKEN=$(./generate-autosign-token.sh)
  log_file=logs/$(date +%Y-%m-%d_%H:%M:%S)_$(basename $release .json).log
  packer build -var-file "$release" ami.json | tee "$log_file"
  echo

  # Get the AMI ID produced
  release_code=$(jq -r '"\(.distro)\(.distro_version)"' < "$release")

  echo Setting AMI information for $release_code:
  ami=$(grep '^us-west-2: ami-' "$log_file" | cut -f2 -d' ' | tr -d '\n')
  aws --region us-west-2 ec2 describe-images --image-ids "${ami}" \
    | jq -r '.Images[]' \
    | curl -ksST - "${consul_kv}/infracore/ami/us-west-2/$release_code"
  echo
done

echo Purging build nodes
ssh pe-mom1-prod.ops.puppetlabs.net \
  'sudo puppet query nodes "group=template and function=aws and stage=dev" \
  | xargs -r sudo puppet node purge'
