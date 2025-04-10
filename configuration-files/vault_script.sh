#!/bin/sh

echo $conf | base64 -d > /vault/vault-conf.hcl
echo $license | base64 -d > /vault/license.hclic
/vault/vault server -config=/vault/vault-conf.hcl
