# CI/CD Demo with NGINX+ Ingress Controller and NGINX App Protect - Lab Setup

## Vars

Install these tools using your preferred way (brew, apt, manually, ...):

    - docker (must be running during the demo)
    - git
    - helm
    - jq
    - kubectl
    - kubectx
    - azure cli

Set the values below to your own env vars:

    ```bash
    export PREFIX=CHANGE_THIS_TO_YOUR_NAMESPACE
    export GITHUB_ACCOUNT=CHANGE_THIS_TO_YOUR_GITHUB_ACCOUNT
    export NGINX_VERSION=2.2.1
    ```

Let others know what values will be used.

    ```bash
    export AZURE_SUBSCRIPTION="ASK_YOUR_LAB_ADMIN"
    export AZURE_RG="ASK_YOUR_LAB_ADMIN"
    export AZURE_AKSCLUSTER="ASK_YOUR_LAB_ADMIN"
    export AZURE_ACR="ASK_YOUR_LAB_ADMIN"
    ```

## Create the Azure Kubernetes Service

Use the following commands to create a Resource Group and an AKS cluster:

    ```bash
    az group create --name $AZURE_RG --location eastus
    az aks create --resource-group $AZURE_RG --name $AZURE_AKSCLUSTER --node-count 2 --enable-addons monitoring --no-ssh-key --node-vm-size Standard_D8s_v3
    ```

Then, create a Container Registry and attach to AKS.

    ```bash
    az acr create --resource-group $AZURE_RG --name $AZURE_ACR --sku Basic
    az aks update -n $AZURE_AKSCLUSTER -g $AZURE_RG --attach-acr $AZURE_ACR
    ```

## Deploy ArgoCD to AKS

    ```bash
    kubectl create namespace argocd
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
    kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'
    kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
    echo https://`kubectl get svc -n argocd argocd-server -o jsonpath="{.status.loadBalancer.ingress[0].ip}"`.nip.io
    ```
