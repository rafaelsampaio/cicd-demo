# CI/CD Demo with NGINX+ Ingress Controller and NGINX App Protect

**READ** the instructions before trying the commands.

If you found any error, make sure you read and followed the instructions, in the order they appeard.

## Technology

- [NGINX+ Ingress Controller](https://www.nginx.com/products/nginx-ingress-controller/)
- [NGINX App Protect](https://www.nginx.com/products/nginx-app-protect/)
- [Azure Kubernetes Service (AKS)](https://azure.microsoft.com/en-us/services/kubernetes-service/)
- [ArgoCD](https://argo-cd.readthedocs.io/en/stable/)
- [GitHub Actions](https://docs.github.com/en/actions)
- [OWASP ZAP](https://www.zaproxy.org/docs/docker/full-scan/)
- [OWASP Juice Shop](https://hub.docker.com/r/bkimminich/juice-shop/)
- [Elastic Stack](https://hub.docker.com/r/sebp/elk/)

## Demo setup

It's highly recommended to use WSL in Windows or a Linux Virtual Machine in MacOS. All steps belows are for Linux, if you are using a different OS, make sure that **you** change all commands as needed.

1. Install all required tools and set your own variable set. Don't forget to update the ***PREFIX*** to an unique name, preferably your username, that you can identify later, it will also be your namespace.

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

    The vars below are the same to everyone. If you are the **lab admin**, let others know what values will be used.

    ```bash
    export AZURE_SUBSCRIPTION="ASK_YOUR_LAB_ADMIN"
    export AZURE_RG="ASK_YOUR_LAB_ADMIN"
    export AZURE_AKSCLUSTER="ASK_YOUR_LAB_ADMIN"
    export AZURE_ACR="ASK_YOUR_LAB_ADMIN"
    ```

    You'll need a [GitHub](https://github.com) account. If you don't have one account yet, [create one now](https://github.com/signup?ref_cta=Sign+up&ref_loc=header+logged+out&ref_page=%2F&source=header-home).

    [Create](https://github.com/new) a **public** repository with the name `cicd-demo`. You can use another repository name, but rememeber that you have to change all files and script.

    Remember to [add your SSH key](https://github.com/settings/keys) to your GitHub account. If you don't know how to do this, check the guide [Connecting to GitHub with SSH](https://docs.github.com/en/authentication/connecting-to-github-with-ssh).

    Register for NGINX+ trial to get access to the private repository using the given certificate and private key.

2. Configure Azure.

    Login to Azure, follow the instructions, and check the accounts you have access to.

    ```bash
    az login --use-device-code
    az account list --output table
    ```

    If necessary, fix the default subscription:

    ```bash
    az account set --subscription $AZURE_SUBSCRIPTION
    ```

3. Create the Azure Kubernetes Service.

    **If you are the one responsible to setting up the ASK, continue in step #3. If not, SKIP the procedure below and go to step #4.**

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

4. Build NGINX+ Ingress Controler with App Protect (WAF).

    ```bash
    git clone https://github.com/nginxinc/kubernetes-ingress/
    cd kubernetes-ingress
    git checkout v$NGINX_VERSION
    ```

5. Copy NGINX credentials to kubernetes-ingress.

    The certificate and private key to access NGINX repo should be stored in the parent dir.

    ```bash
    cp ../nginx-repo.* .
    make debian-image-nap-dos-plus PREFIX=nginx-ingress TARGET=container TAG=$NGINX_VERSION
    ```

6. Upload NGINX image to ACR.

    ```bash
    az acr login --name $AZURE_ACR
    docker tag nginx-ingress:$NGINX_VERSION $AZURE_ACR.azurecr.io/$PREFIX/nginx-ingress:$NGINX_VERSION
    docker push $AZURE_ACR.azurecr.io/$PREFIX/nginx-ingress:$NGINX_VERSION
    ```

7. Deploy NGINX+ IC to AKS.

    Update your kubectl config file with the credentials to access AKS. If a different object with the same name already exists in your kubeconfig file, overwrite it.

    ```bash
    az aks get-credentials --name $AZURE_AKSCLUSTER --resource-group $AZURE_RG --file ~/.kube/config
    ```

    Go back to the kubernetes-ingress project that you cloned in step #4. Then, deploy your NGINX to the cluster.

    ```bash
    #cd kubernetes-ingress
    cd deployments/helm-chart
    git checkout v$NGINX_VERSION
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
      --set controller.enableLatencyMetrics=true
      --set controller.config.proxy-protocol="true" \
      --set controller.config.real-ip-header="proxy_protocol" \
      --set controller.config.set-real-ip-from="0.0.0.0/0"
    ```

    To check your instance, try the commands below.

    ```bash
    kubectl describe service -n nginx-ingress $PREFIX-nginx-ingress
    ```

    Please, take note of your instance public IP address. You will need it to configure the ```host``` in VirtualServer and the ```target``` in OWASP ZAP.

    ```bash
    kubectl get svc -n nginx-ingress $PREFIX-nginx-ingress -o jsonpath="{.status.loadBalancer.ingress[0].ip}"
    ```

8. Deploy ArgoCD to AKS.

    ***For lab admin only***:

    ```bash
    kubectl create namespace argocd
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
    kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'
    ```

9. Check ArgoCD.

    Take note of your ArgoCD ***admin password*** and ***service URL***. There will be only one instance of ArgoCD.

    Get the ArgoCD credentials and hostname:

    ```bash
    kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
    echo https://`kubectl get svc -n argocd argocd-server -o jsonpath="{.status.loadBalancer.ingress[0].ip}"`.nip.io
    ```

## Running the demo

### Part 1

Go back to your parent project folder and clone the demo repository.

```bash
git clone https://github.com/rafaelsampaio/cicd-demo.git
cd cicd-demo
```

Your application hostname will be resolved using [nip.io](https://nip.io). Use the dash instead of dots in your hostname with ```app-``` prefix, like ```app-192-168-1-250.nip.io``` that maps to ```192.168.1.250```.

So, use your NGINX Ingress Controller public IP address to update your URLs to ```app-PUBLIC-IP-ADDRESS-WITH-DASHES.nip.io```.

**Update** all URLs and namespace from the files below. All URLs are hardcoded, so updated them as the instructions above **before** the first commit and push.

- [argo/application.yaml](argo/application.yaml) update ```name```, ```repoURL```, and ```namespace```.
- [app/app-namespace.yaml](app/app-namespace.yaml) update ```name```.
- [app/kustomization.yaml](app/kustomization.yaml) update ```namespace```.
- [app/nap-policy.yaml](app/nap-policy.yaml) update ```logDest```.
- [app/nap-vs.yaml](app/nap-vs.yaml) update ```host``` and ```ingressClassName```.
- [app/nap-waf-policy.yaml](app/nap-waf-policy.yaml) update ```responsePageReference``` and ```whitelistIpReference``` links to your repo.
- [workflows/scan.yml](workflows/scan.yml) update the ```target``` to your NGINX service URL.

Push the code to your repository:

```bash
git add --all
git commit -m "first commit"
git branch -M main
git remote add demo git@github.com:$GITHUB_ACCOUNT/cicd-demo.git
git push -u demo main
```

Deploy Application config to ArgoCD:

 ```bash
 kubectl apply -n argocd -f https://raw.githubusercontent.com/$GITHUB_ACCOUNT/cicd-demo/main/argo/application.yaml
 ```

Wait a few minutes for the first deployment, then check your Application in Argo. Deploy the dashboards to Kibana and take note of your instance URL at the end.

```bash
KIBANA_HOST=`kubectl get svc -n $PREFIX elk-kibana-svc -o jsonpath="{.status.loadBalancer.ingress[0].ip}"`
echo $KIBANA_HOST
KIBANA_URL=http://$KIBANA_HOST:5601
git clone https://github.com/f5devcentral/f5-waf-elk-dashboards.git
cd f5-waf-elk-dashboards
jq -s . kibana/overview-dashboard.ndjson | jq '{"objects": . }' | \
    curl -k --location --request POST "$KIBANA_URL/api/kibana/dashboards/import" \
    --header 'kbn-xsrf: true' \
    --header 'Content-Type: text/plain' -d @- \
    | jq
jq -s . kibana/false-positives-dashboards.ndjson | jq '{"objects": . }' | \
    curl -k --location --request POST "$KIBANA_URL/api/kibana/dashboards/import" \
    --header 'kbn-xsrf: true' \
    --header 'Content-Type: text/plain' -d @- \
    | jq
echo $KIBANA_URL
```

Navigate to your Kibana, Dashboard -> Overview to view the events from NGINX App Protect.

Right now, you should have the IP addresses for:

- Shared ArgoCD instance
- Your Kibana instance
- Your NGINX instance

### Part 2

Make sure there is no opened issue for the ***ZAP Full Scan Report***.

Create the `.github` folder and move the GitHub Actions [workflows](/workflows/) to that folder.

```bash
mkdir .github
mv workflows/ .github
git add --all
git commit -m "second commit - 1st scan"
git push -u demo main
```

With any simple change, like add or modify a file, will trigger a app scan and generate or update an GitHub issue with a report.

### Part 3 - After the 1st scan

After the first scan, we notice a lots of vulnerabilities that could be easy fixed with **NGINX App Protect**.

Check the file [app/nap-policy.yaml](app/nap-policy.yaml) to understand how to attach a WAF policy with ```apPolicy```. Also, we configure a logging policy using the ```securityLog``` that point to our ELK stack.

Check the file [app/nap-waf-policy.yaml](app/nap-waf-policy.yaml) to understand how to build a WAF policy with App Protect for NGINX+ Ingress Controller.

Check out the complete documentatio in [Using with NGINX App Protect](https://docs.nginx.com/nginx-ingress-controller/app-protect/configuration/) and [NGINX App Protect WAF Configuration Guide](https://docs.nginx.com/nginx-app-protect/configuration-guide/configuration/)

In [app/nap-vs.yaml](app/nap-vs.yaml), after `tls` settings block, to enable a policy in the VirtualServer, add the following:

```yaml
  policies:
  - name: nap-policy
```

Update your application code.

```bash
git add --all
git commit -m "add nginx app protect - 2nd scan"
git push -u demo main
```

### Part 4 - After the 2nd scan

Access the Kibana dashboard. When we check a reduced number of vulnerabilities, some of them related to content and settings in application and server, and the dashboard show some alerts.

We can fix some server/application issues in NGINX, by adding the following to [app/nap-vs.yaml](app/nap-vs.yaml), after the `requestHeaders` settings. Please, update the host ```value``` in the config below.

```yaml
        responseHeaders:
          hide:
          - Access-Control-Allow-Origin
          - Feature-Policy
          add:
          - name: Access-Control-Allow-Credentials
            value: "true"
          - name: Access-Control-Allow-Origin
            value: CHANGE_THIS_TO_YOUR_NGINX_SERVICE_URL
          - name: Content-Security-Policy
            value: default-src 'self'; script-src 'self' 'unsafe-inline' cdnjs.cloudflare.com; style-src 'self' 'unsafe-inline' cdnjs.cloudflare.com
          - name: Permissions-Policy
            value: payment 'self'
```

In [nap-waf-policy.yaml](app/nap-waf-policy.yaml), change the following violations to block:

```yaml
      - description: Illegal file type
        name: VIOL_FILETYPE
        block: true
      - description: Illegal method
        name: VIOL_METHOD
        block: true
      - description: Illegal meta character in URL
        name: VIOL_URL_METACHAR
        block: true
      - description: HTTP protocol compliance failed
        name: VIOL_HTTP_PROTOCOL
        block: true
```

Before `blocking-settings`, add the following allowed (in this case, forbidden) methods, and enable `bot-defense`:

```yaml
    methods:
    - name: TRACK
      $action: delete
    - name: TRACE
      $action: delete
    - name: OPTIONS
      $action: delete
    bot-defense:
      settings:
        isEnabled: true
```

Update your application code.

```bash
git add --all
git commit -m "update nginx app protect - 3rd scan"
git push -u demo main
```

After this, we demonstrate that the WAF settings can be implemented by the Security Team without locking, blocking, or breaking up the pipeline for the Development Team.

From the dashboard we demonstrate how operations activities can be integrated with security settings.

### Part 5 - After the 3rd scan

Some alerts triggered by the scanner are related to the content and they are not necessarily a matter for the Security Team.

So, we close the issue and forwarding the issue to be fixed by the dev team.

#### Optional step

Add the following lines to [.zap/rules.tsv](.zap/rules.tsv) to ignore some rules, separated by **tab**:

```text
10096 IGNORE (Timestamp Disclosure - Unix)
10055 IGNORE (CSP: Wildcard Directive)
10055 IGNORE (CSP: script-src unsafe-inline)
10055 IGNORE (CSP: style-src unsafe-inline)
```

Update your application code.

```bash
git add --all
git commit -m "update scanner settings"
git push -u demo main
```

## Versioning

1.0.0

## Authors

- **Rafael Sampaio**: @rafaelsampaio <https://github.com/rafaelsampaio>
- **Mauricio Ocampo**

## Acknowledgements

- Carlos Valencia - for helping me moving from EKS to AKS.
- Cristian Bayona - for discovering and solving the ELK memory problem.
