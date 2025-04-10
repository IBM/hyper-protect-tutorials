# How to use Attestation and Workload Signature to protect your application in Hyper Protect Virtual Servers

The purpuse of this tutorial is to provide a better understanding of the Hyper Protect Virtual Servers (HPVS) anti-tampering methods:

- [Attestation](https://github.ibm.com/ZaaS/zcat-assets/blob/main/tutorials/HPVS-AttestationContractSignature.md#attestation)
- [Contract Signature](https://github.ibm.com/ZaaS/zcat-assets/blob/main/tutorials/HPVS-AttestationContractSignature.md#contract-signature)

The following are pre-requisites:
 - Working HPVS contract that deploys a workload, we'll be using the one developed in the [link to Vault tutorial]
 - It's assumed the contract is encrypted following the procedures in the [official documentation](https://www.ibm.com/docs/en/hpvs/2.2.x?topic=servers-about-contract#hpcr_contract_encrypt)

## Attestation
The topic of attestation for on-prem servers is documented [here](https://www.ibm.com/docs/en/hpvs/2.2.x?topic=servers-attestation).

On HPVS attestation is a way to see and verify the SHA256SUM of all the components that build up your application stack:
- The original base image
- The root partition at the moment of the first boot
- The root partition at build time
- The cloud initialization options

The flow of attestation is exemplified in this VERY complicated diagram:
![image](https://www.ibm.com/docs/en/SSHPMH_2.2.x/images/vsi_se_attestationrecord.png)

The KEY take away here is that the role responsible for doing this is the AUDITOR, henceforth this is the ONLY role in a zero trust system that should have access to the private and public key pair capable of encrypting and decrypting the attestation information.

A MALICIOUS admin could quite easily find out what the correct SHA256SUM of the workload, env and other sections of the contract (also referred to as the cloud initialization options) as they have access to the contract being the role responsible to deployment. HOWEVER, they have access to an encrypted contract that can ONLY be decrypted by HPCR an the public key that HPCR will use to encrypt the attestation information is present in the `attestationPublicKey:` part of the contract. When this is encrypted the ADMIN can not know what it contains. If this section is not present or not encrypted a malicious admin could redeploy a different application that looks the same and provides the expected attestation information, which has in fact been faked at the information level.

Let's now see how attestation works in practice.

### Changes in the contract
You must mount the internal attestation directory:
```
 volumeMounts:
     - name: attestation
       readOnly: true
       mountPath: /var/hyperprotect:Z,U
...
 volumes:
     - name: attestation
       hostPath:
         path: /var/hyperprotect
         type: Directory 
```
You can view the full contract template used for the workload here: [workload.yaml](HPVS-AttestationSignature-files/workload.yaml)


### Accessing the Attestation data
You workload must make this available to you either by webserver/API or dump it in the logs so that it can be retrieved at boot. In this case we chose dumping it the logs as the workload does not have a native webserver, so the following line was included in the script that runs the workload:
```
cat /var/hyperprotect/se-checksums.txt
```

You can view the full script here [vault-script.sh](HPVS-AttestationSignature-files/vault-script.sh)

### Encrypting the Contract and Calculating Attestation Checksums
The attestation checksum data is basically the sha256sum of the contract elements. So for the workload checksum is the sha256sum of `hyper-protect-basic.${ENCRYPTED_PASSWORD}.${ENCRYPTED_WORKLOAD}` without any end of line characters:
```
echo "hyper-protect-basic.${ENCRYPTED_PASSWORD}.${ENCRYPTED_WORKLOAD}" | tr -d "\n\r" | sha256sum
```
I chose to use the contract encryption script, which can be viewed here [`encrypt_contract.sh`](HPVS-AttestationSignature-files/encrypt_contract.sh), to automatically output the checksums to a file so these values could be compared to the actual data which is made available by the system.

The resulting local `se-checksums.txt` matched the logs:
```
680e49fa9deae730d16eb0ba067ec2a66b18540ffc735665e54535450a9e5fc8  - contract:workload
ef192311e1c19512774498ef5d6c1afd0709da7d4675de65e67d87014c57616f  - contract:env
```
### Results in logs:
When the workload comes up we see the following:
```
Mar 24 10:52:29 zrhpkoso zcatvault-zcatvault[854262]: 24.11.0
Mar 24 10:52:29 zrhpkoso zcatvault-zcatvault[854262]: Machine Type/Plant/Serial: 3931/02/8A3B8
Mar 24 10:52:29 zrhpkoso zcatvault-zcatvault[854262]: Image age: 123 days since creation.
Mar 24 10:52:29 zrhpkoso zcatvault-zcatvault[854262]: ad65a3820d4a233c84e6d201ce537b8020435ccefe26682809da5ef9b176b8ae root.tar.gz
Mar 24 10:52:29 zrhpkoso zcatvault-zcatvault[854262]: 080f817231fe4bc40021d24e20af9f1135a36711047212f9374664b86ab406ac baseimage
Mar 24 10:52:29 zrhpkoso zcatvault-zcatvault[854262]: b69ddd6fa0a4474a097d1fbb3a8e61158e00d3036a246964792bdfb4bdc72096 /dev/disk/by-label/cidata
Mar 24 10:52:29 zrhpkoso zcatvault-zcatvault[854262]: c7337f60d493b4b146c27ad1213b4b6fd35bb88c9905869002b47fbae16f4e52 cidata/meta-data
Mar 24 10:52:29 zrhpkoso zcatvault-zcatvault[854262]: ac6f89514970d644aa306cbee0ff51a5a38a64858faf1362544ac3d382511a1f cidata/user-data
Mar 24 10:52:29 zrhpkoso zcatvault-zcatvault[854262]: 13891bfb004315f8fd84d1b3d06833fe251f7749010e1c14833522bd57a950c4 cidata/vendor-data
Mar 24 10:52:29 zrhpkoso zcatvault-zcatvault[854262]: 680e49fa9deae730d16eb0ba067ec2a66b18540ffc735665e54535450a9e5fc8 contract:workload 
Mar 24 10:52:29 zrhpkoso zcatvault-zcatvault[854262]: ef192311e1c19512774498ef5d6c1afd0709da7d4675de65e67d87014c57616f contract:env 
```
The attestation matches and we now know the contract on the system is what we encrypted... 

### Encrypting the Attestation Records
However as discussed above the open records can be 'faked' so we'll now assume the role of the auditor and encrypt the attestation record. Note that since we're using encrypted records we need to change the workload script to output the `se-checksums.txt.enc` to the logs. To make it easier to identify I've also included the tag `***BEGIN se-checksums.txt.enc CAT DUMP***` to be outputted just before the encrypted output and a corresponding one after.

1. Creating RSA key pair:
```
[root@zrhpgp11 vault-tutorial-onprem]# openssl genrsa -aes128 -passout pass:zcatattestation -out private_attestation.pem 4096
Generating RSA private key, 4096 bit long modulus (2 primes)
...............................................................................................................................................................................++++
......................++++
e is 65537 (0x010001)
[root@zrhpgp11 vault-tutorial-onprem]# openssl rsa -in private_attestation.pem -passin pass:zcatattestation -pubout -out public_attestation.pem
writing RSA key
```
2. Modify `encrypt_contract.sh` to [`encrypt_contract_att.sh`](HPVS-AttestationSignature-files/encrypt_contract_att.sh) (click to view) to include the attestation key in the contract, this now results in the following `se-checksums.txt`:
``` 
8b58c2a43d62f44b4362a88a37729bf8fbe32f890b8bad84113f98cd01c2861d  - contract:workload
dca72747c131d42f308c591c367a72b9613aa9d7f6988d04cb9f2bf661fe67e7  - contract:env
f49b94c7fd898b74e2efda21b06cd8054926ebfe24a4f714b5fc1ef9b6136c74  - contract:attestationPublicKey
```

### Results in the logs for :
```
Mar 25 05:56:45 zrhpkoso zcatvault-zcatvault[854262]: ***BEGIN se-checksums.txt.enc CAT DUMP***
Mar 25 05:56:45 zrhpkoso zcatvault-zcatvault[854262]: hyper-protect-basic.MJ2RWnFy5RG0n11fsu1OFAEaremxbTrLhLdoJ17ZWUDfQ9/QWW6okcnsPmw4bxXfCZ+FZgqo78DcdnWaktRMeGv22qd6SNS+e7ixeO0kjwN6gIULe+fFIx8D+qrUpgzH3yhARQc7hCr4K76Zn+HgmkGJNpC8verIEYPxgdwFmI6ZD7pDin6+I+RbM8Ref/DCcTuTK+RSpI5W6azHqxA5j8nmNOzBal1Qyd2VIWeAm7GZGR4IOk48h+HMhiTDqxhMZe+JK99AJDpK91y4J25sEvunlmAgeSby2OnMx6dh3o35beoNmaV4btbVZ7f3Mb266TsTn0bF3Vi6xXthYhzXkB0L2r6Edwpdf6C578+uo6UfKzOlNLL+3icq3RVC3aEbD0gTAHtEbu/6DwHfcb3Fw9C4xdKuDKD5ovRmjSiKuJaF7i1Zq2uYdtps/vNEldSvtse1gHAPD2H9t9QkfUgzKKbJli3rlZ3aMiOhDZq3nJN6HpmZ5t2uTUkvZLFNMN+2NeQkBhu4sV05Hto63GwOv0mHCWQ81ssfBXQqf9PUbDmR4ZI0924oq0P0pznpTJzDmV69MWTfDYNPnQRDNlSkf7FffjjXGL1b3UaFFHb0/Qj7JiYqzcUDV1Lkhtt73A2H1Y5mBBQ04YqQw+fgjGfL+qR58HKdxYtRoZJahDLtcZY=.U2FsdGVkX1/oNKFSJ0VTPXyjHcCs+Y4be2QM6pjmYqSo66yegA6SLpp2cYa3kkBa7rreEanBDnT13M7zsUnkvHW8bEo4oCA8Rkyvgf2UZx1BXPNbrXhLRRjoPjhOYk/+DV3Y0KeAaJ3fdTpJdB7s1gez2lzC/+hOt8gzNllSISYUIV6Ug7wG5kXyygLxIJAXKaDTT47z24+rmI+PrA7xFkVKv5GNiq4fQU6IIGdK0d8Kf9egS7xIm4wrh7N/I73q40J9CMvX2GwcDY7n66kOzM6f+4SoGwsxhVZ6d4autYLs+J5W+VG8wfEVra+shFc73LDRhuLbxQBX5nlHTgd6RmTeQVLtnearWtcUi/G2vRo1uIyyQU4ys0CaBEZ3msZS1a1IJ3x233/LlVZ39Dn0xotse0J1KNKRwBEKE1idRi8imahPCv8Y8gAzj1sXsl1LvzwQ3f0odLwvmY6+t5NAiUv3/+ztB4fK8ah7i/AoF1coqpEwZU04OUIwvhTXuASjnH3rEl6U1QuuSgdrU4hQ5qhNg5pGO2EMQjr3x0TndAvzrzKR8nROBvGoVdMXeaAdmXvepl/cjDNv9AOr2UNI9ZOAbAQ/h5TpXxDVWyAT1jMvQ1hlfgRoJF7RLxvfmCIAanLuIq3EWxCUpbqNEm7KhkdZoXIDOopFPLBiXYZVk5ZWq1Z3/5lf6bN3wG3qxA+2ibsT4ET0cpf4yKEwUm32cglIzu135AY2lgbq4mb0YPLQYQFQBq95oMiOTW0WecGHzzxlZiJ9FsVEHWnuoi6aDtLgljsBel87h3F+afCQwt4onRZxYZWJ7wlELAP6sJFVWyb7/wfT52gApKuAizKh62DsZzcIe/iNVZgdvN0btrJzL1rYRgasUSZx3pc+F+n5Ci168ChRwvRGOil3AgFSduBz64KXmmqvQlpp6dYaJItvU+ip/Qcs6f2KyCptdEU+llOz1BBkvmUY5mQcjVqXodMBgy52c/QEJDF1prn/7zcc6u8/vYbhlf7mOXICLl4KmfTjx/VtNfieVEX52EBB6OLIHsga7pC7Lvd+tqTs5GVOKWGv5NPZU05181p1hl0rRJxt36LMi9ns22x1uyPwALb0rCeuh2JZrx0ANI20VXEDzmvGpLj9QGwgkfZ7VGg7***END se-checksums.txt.enc CAT DUMP***
```
### Decrypting the Attestation Data
1. Save the above information `hyper-protect-basic.MJ2R...` as a file called `se-checksums.txt.enc`

2. Use the documented [`decrypt-attestation.sh`](HPVS-AttestationSignature-files/decrypt-attestation.sh) script to decrypt with private keyfile (note that this script will overwrite the `se-checksums.txt` generated by the encrypt_contract.sh script, this can easily be solved by changing the output file in either script to a different name):
```
[root@zrhpgp11 vault-tutorial-onprem]# ./decrypt-attestation.sh private_attestation.pem se-checksums.txt.enc
Enter pass phrase for private_attestation.pem:
[root@zrhpgp11 vault-tutorial-onprem]# cat se-checksums.txt
24.11.0
Machine Type/Plant/Serial: 3931/02/8A3B8
Image age: 124 days since creation.
ad65a3820d4a233c84e6d201ce537b8020435ccefe26682809da5ef9b176b8ae root.tar.gz
080f817231fe4bc40021d24e20af9f1135a36711047212f9374664b86ab406ac baseimage
8014fee239f8ece9fa197b0b83028e1de9397f4ab2e6be1fb721ad9f18c80145 /dev/disk/by-label/cidata
c7337f60d493b4b146c27ad1213b4b6fd35bb88c9905869002b47fbae16f4e52 cidata/meta-data
c98bb06ed4be07064d704918f5e220d0032805824d538fc061c2754686986660 cidata/user-data
13891bfb004315f8fd84d1b3d06833fe251f7749010e1c14833522bd57a950c4 cidata/vendor-data
dca72747c131d42f308c591c367a72b9613aa9d7f6988d04cb9f2bf661fe67e7 contract:env 
f49b94c7fd898b74e2efda21b06cd8054926ebfe24a4f714b5fc1ef9b6136c74 contract:attestationPublicKey 
8b58c2a43d62f44b4362a88a37729bf8fbe32f890b8bad84113f98cd01c2861d contract:workload 
```
We have matching attestation records!

Also **NOTE THAT** there should and needs to be separation of duties:
Part 1 - the creation of key pair must be done by the **AUDITOR**, for reasons discussed above
Part 2 - **MUST** be done in separate steps, that is:
- Workload owner does the workload section encryption and provides the value to the ADMIN: `workload: "hyper-protect-basic.tc/xVkDUY9bzvjsBlRok/o9ZbJEXuX9ZdqXwHe5tXKOWRzl0nnZWw3jOeAQSXCvdeN1bfWD8A1QeNJf+SqiRsWNatk3c1BoGjqK5mqrf+BkUARtvH4JkDTrr59STCOXnWlr4O6/61bA1DUgKjFHh9..."`
And provides the checksum to the AUDITOR: `8b58c2a43d62f44b4362a88a37729bf8fbe32f890b8bad84113f98cd01c2861d  - contract:workload`
- Env owner (ADMIN) does the env section encryption and provides the checksum to the AUDITOR: `dca72747c131d42f308c591c367a72b9613aa9d7f6988d04cb9f2bf661fe67e7  - contract:env`
- Lastly, the AUDITOR encrypts the public key and gives the value to the ADMIN to be placed  into the `attestationPublicKey: "hyper-protect-basic.GAmsw4oFY1LizjqcwvzrK4gzy1GbnUd+EU1w+S2..."`

## Contract Signature
The contract signature is another option anti-tampering method described/documented [here](https://www.ibm.com/docs/en/hpvs/2.2.x?topic=servers-about-contract#hpcr_contract_sign).

In this method the workload owner (or the auditor) has access the unique ability to sign the contract using a private key or certificate, which has a public pair known to all roles and present in the environment section of the contract as the `signingKey:`.

It's recommended that the workload owner be the one that provides this signature as this allows them to protect the workload and make sure it's the correct workload that is deployed.

Technically, unless the malicious actor has access to the private key and can provide a valid signature, it is impossible for anyone else to tamper with the workload, as the signature would not be valid and HPCR would not deploy the workload.

The process should be:
1. Contract signer (possibly workload owner) generates key or certificate pairs
2. Signing Key (public key/cert) must be given to ADMIN to be put into env section
3. Admin then gives encrypted env section to contract signer, who combines this with the encrypted workload section of the contract (into a `contract.txt` file) and produces a signature
4. Signature value is given back to admin to deploy contract

Please note that if you use certificates you can enable contract expiry through the expiration of the certs, for simplicity we'll use keys below, but the use of certs is documented on the official link.

We'll use the above contract that already has attestation and build on that for a complete solution!

### 1. Generating Key Pairs:
```
[root@zrhpgp11 vault-tutorial-onprem]# openssl genrsa -aes128 -passout pass:zcatsigner  -out private_signer.pem 4096
Generating RSA private key, 4096 bit long modulus (2 primes)
....++++
.......................................................................................................++++
e is 65537 (0x010001)
[root@zrhpgp11 vault-tutorial-onprem]# openssl rsa -in private_signer.pem -passin pass:zcatsigner -pubout -out public_signer.pem
writing RSA key
```
### 2. Generating the Signing Key:
```
[root@zrhpgp11 vault-tutorial-onprem]# cat public_signer.pem | base64 -w 0
LS0tLS1CRUdJTiBQVUJMSUMgS0VZLS0tLS0KTUlJQ0lqQU5CZ2txaGtpRzl3MEJBUUVGQUFPQ0FnOEFNSUlDQ2dLQ0FnRUEwT00zNFREUFY0VnhQTFJEN2t4SwpMeGNnQkpIWDhyakprb1J3aUNiVU16ZnNPVnBLM0xybEQxc2hxRzJlTkxTUEhpc3ZNRUNranU2cTRVand6NjdxClhmaTVUdEFzUzJpOGFBa0g5cUt0L290MXJCQWVtWUl4Y3I1LysyaEkwb2dNRm9SZWJDSTlWakd2bDJyc3lUWkYKUDJ4eGw4RE0rRVhneXJLV3VJTWtXZ3pKR0JibUVvR2pVMmNqRXpEWHdwbXpZcDF1WHQxcmluVkhxd2NPSWtZSQpTZGZZMXhRUFlhcEhvSldvRjZZWVF3L2hYTE50ODYxUjMycFpHbFZkNmxYRVJWZEhVclNRYVpFemY3dU1WM1lFClF0QmNXTUhJUjAyZ0wwRjg1WHVtQlkvNkc4MzErRzZ1TjBwRkZNb0RQS3BrZ0hLQU1xU2pLUk02aXBHVmxaRjMKZ2xCZlZvL21wL2lOTm1YQzJjMWhaN04zUlNneHVjK3hoVkZ0eSs3ZERGMGJtVDRhVllGT3ZNWVI2WmU1YnliVAp6SFpaNTNZTmtQRUthQ2JQL0RGYmh6SFU0dzQ3WmorbWlhbG51bFlQVTRyTmpHV2M3L0IzcFpmelFCK1UrVEg2CnBpODVQT2xQT2ZKUUZzdHI4cm5YUHUwQmVtRWFmMlVwNFh5MTRWTW5VZUNKTVpwRkVGMHVrYXhWQzIxdkNZeFMKUUREQnB4VUZMVnd0b2N5K2lKNkhya25OejJwZ09Tck11UTBHWDV0RTdrczV0SThna3QzcENZbjJNZlgvQmh2KwpnZEo2bDVFK0hlY3pueEY5RDJZNXZKRENZWkpEaFl0N3dsTmF0MGJaZXMyMFRNZnlrdytTNzBkWVdGUzhFZnhnCi9uVEFGemhiVGJTTmUzcWhWbE5mKzlFQ0F3RUFBUT09Ci0tLS0tRU5EIFBVQkxJQyBLRVktLS0tLQo=
```
### 3. Adding the Signing Key to the Contract (Env section):
```
type: env
logging:
  *** Redacted ***
volumes:
  test:
    seed: "testing"
signingKey: LS0tLS1CRUdJTiBQVUJMSUMgS0VZLS0tLS0KTUlJQ0lqQU5CZ2txaGtpRzl3MEJBUUVGQUFPQ0FnOEFNSUlDQ2dLQ0FnRUEwT00zNFREUFY0VnhQTFJEN2t4SwpMeGNnQkpIWDhyakprb1J3aUNiVU16ZnNPVnBLM0xybEQxc2hxRzJlTkxTUEhpc3ZNRUNranU2cTRVand6NjdxClhmaTVUdEFzUzJpOGFBa0g5cUt0L290MXJCQWVtWUl4Y3I1LysyaEkwb2dNRm9SZWJDSTlWakd2bDJyc3lUWkYKUDJ4eGw4RE0rRVhneXJLV3VJTWtXZ3pKR0JibUVvR2pVMmNqRXpEWHdwbXpZcDF1WHQxcmluVkhxd2NPSWtZSQpTZGZZMXhRUFlhcEhvSldvRjZZWVF3L2hYTE50ODYxUjMycFpHbFZkNmxYRVJWZEhVclNRYVpFemY3dU1WM1lFClF0QmNXTUhJUjAyZ0wwRjg1WHVtQlkvNkc4MzErRzZ1TjBwRkZNb0RQS3BrZ0hLQU1xU2pLUk02aXBHVmxaRjMKZ2xCZlZvL21wL2lOTm1YQzJjMWhaN04zUlNneHVjK3hoVkZ0eSs3ZERGMGJtVDRhVllGT3ZNWVI2WmU1YnliVAp6SFpaNTNZTmtQRUthQ2JQL0RGYmh6SFU0dzQ3WmorbWlhbG51bFlQVTRyTmpHV2M3L0IzcFpmelFCK1UrVEg2CnBpODVQT2xQT2ZKUUZzdHI4cm5YUHUwQmVtRWFmMlVwNFh5MTRWTW5VZUNKTVpwRkVGMHVrYXhWQzIxdkNZeFMKUUREQnB4VUZMVnd0b2N5K2lKNkhya25OejJwZ09Tck11UTBHWDV0RTdrczV0SThna3QzcENZbjJNZlgvQmh2KwpnZEo2bDVFK0hlY3pueEY5RDJZNXZKRENZWkpEaFl0N3dsTmF0MGJaZXMyMFRNZnlrdytTNzBkWVdGUzhFZnhnCi9uVEFGemhiVGJTTmUzcWhWbE5mKzlFQ0F3RUFBUT09Ci0tLS0tRU5EIFBVQkxJQyBLRVktLS0tLQo=
```
### 4. Modified `encrypt_contract_att.sh` to [encrypt_contract_att_sign.sh](HPVS-AttestationSignature-files/encrypt_contract_att_sign.sh), to add the signature to the contract (here I'm saving the checksum at contract creation time to `gen-se-checksums.txt`). The signature consists of both the encrypted workload and env section signed by the private key/certificate:
Logging looks good and has:
```
Mar 25 08:44:29 zrhpkoso zcatvault-zcatvault[854262]: ***BEGIN se-checksums.txt.enc CAT DUMP***
Mar 25 08:44:29 zrhpkoso zcatvault-zcatvault[854262]: hyper-protect-basic.6K13absYymqE5+SEtq6e636fMTF7tItBHyR/LxJhInHYPbDqOY1P9tDfWvTIzooSWD06Kl9ZSLc1iKKTLyOTCmQLqcOgfONnmpPndYHxVSdkM01ROhglgtCyj+Y2Qf7dZzF3Uo9oqgHVO9gCWwAwXp3zs1i1Zu6OHZNgtjKDDCRRNWo3lxS99MzL0Pgb+VVzWxfh3nejXjRXWd31iT9436AQZ3v2xMpq/7YE3kniHYjOVa2KlUwlTZSTdkhzFsI1yAlAkSjM8zQiUlhotZMdEugjUJJuS0K7K71wq/mpXBRvBkPZ2zcI4KfASc9D4jEjuLC1ZyFQA21fqYiYiaSi3Z8NZDlNIa+Xuc50lTHwwE7mRE+4NkMugdpQM/j5bCnPNLI7aYDVYHJpFapKdWaJA3azs+aeqWQp/UYvahrGevHpgSnqIUaiABYY2Ru2+dYzehvxP9ySFI2d46Np6/zIE8GzHDdYJNlVJmOUtjfZOBOZy8MooEVibK0a3gKrxpcNqaUsQ0glXbnmLc4adwrG3KcxJEBxHgahhNOfwLpst2HiDP5LLcXrGYWoDDbFG/wHlMBE5EO+aFuDMRt0fjCpKUzx1eoaoNirE57oCxPQ2Y9EtasiRqNfvifDKUJi0XwxVFlJGGiCsg6K477pJypUbqmMbxzrOyxJAOoAmAbUWOc=.U2FsdGVkX1/To+2wg/IYTMQoQ0SkUkfLNMNRVsmVb9nCH0PYfdCxEQU3Y4hJ0S/04teeQvBhuRSDZzYi4CHs50c1bYa/g6Bp0xLncHR59TQI7X1hF1PpbAq9iASBEzAQw8YhwGpnfdr0qCGI3FrbEnUEVO0aCPPGis7f/Iha8E8c8s3nyQOsXTxTqc5ezXRJZrt6SlHrNHdNxtQpSC01YFLLerHvsJVAcCCB2G7yARG/WESsyIBg2fwegOtSa7OHEh8hOZWKAEuKQhoJl06Rt1kZfjBZzwlRUY7HF2rBScfLgycI2VsBdMr5ioPid3MYTVzh6OBYjOoVk07SGTfrfJXL3rYek+D4LV13Npnp3AZnQiL2/trF+1Elwp69BHxm93LUGIcUeW0CfllvMwGiydVN/ngMvbfKLY9K+biVNa8tLkzZJeGkQBpH7spn6yQrvubQfV+SULfaJT+KXWuzzdcXu1RVwq64b7oxHdIAOESR+AbCxBL8i6fSvTTuZH4kYQLSFwQSCE7f5YBAcvSEO7A6WQbCxPK7v6Ueqt1FOt5jdQI9RlMuXMonjfU+lr5375NDljG0SAODpsR+vwPwQpDbYK/sJns27zino/XmlMyRT3JK+HSf9LMNSbtIaNrkSSRv0+ELs0jT17VjC/CtnjTotE7Ehr1vxGqR+9YOOQ8FUEpvaJidJgp/4g057kc+10sxG98Rj+cZlJAAVONfsKy5LvfqLnnxJekLAUvB4wzU4ZkT5+q2jWMunT//FITVEygFKZSyZm/wz1NAIt8USpxL9Mbkl7tqytQFQtvodSi/Vaw0NBD26FHXMq0dc8O2cVYLEvTjlitjaVqhP9Lsglw3u6sq4GPhu2v4PSPJV1ffVrjOsB5xk5uJwFGKwhhY6srC+6SIlOmRFxENKwLwnJM/Y2eOe4tcL42IcnkGuXTWXBGm5NVAlJmpi2XBIFz5u/1XJqSa2qrXHB+LoWn14/5MWXXguPU8JxQqPHq9EimTYAT+qbBA16QJ9tw2A2vwKLCDh6s20ruHrYKj4sp02B8NGgHSpYSIufjGo3KCszY8mCvvpaGcXbv68xUGc4L6mWYe/tMQHVIf6LoyhhYgdhjFkjsYHC1oK/ijMdxo/njOaw7QHqD9Cva5aV0o1gioHkYJpNltRM+7Yp0g2jhaH95+ARYAIBTVgM7DGuOrTrW11O6Dv1E0MrWgPeDmESiCbYbtasOan+bC5Tw6gyfgnvgRPKTG0P/+cZF5vkHN5koWPhNGORo1XSwGMs2hYa5s***END se-checksums.txt.enc CAT DUMP***
```
Checking the attestation:
```
[root@zrhpgp11 vault-tutorial-onprem]# ./decrypt-attestation.sh private_attestation.pem se-checksums.txt.enc
Enter pass phrase for private_attestation.pem:
[root@zrhpgp11 vault-tutorial-onprem]# cat se-checksums.txt
24.11.0
Machine Type/Plant/Serial: 3931/02/8A3B8
Image age: 124 days since creation.
ad65a3820d4a233c84e6d201ce537b8020435ccefe26682809da5ef9b176b8ae root.tar.gz
080f817231fe4bc40021d24e20af9f1135a36711047212f9374664b86ab406ac baseimage
295405e46f835299776079821776bcf0e7f1bbdf5e493959a25be56526e4e742 /dev/disk/by-label/cidata
c7337f60d493b4b146c27ad1213b4b6fd35bb88c9905869002b47fbae16f4e52 cidata/meta-data
d0a6d95be44499e1372707ac68d6f1aa23a034046542978e42f55e84a53a660f cidata/user-data
13891bfb004315f8fd84d1b3d06833fe251f7749010e1c14833522bd57a950c4 cidata/vendor-data
dcc2ca7f5b8590e69524ef63e8ddbb3c1770dabf40525950c3171ae2d059ff70 contract:workload 
4bd9da278bc3604414c038a090ad06ec87cca17f32e15ac42dbe13e37acc9fb1 contract:env 
5b9587234163bbbfbb14f5e7aad77f6f864f33e52fe43b834afd04f969ae3329 contract:attestationPublicKey 
e236791035292b8b3c4bf8507a6faa587c64a4dd7e1503064b1c6fd462edce7f contract:envWorkloadSignature 
[root@zrhpgp11 vault-tutorial-onprem]# cat gen-se-checksums.txt 
dcc2ca7f5b8590e69524ef63e8ddbb3c1770dabf40525950c3171ae2d059ff70  - contract:workload
4bd9da278bc3604414c038a090ad06ec87cca17f32e15ac42dbe13e37acc9fb1  - contract:env
5b9587234163bbbfbb14f5e7aad77f6f864f33e52fe43b834afd04f969ae3329  - contract:attestationPublicKey
e236791035292b8b3c4bf8507a6faa587c64a4dd7e1503064b1c6fd462edce7f  - contract:envWorkloadSignature
```
All patterns match!

### 5. Testing with WRONG Signature
Altering a character on the `signingKey` component on the environment section of the contract simulates someone trying to deploy a workload with the wrong signature, this results in the following error when the machine comes up:
```
# HPL11 build:24.11.0 enabler:24.11.0
# Tue Mar 25 12:21:15 UTC 2025
# Machine Type/Plant/Serial: 3931/02/8A3B8
# delete old root partition...
# create new root partition...
# encrypt root partition...
# create root filesystem...
# write OS to root disk...
# decrypt user-data...
3 token decrypted, 0 encrypted token ignored
# create attestation data
# encrypt attestation document...
# set hostname...
# finish root disk setup...
# Tue Mar 25 12:21:35 UTC 2025
# HPL11 build:24.11.0 enabler:24.11.0
# HPL11099I: bootloader end
hpcr-dnslookup[1063]: HPL14000I: Network connectivity check completed successfully.
hpcr-logging[1106]: Configuring logging ...
hpcr-logging[1111]: Version [1.1.184]
hpcr-logging[1111]: Configuring logging, input [/var/hyperprotect/user-data.decrypted] ...
hpcr-logging[1111]: HPL01010I: Logging has been setup successfully.
hpcr-logging[1106]: Logging has been configured
hpcr-catch-failure[1198]: VSI has failed to start!
hpcr-catch-failure[1198]: HPL10000E: One or more service failed -> systemd triggered hpl-catch-failed service
```
Looking at the logs:
```
Mar 25 08:21:37 zrhpkoso hpcr-contract[854262]: Contract file is invalid.
Mar 25 08:21:37 zrhpkoso hpcr-contract[854262]: Validation of Contract failed.
Mar 25 08:21:37 zrhpkoso hpcr-contract[854262]: HPL05001E: Unable to validate the contract semantically. -> jsonschema: '/envWorkloadSignature' does not validate with file:///schema.json#/allOf/6/properties/envWorkloadSignature/$ref/pattern: does not match pattern '^(?:[A-Za-z\\d+/]{4}\\s*)*(?:[A-Za-z\\d+/]{3}=|[A-Za-z\\d+/]{2}==)?$'
Mar 25 08:21:37 zrhpkoso hpcr-contract[854262]: Validation Error: {}
```
We can therefore see in action how HPVS will protect the the workload by deploying it only when it matches the signature.
# Conclusion
Now have a better understanding of the HPVS anti tamper mechanisms:
- Attestation: for the AUDITOR to audit the system and make sure all components are what they say they are, must keep their PUBLIC and Private keys a secret (especially the public keys)
- Contract Signature: a way for a contract signer (presumably the workload owner) to sign the contract so that the workload can't be tampered with, if the signature doesn't match then HPVS will not deploy the workload (assumes it has been compromised)

It is worth noting that neither process will necessarily stop the deployment of a compromised imaged at source. If some malicious actor has managed to push an image with the SAME SHA256SUM to the registry then it will be deployed as it's passed the checksum test. The only way to protect against that is to use a secure build method and sign the images digitally.
