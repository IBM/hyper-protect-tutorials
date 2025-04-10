ui            = true
cluster_addr  = "http://127.0.0.1:8201/"
api_addr      = "http://0.0.0.0:8200/"
disable_mlock = true
license_path  = "/vault/license.hclic"

storage "raft" {
    path = "/vault/data"
    vault_node_name = "vault_1"            #setting up a unique node_id for each vault node
}

listener "tcp" {
  address       = "0.0.0.0:8200"
  tls_disable   = 1
}

seal "pkcs11" {
 key_label = "vault-hsm-key"
 lib = "/usr/local/lib/pkcs11-grep11-s390x.so.2.6.8"
 slot = "0"
 mechanism = 0x1085
 pin = "12345678"
 generate_key = "true"
 # token_label = "vaultpoc"
 hmac_key_label = "vault-hsm-hmac-key"
}
