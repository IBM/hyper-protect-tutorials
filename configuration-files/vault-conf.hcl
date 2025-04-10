ui            = true
cluster_addr  = "http://127.0.0.1:8201"
api_addr      = "http://0.0.0.0:8200"
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
