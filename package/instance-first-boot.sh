#!/bin/bash

# Run when the instance first boots, and never again.

export PATH="/opt/puppetlabs/bin:$PATH"

# This is how you parse yaml in bash
fqdn=$(grep '^fqdn:' /var/lib/cloud/instance/user-data.txt | cut -f2- -d' ')
autosign_token=$(grep '^autosign_token:' /var/lib/cloud/instance/user-data.txt | cut -f2- -d' ')

# We get the FQDN from user-data directly because Debian relies on /etc/hosts
# for hostname -f. Chicken and egg.
hostname=$(hostname -s)
cloud_id=$(curl -sS http://169.254.169.254/latest/meta-data/instance-id | tr -d -)
cert_hostname=${hostname}-${cloud_id}
certname=${cert_hostname}.certs.puppet.net

cat <<EOF >/etc/hosts
127.0.1.1 $fqdn $hostname
127.0.1.2 $certname $cert_hostname

# This is the union of the standard Debian and CentOS hosts files
127.0.0.1 localhost localhost.localdomain localhost4 localhost4.localdomain4
::1 localhost localhost.localdomain localhost6 localhost6.localdomain6 ip6-localhost ip6-loopback

fe00::0 ip6-localnet
ff00::0 ip6-mcastprefix
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
ff02::3 ip6-allhosts
EOF

# Set up puppet
puppet config --section agent set certname "$certname"
puppet config --section agent set environment production

cat <<EOF >$(puppet config --section main print confdir)/csr_attributes.yaml
custom_attributes:
  challengePassword: "${autosign_token}"
extension_requests:
  pp_network: "$(hostname -d)"
  pp_cloudplatform: aws
  pp_instance_id: "$(curl -sS http://169.254.169.254/latest/meta-data/instance-id)"
  pp_zone: "$(curl -sS http://169.254.169.254/latest/meta-data/placement/availability-zone)"
  pp_region: "$(curl -sS http://169.254.169.254/latest/meta-data/placement/availability-zone | sed -e 's/.$//')"
EOF

puppet agent --test || true
