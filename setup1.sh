minikube start

export VAULT_LICENSE="..."

kubectl create ns vault

kubectl create secret generic vault-license --from-literal license=$VAULT_LICENSE -n vault

helm install vault hashicorp/vault -n vault --create-namespace --values vault/vault-values.yaml
# vault-values updates for ent

read -p "check Vault is ready then press enter to continue"

kubectl exec --stdin=true --tty=true vault-0 -n vault -- /bin/sh

vault namespace create us-west-org

VAULT_NAMESPACE=us-west-org vault auth enable -path demo-auth-mount kubernetes

VAULT_NAMESPACE=us-west-org vault write auth/demo-auth-mount/config \
	kubernetes_host="http://$KUBERNETES_PORT_443_TCP_ADDR:443"

VAULT_NAMESPACE=us-west-org vault secrets enable -path=kvv2 kv-v2
## could not run below in shell on vault server, had to remotely run
VAULT_NAMESPACE=us-west-org vault policy write dev - <<EOF
	path "kvv2/data/webapp/config" {
	   capabilities = ["read", "list", "subscribe"]
	   subscribe_event_types = ["kv*"]
	}

	path "sys/events/subscribe/kv*" {
   		capabilities = ["read"]
	}
EOF
# could not run remotely
VAULT_NAMESPACE=us-west-org vault write auth/demo-auth-mount/role/role1 \
   bound_service_account_names=instant-update-app \
   bound_service_account_namespaces=app \
   policies=dev \
   token_period=2m

# VAULT_NAMESPACE=us-west-org vault write auth/demo-auth-mount/role/role1 \
#    bound_service_account_names=instant-update-app \
#    bound_service_account_namespaces=app \
#    policies=dev \
#    audience=vault \
#    ttl=24h

VAULT_NAMESPACE=us-west-org vault kv put kvv2/webapp/config username="static-user" password="static-password"
# demo uses kustomize instead of helm

# in cloned vso repo
export GOARCH=amd64
GOOS=linux
docker build -t hashicorp/vault-secrets-operator:0.0.0-dev . --target=dev \
        --build-arg GOOS=$GOOS \
        --build-arg GOARCH=$GOARCH \
        --build-arg GO_VERSION=$(cat .go-version) \
        --build-arg LD_FLAGS="$(GOOS=$GOOS GOARCH=$GOARCH ./scripts/ldflags-version.sh)"
# clear all vso images from mk repo
minikube image ls
minikube image rm docker.io/hashicorp/vault-secrets-operator:latest

helm install vault-secrets-operator ./chart --version 0.0.0-dev -n vault-secrets-operator-system --create-namespace --values vov.yaml  

# back in learn-vault-cso repo
kubectl create ns app

kubectl apply -f vault/vault-auth-static.yaml

kubectl apply -f vault/static-secret.yaml

