#!/bin/sh

pushd ..

printf "\nInstall Keycloak ...\n"
# Create Keycloak namespace if it does not yet exist
kubectl create namespace keycloak --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f keycloak/keycloak-secrets.yaml
kubectl apply -f keycloak/keycloak-db-pv.yaml
kubectl apply -f keycloak/keycloak-postgres.yaml
printf "\nWait for Keycloak Postgres readiness ...\n"
kubectl -n keycloak rollout status deploy/postgres

kubectl apply -f keycloak/keycloak.yaml
printf "\nWait for Keycloak readiness ...\n"
kubectl -n keycloak rollout status deploy/keycloak

printf "\nDeploy HTTPBin service ...\n"
kubectl apply -f apis/httpbin.yaml

printf "\nDeploy OAuth AuthConfig ...\n"
kubectl apply -f policies/extauth/oauth-acf-auth-config.yaml

printf "\nDeploy VirtualServices ...\n"
kubectl apply -f virtualservices/api-example-com-vs.yaml
kubectl apply -f virtualservices/keycloak-example-com-vs.yaml

# Create a an incorrect OAuth clientSecret which we will use in our test to see what 
# we log when the clientSecret to access the IdP for Authorization Code Flow is incorrect.

# Create a oauth K8S secret with from the webapp-client's secret. 
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: wrong-oauth
  namespace: gloo-system
type: extauth.solo.io/oauth
data:
  client-secret: c29tZXJhbmRvbXRleHQ=
EOF

popd