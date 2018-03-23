#!/bin/bash

if [ -z "$autosign_token" ] ; then
  echo "autosign_token environment variable must be set"
  exit 1
fi

set -ex
set -o pipefail

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/opt/puppetlabs/bin

if command -v apt-get >/dev/null ; then
  apt-get update
  export DEBIAN_FRONTEND=noninteractive
  apt-get -o Dpkg::Options::="--force-confnew" --assume-yes dist-upgrade
  apt-get -o Dpkg::Options::="--force-confnew" --assume-yes install curl lsb-release
elif command -v yum >/dev/null ; then
  yum -y update
fi

# 169.254.169.254 is the AWS EC2 metadata service
cloud_id=$(curl -sS http://169.254.169.254/latest/meta-data/instance-id | tr -d -)

hostname=aws-template-dev-1
domain=ops.puppetlabs.net
puppet_environment=production
fqdn=${hostname}.${domain}
cert_hostname=${hostname}-${cloud_id}
certname=${cert_hostname}.certs.puppet.net

hostname $fqdn

# Install Puppet, but don't run it
curl -sSk https://puppetca.ops.puppetlabs.net:8140/packages/current/install.bash \
  | bash -s -- \
    "agent:certname=$certname" \
    "agent:environment=$puppet_environment" \
    --puppet-service-ensure stopped \
    --puppet-service-enable false

cat <<EOF >$(puppet config --section main print confdir)/csr_attributes.yaml
custom_attributes:
  challengePassword: "${autosign_token}"
extension_requests:
  pp_network: "$domain"
  pp_cloudplatform: aws
  pp_instance_id: "$(curl -sS http://169.254.169.254/latest/meta-data/instance-id)"
  pp_zone: "$(curl -sS http://169.254.169.254/latest/meta-data/placement/availability-zone)"
  pp_region: "$(curl -sS http://169.254.169.254/latest/meta-data/placement/availability-zone | sed -e 's/.$//')"
EOF

# Run Puppet twice to ensure it coallesces
puppet agent --test --waitforcert 15 --server puppetca.ops.puppetlabs.net || true
puppet agent --test || true

# Validate that the server works
if ! ls -1 /home | fgrep -qvx admin ; then
  echo "No users other than admin in /home"
  exit 1
fi

# Strip old cert and autosign token
rm -f "$(puppet config --section main print confdir)/csr_attributes.yaml"
rm -rf "$(puppet config --section main print ssldir)"
puppet config --section main delete certname
