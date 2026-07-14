default: all-ent

all-ent: ent-prerequisites start-minikube install-vault-ent-cluster config-vault install-the-vault-secrets-operator deploy-and-sync-a-secret rotate-the-secret install-postgresql-pod setup-postgresql transit-encryption setup-dynamic-secrets create-the-application
community: prerequisites start-minikube install-vault-cluster
export ENT_RUN:="0"
test:
    @echo $VAULT_LICENSE
    @just _print_static_secrets
    @kubectl exec -it vault-0 -n vault -- env 
    @just _print_dynamic_secrets

start-minikube:
    @echo ">>> start-minikube" 
    minikube start

clean-up:
    minikube delete

kill-ns:
	@kubectl delete ns vault app vault-secrets-operator-system demo-ns postgres
	sleep 5

prep-cluster-install:
	@helm repo add hashicorp https://helm.releases.hashicorp.com
	@helm repo update
	@helm search repo hashicorp/vault

install-vault-cluster: prep-cluster-install
	@helm install vault hashicorp/vault -n vault --create-namespace --values vault/vault-values.yaml
	@kubectl get pods -n vault

install-vault-ent-cluster: prep-cluster-install
	@kubectl create ns vault
	@sleep 10
	@kubectl create secret generic vault-license --from-literal license=$VAULT_LICENSE -n vault
	@helm install vault hashicorp/vault -n vault --values vault-ent/vault-values.yaml
	@kubectl wait --for=jsonpath='{.status.phase}'=Running pod --all --namespace vault --timeout=1m
	@kubectl get pods -n vault

uninstall-vault:
	@helm uninstall vault -n vault
	@kubectl delete ns vault
	@sleep 10

reinstall-vault: uninstall-vault install-vault-cluster

reinstall-vault-ent: uninstall-vault install-vault-ent-cluster

status:
    @kubectl exec -n vault -ti vault-0 -- vault status

logs:
	@kubectl logs -n vault sts/vault -f

install-the-vault-secrets-operator:
	@helm install vault-secrets-operator hashicorp/vault-secrets-operator \
		-n vault-secrets-operator-system \
		--create-namespace \
		--values vault-ent/vault-operator-values.yaml \
		--version 0.8.0
	@sleep 10
	@kubectl wait --for=jsonpath='{.status.phase}'=Running pod \
		--all --namespace vault-secrets-operator-system --timeout=1m
	@kubectl wait --for=jsonpath='{.status.phase}'=Running pod --all --namespace vault-secrets-operator-system --timeout=1m
	@sleep 10

uninstall-vso:
	@helm uninstall vault-secrets-operator -n vault-secrets-operator-system

vso-logs:
   @kubectl logs -n vault-secrets-operator-system -l app.kubernetes.io/name=vault-secrets-operator -f

config-vault: 
    #!/usr/bin/env bash
    kubectl exec -it vault-0 -n vault -- vault namespace create us-west-org
    kubectl exec -it vault-0 -n vault -- env VAULT_NAMESPACE=us-west-org vault auth enable -path demo-auth-mount kubernetes
    addr1=$(kubectl exec vault-0 -n vault --  printenv KUBERNETES_PORT_443_TCP_ADDR)
    echo "$addr1"
    kubectl exec -it vault-0 -n vault -- env VAULT_NAMESPACE=us-west-org vault write auth/demo-auth-mount/config \
        kubernetes_host="https://$addr1:443"
    kubectl exec -it vault-0 -n vault -- env VAULT_NAMESPACE=us-west-org vault secrets enable -path=kvv2 kv-v2
    kubectl cp -n vault support/webapp.hcl vault-0:/tmp/webapp.hcl 
    kubectl exec -it vault-0 -n vault -- env VAULT_NAMESPACE=us-west-org vault policy write  webapp /tmp/webapp.hcl
    kubectl exec -it vault-0 -n vault -- env VAULT_NAMESPACE=us-west-org vault write auth/demo-auth-mount/role/role1 \
        bound_service_account_names=demo-static-app \
        bound_service_account_namespaces=app \
        policies=webapp \
        audience=vault \
        token_period=2m
    kubectl exec -it vault-0 -n vault -- env VAULT_NAMESPACE=us-west-org vault kv put kvv2/webapp/config \
        username="static-user" password="static-password"
	
deploy-and-sync-a-secret:
	@kubectl create ns app
	@sleep 5
	@kubectl apply -f vault-ent/vault-auth-static.yaml
	@kubectl apply -f vault-ent/static-secret.yaml
	@sleep 3
	echo "username: $(kubectl get secrets -n app secretkv -o jsonpath="{.data.username}" | base64 -d), pass: $$(kubectl get secrets -n app secretkv -o jsonpath="{.data.password}" | base64 -d)"

_print_static_secrets:
    #!/usr/bin/env bash
    echo "static secrets - username: $(kubectl get secrets -n app secretkv -o jsonpath="{.data.username}" | base64 -d), pass: $(kubectl get secrets -n app secretkv -o jsonpath="{.data.password}" | base64 -d)"

_print_dynamic_secrets:
    #!/usr/bin/env bash
    echo "dynamic secrets - username: $(kubectl get secrets -n demo-ns -o jsonpath="{.items[1].data.username}" | base64 -d), pass: $(kubectl get secrets -n demo-ns -o jsonpath="{.items[1].data.password}" | base64 -d)"


