#! /bin/bash

# git clone https://github.com/hashicorp-education/learn-vault-secrets-operator.git

# cd learn-vault-secrets-operator

export VAULT_LICENSE=$1
# echo $VAULT_LICENSE

# exit

# minikube start

# read -p "Press enter to continue"

# helm repo add hashicorp https://helm.releases.hashicorp.com

# helm repo update

# helm search repo hashicorp/vault

read -p "Press enter to continue"

kubectl create ns vault

kubectl create secret generic vault-license --from-literal license=$VAULT_LICENSE -n vault

helm install vault hashicorp/vault -n vault --create-namespace --values vault/vault-values.yaml

read -p "Press enter to continue"

# export VAULT_TOKEN="root" 
# export VAULT_ADDR=http://127.0.0.1:8200

echo "kubectl port-forward -n vault statefulset/vault 38306:8200 &"
read -p "Press enter to continue"

# kubectl exec --stdin=true --tty=true vault-0 -n vault -- /bin/sh

vault namespace create us-west-org

VAULT_NAMESPACE=us-west-org vault auth enable -path demo-auth-mount kubernetes

VAULT_NAMESPACE=us-west-org vault write auth/demo-auth-mount/config \
	kubernetes_host="http://$KUBERNETES_PORT_443_TCP_ADDR:443"

VAULT_NAMESPACE=us-west-org vault secrets enable -path=kvv2 kv-v2

VAULT_NAMESPACE=us-west-org vault policy write dev - <<EOF
	path "kvv2/*" {
	capabilities = ["read"]
	}
EOF

VAULT_NAMESPACE=us-west-org vault write auth/demo-auth-mount/role/role1 \
	bound_service_account_names=default \
	bound_service_account_namespaces=app \
	policies=dev \
	audience=vault \
	ttl=24h

VAULT_NAMESPACE=us-west-org vault kv put kvv2/webapp/config username="static-user" password="static-password"

## to build new image use this
## these execute in the cloned repo of VSO 
# export GOOS='linux'
# export GOARCH='amd64'

# docker build -t hashicorp/vault-secrets-operator . --target=dev \
#         --build-arg GOOS=$GOOS \
#         --build-arg GOARCH=$GOARCH \
#         --build-arg GO_VERSION=$(cat .go-version) \
#         --build-arg LD_FLAGS="$(GOOS=$GOOS GOARCH=$GOARCH ./scripts/ldflags-version.sh)"

# minikube image load hashicorp/vault-secrets-operator

## execute this in VSO repo with the VAULT-25164/kv-events branch
# helm install vault-secrets-operator ./chart --version 0.0.0-dev -n vault-secrets-operator-system --create-namespace --values vov.yaml

# back in learn-vault-secrets-operator

kubectl create ns app

kubectl apply -f vault/vault-auth-static.yaml

kubectl apply -f vault/static-secret.yaml

# k9s

# kubectl exec --stdin=true --tty=true vault-0 -n vault -- /bin/sh

# vault kv put kvv2/webapp/config username="static-user2" password="static-password2"

# exit

# kubectl create ns postgres

# helm repo add bitnami https://charts.bitnami.com/bitnami

# helm upgrade --install postgres bitnami/postgresql --namespace postgres --set auth.audit.logConnections=true  --set auth.postgresPassword=secret-pass

# kubectl exec --stdin=true --tty=true vault-0 -n vault -- /bin/sh

# vault secrets enable -path=demo-db database

# vault write demo-db/config/demo-db \
# 	plugin_name=postgresql-database-plugin \
# 	allowed_roles="dev-postgres" \
# 	connection_url="postgresql://{{username}}:{{password}}@postgres-postgresql.postgres.svc.cluster.local:5432/postgres?sslmode=disable" \
# 	username="postgres" \
# 	password="secret-pass"

# vault write demo-db/roles/dev-postgres \
# 	db_name=demo-db \
# 	creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; \
# 	GRANT ALL PRIVILEGES ON DATABASE postgres TO \"{{name}}\";" \
# 	backend=demo-db \
# 	name=dev-postgres \
# 	default_ttl="1m" \
# 	max_ttl="1m"

# vault policy write demo-auth-policy-db - <<EOF
# 	path "demo-db/creds/dev-postgres" {
# 	capabilities = ["read"]
# 	}
# 	EOF

# exit

# cat vault/vault-operator-values.yaml

# kubectl exec --stdin=true --tty=true vault-0 -n vault -- /bin/sh

# vault secrets enable -path=demo-transit transit

# vault write -force demo-transit/keys/vso-client-cache

# vault policy write demo-auth-policy-operator - <<EOF
# 	path "demo-transit/encrypt/vso-client-cache" {
# 	capabilities = ["create", "update"]
# 	}
# 	path "demo-transit/decrypt/vso-client-cache" {
# 	capabilities = ["create", "update"]
# 	}
# 	EOF

# vault write auth/demo-auth-mount/role/auth-role-operator \
# 	bound_service_account_names=demo-operator \
# 	bound_service_account_namespaces=vault-secrets-operator-system \
# 	token_ttl=0 \
# 	token_period=120 \
# 	token_policies=demo-auth-policy-db \
# 	audience=vault

# vault write auth/demo-auth-mount/role/auth-role \
# 	bound_service_account_names=default \
# 	bound_service_account_namespaces=demo-ns \
# 	token_ttl=0 \
# 	token_period=120 \
# 	token_policies=demo-auth-policy-db \
# 	audience=vault

# exit

# kubectl create ns demo-ns

# kubectl apply -f dynamic-secrets/.

# minikube delete

