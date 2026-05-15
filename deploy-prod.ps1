# Production deployment - NO mock images, NO worker removal, NO single replica scaling

# Deploy in order
kubectl apply -f 00-namespaces.yaml
kubectl apply -f 01-metallb.yaml
kubectl apply -f 02-postgres.yaml
kubectl apply -f https://raw.githubusercontent.com/traefik/traefik/v3.0/docs/content/reference/dynamic-configuration/kubernetes-crd-definition-v1.yml
kubectl apply -f https://raw.githubusercontent.com/traefik/traefik/v3.0/docs/content/reference/dynamic-configuration/kubernetes-crd-rbac.yml
kubectl apply -f 03-traefik-rbac.yaml
kubectl apply -f 04-traefik-install.yaml
kubectl apply -f 05-traefik-middlewares.yaml
kubectl apply -f 11-configmaps.yaml
kubectl apply -f 12-secrets.yaml
kubectl apply -f 06-auth.yaml
kubectl apply -f 07-cockpit.yaml
kubectl apply -f 08-messenger.yaml
kubectl apply -f 09-social.yaml
kubectl apply -f 10-task.yaml
kubectl apply -f 13-vault.yaml
kubectl apply -f 14-workflow.yaml

# Keep 2 replicas (HA), keep workers, use ECR images
kubectl scale statefulset postgres -n database-namespace --replicas=2

kubectl get pods -A