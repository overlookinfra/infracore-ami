#!/bin/sh

ssh pe-mom1-prod.ops.puppetlabs.net \
  sudo /opt/puppetlabs/puppet/bin/autosign generate --bare \
  "'/\Atemplate-aws-dev-[1-9][0-9]*-i[a-z0-9]*\.certs\.puppet\.net\Z/'"
