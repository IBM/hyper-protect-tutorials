#!/bin/sh

# Attestation
cat /var/hyperprotect/se-checksums.txt

# PKCS11 files
echo $grep11 | base64 -d > /etc/ep11client/grep11client.yaml
echo $ca | base64 -d > /etc/ep11client/certs/grep11-ca.pem
echo $client | base64 -d > /etc/ep11client/certs/grep11-client.pem
echo $key | base64 -d > /etc/ep11client/certs/grep11-client.key

# Vault files
echo $conf | base64 -d > /vault/vault-conf.hcl
echo $license | base64 -d > /vault/license.hclic
/vault/vault server -config=/vault/vault-conf.hcl
