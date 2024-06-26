minikube start
helm install vault hashicorp/vault -n vault --create-namespace --values vault/vault-values.yaml

read -p "check Vault is ready then press enter to continue"

kubectl port-forward -n vault statefulset/vault 8200:8200 &
export VAULT_TOKEN=root  
export VAULT_ADDR=http://127.0.0.1:8200
vault status

read -p "check ports forwaring  is ready then press enter to continue"

vault auth enable -path demo-auth-mount kubernetes

vault write auth/demo-auth-mount/config \
   kubernetes_host="https://$KUBERNETES_PORT_443_TCP_ADDR:443"

vault secrets enable -path=kvv2 kv-v2

vault policy write dev - <<EOF
path "kvv2/*" {
   capabilities = ["read"]
}
EOF

vault write auth/demo-auth-mount/role/role1 \
   bound_service_account_names=instant-update-app \
   bound_service_account_namespaces=app \
   policies=dev \
   audience=vault \
   ttl=24h

vault kv put kvv2/webapp/config username="static-user" password="static-password"