rotate-the-secret:
	@just _print_static_secrets
	@kubectl exec -it vault-0 -n vault -- env VAULT_NAMESPACE=us-west-org vault kv put kvv2/webapp/config username="static-user2" password="static-password2"
	@just _print_static_secrets

uninstall-app-ns:
	@kubectl delete ns app

install-postgresql-pod:
    @kubectl create ns postgres
    @sleep 10
    @helm repo add bitnami https://charts.bitnami.com/bitnami
    @helm upgrade --install postgres bitnami/postgresql --namespace postgres --set auth.audit.logConnections=true  --set auth.postgresPassword=secret-pass
    @kubectl wait --for=jsonpath='{.status.phase}'=Running pod --all --namespace postgres --timeout=1m
    @sleep 10

uninstall-postgresql-pod:
    @kubectl exec -it vault-0 -n vault -- env VAULT_NAMESPACE=us-west-org vault secrets disable demo-db
    @kubectl delete ns postgres
    @sleep 10

setup-postgresql:
    #!/usr/bin/env bash
    kubectl exec -it vault-0 -n vault -- env VAULT_NAMESPACE=us-west-org vault secrets enable -path=demo-db database 
    sleep 5
    kubectl exec -it vault-0 -n vault -- env VAULT_NAMESPACE=us-west-org vault write demo-db/config/demo-db \
        plugin_name=postgresql-database-plugin \
        allowed_roles="dev-postgres" \
        connection_url="postgresql://{{{{username}}:{{{{password}}@postgres-postgresql.postgres.svc.cluster.local:5432/postgres?sslmode=disable" \
        username="postgres" \
        password="secret-pass"
    kubectl exec -it vault-0 -n vault -- env VAULT_NAMESPACE=us-west-org vault write demo-db/roles/dev-postgres db_name=demo-db \
        creation_statements="CREATE ROLE \"{{{{name}}\" WITH LOGIN PASSWORD '{{{{password}}' VALID UNTIL '{{{{expiration}}'; \
        GRANT ALL PRIVILEGES ON DATABASE postgres TO \"{{{{name}}\";" \
        revocation_statements="REVOKE ALL ON DATABASE postgres FROM  \"{{{{name}}\";" \
        backend=demo-db \
        name=dev-postgres \
        default_ttl="1m" \
        max_ttl="1m"
    kubectl cp -n vault support/postgresql.hcl vault-0:/tmp/postgresql.hcl
    kubectl exec -it vault-0 -n vault -- env VAULT_NAMESPACE=us-west-org vault policy write demo-auth-policy-db /tmp/postgresql.hcl


transit-encryption:
	#!/usr/bin/env bash
	kubectl exec -it vault-0 -n vault --  env VAULT_NAMESPACE=us-west-org vault secrets enable -path=demo-transit transit
	kubectl exec -it vault-0 -n vault --  env VAULT_NAMESPACE=us-west-org vault write -force demo-transit/keys/vso-client-cache
	kubectl cp -n vault support/demo-auth-policy-operator.hcl vault-0:/tmp/demo-auth-policy-operator.hcl
	kubectl exec -it vault-0 -n vault --  env VAULT_NAMESPACE=us-west-org vault policy write demo-auth-policy-operator /tmp/demo-auth-policy-operator.hcl
	kubectl exec -it vault-0 -n vault --  env VAULT_NAMESPACE=us-west-org vault write auth/demo-auth-mount/role/auth-role-operator \
		bound_service_account_names=vault-secrets-operator-controller-manager \
		bound_service_account_namespaces=vault-secrets-operator-system \
		token_ttl=0 \
		token_period=120 \
		token_policies=demo-auth-policy-operator \
		audience=vault

setup-dynamic-secrets:
    #!/usr/bin/env bash
    kubectl exec -it vault-0 -n vault --  env VAULT_NAMESPACE=us-west-org vault write auth/demo-auth-mount/role/auth-role \
        bound_service_account_names=demo-dynamic-app \
        bound_service_account_namespaces=demo-ns \
        token_ttl=0 \
        token_period=120 \
        token_policies=demo-auth-policy-db \
        audience=vault

create-the-application:
    #!/usr/bin/env bash
    kubectl create ns demo-ns
    sleep 5
    kubectl apply -f vault-ent/dynamic-secrets/.
    sleep 5
    echo "dynamic - username: $(kubectl get secrets -n demo-ns -o jsonpath="{.items[1].data.username}" | base64 -d), pass: $(kubectl get secrets -n demo-ns -o jsonpath="{.items[1].data.password}" | base64 -d)"

prerequisites:
    #!/usr/bin/env bash
    if ! command -v kubectl 2>&1 >/dev/null
    then
        echo "kubectl could not be found"
        exit 1
    fi
    if ! command -v k9s 2>&1 >/dev/null
    then
        echo "k9s could not be found"
        exit 1
    fi
    if ! command -v helm 2>&1 >/dev/null
    then
        echo "helm could not be found"
        exit 1
    fi
    if ! command -v minikube 2>&1 >/dev/null
    then
        echo "minikube could not be found"
        exit 1
    fi

ent-prerequisites: prerequisites
    #!/usr/bin/env bash
    if [ -z "${VAULT_LICENSE}" ]; then
        echo "VAULT_LICENSE not set"
        exit 1
    fi