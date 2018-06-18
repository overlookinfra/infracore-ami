#!/bin/bash

# Run when the instance first boots, and never again.
echo Starting instance-first-boot.sh

export PATH="/opt/puppetlabs/bin:$PATH"

# This is how you parse yaml in bash
fqdn=$(grep '^fqdn:' /var/lib/cloud/instance/user-data.txt | cut -f2- -d' ')
autosign_token=$(grep '^autosign_token:' /var/lib/cloud/instance/user-data.txt | cut -f2- -d' ')
environment=$(grep '^environment:' /var/lib/cloud/instance/user-data.txt | cut -f2- -d' ')

echo Got user-data fqdn: $fqdn
echo Got user-data autosign_token: $autosign_token
echo Got user-data environment: $environment

# Default environment is production
environment=${environment:-production}
echo Using environment: $environment

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

sed -i -e "s/^send host-name .*;/send host-name ${hostname};/" /etc/dhcp/dhclient.conf

cat <<EOF >/etc/cloud/cloud.cfg
preserve_hostname: true
manage_etc_hosts: false
EOF

# This will fail if the correct IAM profile is not set
echo Attempting to create: ${certname}. 3600 IN A $(hostname -I)
puppet resource route53_a_record "${certname}." \
  ensure=present \
  zone='certs.puppet.net.' \
  ttl=3600 \
  values="$(hostname -I)"

# Set up puppet
echo Configuring puppet.conf:
puppet config --section agent set certname "$certname"
puppet config --section agent set environment "$environment"
cat /etc/puppetlabs/puppet/puppet.conf

echo Installing autosign token
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

echo Running puppet
puppet agent --test --waitforcert 15

echo Finished instance-first-boot.sh
