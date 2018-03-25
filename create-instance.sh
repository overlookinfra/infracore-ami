#!/bin/bash

ami="$1"
hostname="$2"

if [ -z "$hostname" ] ; then
  echo usage: $o ami hostname
fi

autosign_token=$(ssh pe-mom1-prod.ops.puppetlabs.net sudo /opt/puppetlabs/puppet/bin/autosign generate -b "'/\A${hostname}-i[a-z0-9]*\.certs\.puppet\.net\Z/'")

logfile=$(mktemp)

aws --region us-west-2 ec2 run-instances \
  --image-id "$ami" \
  --count 1 \
  --instance-type t2.small \
  --subnet-id subnet-5d2df02a \
  --security-group-ids sg-da8c9ebe \
  --iam-instance-profile Name=ec2-base \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${hostname}},{Key=lifetime,Value=1h}]" \
  --user-data "#cloud-config
fqdn: ${hostname}.ops.puppetlabs.net
autosign_token: ${autosign_token}
environment: aws_amitest
" | tee "$logfile" | jq .

echo
echo Hostnames:
<"$logfile" jq -r '.Instances[].InstanceId' \
  | sed -e "s/^i-/${hostname}-i/" -e 's/$/.certs.puppet.net/'

rm "$logfile"
