#!/bin/bash

CONTRACT_KEY="/data/hpcr/config/certs/ibm-hyper-protect-container-runtime-24.11.0-encrypt.crt"
WORKLOAD="./workload.yml"
PASSWORD="$(openssl rand 32 | base64 -w0)"
ENCRYPTED_PASSWORD="$(echo -n "$PASSWORD" | base64 -d | openssl rsautl -encrypt -inkey $CONTRACT_KEY -certin | base64 -w0 )"
ENCRYPTED_WORKLOAD="$(echo -n "$PASSWORD" | base64 -d | openssl enc -aes-256-cbc -pbkdf2 -pass stdin -in "$WORKLOAD" | base64 -w0)"
echo "workload: \"hyper-protect-basic.${ENCRYPTED_PASSWORD}.${ENCRYPTED_WORKLOAD}\"" > user-data
# For attestation of the workload section 
echo "`echo "hyper-protect-basic.${ENCRYPTED_PASSWORD}.${ENCRYPTED_WORKLOAD}" | tr -d "\n\r" | sha256sum` contract:workload" > se-checksums.txt


#ENV="./env.yml"
ENV="./env-syslog.yml"
#ENV="./env-logdna-tor.yml"
PASSWORD="$(openssl rand 32 | base64 -w0)"
ENCRYPTED_PASSWORD="$(echo -n "$PASSWORD" | base64 -d | openssl rsautl -encrypt -inkey $CONTRACT_KEY  -certin | base64 -w0)"
ENCRYPTED_ENV="$(echo -n "$PASSWORD" | base64 -d | openssl enc -aes-256-cbc -pbkdf2 -pass stdin -in "$ENV" | base64 -w0)"
echo "env: \"hyper-protect-basic.${ENCRYPTED_PASSWORD}.${ENCRYPTED_ENV}\"" >> user-data
# For attestation of the env section
echo "`echo "hyper-protect-basic.${ENCRYPTED_PASSWORD}.${ENCRYPTED_ENV}" | tr -d "\n\r" | sha256sum` contract:env" >> se-checksums.txt
