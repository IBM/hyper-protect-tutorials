#!/bin/bash

CONTRACT_KEY="/data/hpcr/config/certs/ibm-hyper-protect-container-runtime-24.11.0-encrypt.crt"

# Workload section
WORKLOAD="./workload.yml"
PASSWORD="$(openssl rand 32 | base64 -w0)"
ENCRYPTED_W_PASSWORD="$(echo -n "$PASSWORD" | base64 -d | openssl rsautl -encrypt -inkey $CONTRACT_KEY -certin | base64 -w0 )"
ENCRYPTED_WORKLOAD="$(echo -n "$PASSWORD" | base64 -d | openssl enc -aes-256-cbc -pbkdf2 -pass stdin -in "$WORKLOAD" | base64 -w0)"
echo "workload: \"hyper-protect-basic.${ENCRYPTED_W_PASSWORD}.${ENCRYPTED_WORKLOAD}\"" > user-data
# For attestation of the workload section 
echo "`echo "hyper-protect-basic.${ENCRYPTED_W_PASSWORD}.${ENCRYPTED_WORKLOAD}" | tr -d "\n\r" | sha256sum` contract:workload" > gen-se-checksums.txt

# Env section
ENV="./env-syslog-signingKey.yml"
PASSWORD="$(openssl rand 32 | base64 -w0)"
ENCRYPTED_E_PASSWORD="$(echo -n "$PASSWORD" | base64 -d | openssl rsautl -encrypt -inkey $CONTRACT_KEY  -certin | base64 -w0)"
ENCRYPTED_ENV="$(echo -n "$PASSWORD" | base64 -d | openssl enc -aes-256-cbc -pbkdf2 -pass stdin -in "$ENV" | base64 -w0)"
echo "env: \"hyper-protect-basic.${ENCRYPTED_E_PASSWORD}.${ENCRYPTED_ENV}\"" >> user-data
# For attestation of the env section
echo "`echo "hyper-protect-basic.${ENCRYPTED_E_PASSWORD}.${ENCRYPTED_ENV}" | tr -d "\n\r" | sha256sum` contract:env" >> gen-se-checksums.txt

# Attestation Public Key
ATTESTATION="./public_attestation.pem"
PASSWORD="$(openssl rand 32 | base64 -w0)"
ENCRYPTED_A_PASSWORD="$(echo -n "$PASSWORD" | base64 -d | openssl rsautl -encrypt -inkey $CONTRACT_KEY  -certin | base64 -w0)"
ENCRYPTED_ATTESTATION="$(echo -n "$PASSWORD" | base64 -d | openssl enc -aes-256-cbc -pbkdf2 -pass stdin -in "$ATTESTATION" | base64 -w0)"
echo "attestationPublicKey: \"hyper-protect-basic.${ENCRYPTED_A_PASSWORD}.${ENCRYPTED_ATTESTATION}\"" >> user-data
# For attestation of the Attestation section
echo "`echo "hyper-protect-basic.${ENCRYPTED_A_PASSWORD}.${ENCRYPTED_ATTESTATION}" | tr -d "\n\r" | sha256sum` contract:attestationPublicKey" >> gen-se-checksums.txt

# Workload Signature
echo "hyper-protect-basic.${ENCRYPTED_W_PASSWORD}.${ENCRYPTED_WORKLOAD}hyper-protect-basic.${ENCRYPTED_E_PASSWORD}.${ENCRYPTED_ENV}" > contract.txt
#echo "envWorkloadSignature: `echo $(cat contract.txt | tr -d "\n\r" | openssl dgst -sha256 -sign private_signer.pem | openssl enc -base64) | tr -d ' '`" >> user-data
SIGNATURE=`echo $(echo "hyper-protect-basic.${ENCRYPTED_W_PASSWORD}.${ENCRYPTED_WORKLOAD}hyper-protect-basic.${ENCRYPTED_E_PASSWORD}.${ENCRYPTED_ENV}" | tr -d "\n\r" | openssl dgst -sha256 -sign private_signer.pem | openssl enc -base64) | tr -d ' '`
#SIGNATURE=`echo $(cat contract.txt | tr -d "\n\r" | openssl dgst -sha256 -sign private_signer.pem | openssl enc -base64) | tr -d ' '`
echo "envWorkloadSignature: ${SIGNATURE}" >> user-data
# For attestation of the Attestation section
echo "`echo "${SIGNATURE}" | tr -d "\n\r" | sha256sum` contract:envWorkloadSignature" >> gen-se-checksums.txt
