#!/bin/bash
echo "### Preparing the CICD demo with NGINX+ Ingress Controller and App Protect"

echo "### Preparing demo root folder ###"
rm -rf ~/cicd-demo-resources/ 
mkdir ~/cicd-demo-resources/

echo "### Cloning NGINX Ingress to folder `pwd` ###"
cd ~/cicd-demo-resources/
git clone https://github.com/nginxinc/kubernetes-ingress/

echo "### Building nginx ingress v$NGINX_VERSION ###"
cd ~/cicd-demo-resources/kubernetes-ingress
git checkout v$NGINX_VERSION
cp ~/nginx-repo.* .
make debian-image-nap-dos-plus PREFIX=nginx-ingress TARGET=container TAG=$NGINX_VERSION

echo "### Building Azure Resources ###"
cd ~/cicd-demo-resources/
echo "### Creating Azure Resource Group ###"
az group create --name $AZURE_RG --location eastus
echo "### Creating Azure Kubernetes Service (AKS) ###"
az aks create --resource-group $AZURE_RG --name $AZURE_AKSCLUSTER --node-count 2 --enable-addons monitoring --no-ssh-key --node-vm-size Standard_D4_v3
echo "### Creating Azure Container Registry (ACR) ###"
az acr create --resource-group $AZURE_RG --name $AZURE_ACR --sku Basic
echo "### Attaching ACR to AKS ###"
az aks update -n $AZURE_AKSCLUSTER -g $AZURE_RG --attach-acr $AZURE_ACR

echo "### Logging into ACR ###"
az acr login --name $AZURE_ACR
echo "### Listing NGINX Ingress container image info ###"
docker image inspect nginx-ingress:$NGINX_VERSION
echo "### Tagging NGINX Ingress container image ###"
docker tag nginx-ingress:$NGINX_VERSION $AZURE_ACR.azurecr.io/$PREFIX/nginx-ingress:$NGINX_VERSION
echo "### Uploading NGINX Ingress image to ACR ###"
docker push $AZURE_ACR.azurecr.io/$PREFIX/nginx-ingress:$NGINX_VERSION

echo "### Getting K8s cluster credentials ###"
az aks get-credentials --name $AZURE_AKSCLUSTER --resource-group $AZURE_RG --file ~/.kube/config
echo "### Deploying ArgoCD ###"
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'

echo "### Deploying NGINX Ingress to the cluster ###"
cd ~/cicd-demo-resources/kubernetes-ingress/deployments/helm-chart
helm repo add nginx-stable https://helm.nginx.com/stable
helm repo update
helm install $PREFIX-ingress nginx-stable/nginx-ingress \
    --namespace=nginx-ingress \
    --create-namespace \
    --set controller.kind=deployment \
    --set controller.replicaCount=1 \
    --set controller.image.repository=$AZURE_ACR.azurecr.io/$PREFIX/nginx-ingress \
    --set controller.image.tag=$NGINX_VERSION \
    --set controller.nginxplus=true \
    --set controller.appprotect.enable=true \
    --set controller.appprotectdos.enable=true \
    --set controller.ingressClass=$PREFIX-nginx-ingress \
    --set controller.enableCustomResources=true \
    --set controller.enablePreviewPolicies=true \
    --set controller.enableSnippets=true \
    --set controller.enableTLSPassthrough=true \
    --set controller.healthStatus=true \
    --set controller.nginxStatus.enable=true \
    --set controller.nginxStatus.allowCidrs="0.0.0.0/0" \
    --set controller.service.name="$PREFIX-nginx-ingress" \
    --set controller.service.type=LoadBalancer \
    --set prometheus.create=true \
    --set controller.enableLatencyMetrics=true \
    --set controller.config.proxy-protocol="true" \
    --set controller.config.real-ip-header="proxy_protocol" \
    --set controller.config.set-real-ip-from="0.0.0.0/0"

echo "### DONE! ###"
cd ~/cicd-demo-resources/

printf "\n\n"
echo "Variables:"
echo "PREFIX=$PREFIX"
echo "GITHUB_ACCOUNT=$GITHUB_ACCOUNT"
echo "AZURE_SUBSCRIPTION=$AZURE_SUBSCRIPTION"
echo "AZURE_RG=$AZURE_RG"
echo "AZURE_AKSCLUSTER=$AZURE_AKSCLUSTER"
echo "AZURE_ACR=$AZURE_ACR"
echo "NGINX_VERSION=$NGINX_VERSION"

printf "\n\n"
echo "Your root demo folder: `pwd`"
echo "Your ArgoCD URL: https://`kubectl get svc -n argocd argocd-server -o jsonpath='{.status.loadBalancer.ingress[0].ip}'`"
echo "Your ArgoCD admin password: `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo`"
echo "Your NGINX Ingress IP: `kubectl get svc -n nginx-ingress $PREFIX-nginx-ingress -o jsonpath='{.status.loadBalancer.ingress[0].ip}'`"
echo "Note: If your NGINX Ingress IP is empty, try later the command: kubectl get svc -n nginx-ingress $PREFIX-nginx-ingress -o jsonpath='{.status.loadBalancer.ingress[0].ip}'"