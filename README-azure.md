# CI/CD Demo with NGINX+ Ingress Controller and NGINX App Protect

**READ** the instructions before trying the commands.

If you come across any errors, make sure you have read and followed the instructions, in the order they appeard.

## Technology

- [NGINX+ Ingress Controller](https://www.nginx.com/products/nginx-ingress-controller/)
- [NGINX App Protect](https://www.nginx.com/products/nginx-app-protect/)
- [Azure Kubernetes Service (AKS)](https://azure.microsoft.com/en-us/services/kubernetes-service/)
- [Argo CD](https://argo-cd.readthedocs.io/en/stable/)
- [GitHub Actions](https://docs.github.com/en/actions)
- [OWASP ZAP](https://www.zaproxy.org/docs/docker/full-scan/)
- [OWASP Juice Shop](https://hub.docker.com/r/bkimminich/juice-shop/)
- [Elastic Stack](https://hub.docker.com/r/sebp/elk/)

## Prepare the demo

It's highly recommended to use WSL in Windows or a Linux Virtual Machine in MacOS. All steps belows are for Linux, if you are using a different OS, make sure that **you** change all commands as needed.

Install these tools using your preferred way (brew, apt, manually, ...):

- docker (must be running to prepare the demo)
- git
- helm
- jq
- kubectl
- kubectx
- azure cli

You'll need a [GitHub](https://github.com) account. If you don't have one account yet, [create one now](https://github.com/signup?ref_cta=Sign+up&ref_loc=header+logged+out&ref_page=%2F&source=header-home).

[Create](https://github.com/new) a **public** and empty repository with the name `cicd-demo`. Don't create any readme, .gitignore or other files in this repository.

Remember to [add your SSH key](https://github.com/settings/keys) to your GitHub account. If you don't know how to do this, check the guide [Connecting to GitHub with SSH](https://docs.github.com/en/authentication/connecting-to-github-with-ssh).

### TL;DR

Set `PREFIX`, `GITHUB_ACCOUNT` and `AZURE_SUBSCRIPTION`, then login to Azure.

```bash
export PREFIX=
export GITHUB_ACCOUNT=
export AZURE_SUBSCRIPTION=
export AZURE_RG=$PREFIX-cicd-demo
export AZURE_AKSCLUSTER=$PREFIX-cicd-demo
export AZURE_ACR=`echo $PREFIX`cicd
export NGINX_VERSION=2.3.0
az login --use-device-code
```

After login to Azure, **make sure** that you have your NGINX+ **credentials** (`.crt` and `.key` files) in your **home folder** and run:

```bash
az account set --subscription $AZURE_SUBSCRIPTION
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/rafaelsampaio/cicd-demo/HEAD/demo_setup_azure.sh)"
```

At the end, the script will output your NGINX Ingress public IP, Argo CD credentials and URL. Go to [Part 1](#part-1)

### Manual setup

Update the `PREFIX` to an unique name, preferably your username (alphanumeric only, no capital letters), it will also be your namespace. Set `GITHUB_ACCOUNT` and `AZURE_SUBSCRIPTION`.

```bash
export PREFIX=
export GITHUB_ACCOUNT=
export AZURE_SUBSCRIPTION=
export AZURE_RG=$PREFIX-cicd-demo
export AZURE_AKSCLUSTER=$PREFIX-cicd-demo
export AZURE_ACR=`echo $PREFIX`cicd
export NGINX_VERSION=2.3.0
```

1. Configure Azure

   Login to Azure:

   ```bash
   az login --use-device-code
   az account list --output table
   ```

   Set the default subscription:

   ```bash
   az account set --subscription $AZURE_SUBSCRIPTION
   ```

2. Build NGINX+ Ingress Controler with App Protect (WAF)

   The commands below will create a folder `cicd-demo-resources` in your home that will contain all demo resources, then it will clone the NGINX Ingress project.

   ```bash
   mkdir ~/cicd-demo-resources/
   cd ~/cicd-demo-resources/
   git clone https://github.com/nginxinc/kubernetes-ingress/
   cd kubernetes-ingress
   git checkout v$NGINX_VERSION
   ```

3. Build your ingress controller container image

   Copy your `nginx-repo.crt` and `nginx-repo.key` to `~/cicd-demo-resources/kubernetes-ingress`.
   If the files are in your home folder, use the command:

   ```bash
   cp ~/nginx-repo.crt ~/cicd-demo-resources/kubernetes-ingress
   cp ~/nginx-repo.key ~/cicd-demo-resources/kubernetes-ingress
   ```

   After that, build your image.

   ```bash
   make debian-image-nap-dos-plus PREFIX=nginx-ingress TARGET=container TAG=$NGINX_VERSION
   ```

4. Upload container image to ACR

   The command below will get the credentials to Azure Container Registry, tag and upload the NGINX+ container image.

   ```bash
   az acr login --name $AZURE_ACR
   docker tag nginx-ingress:$NGINX_VERSION $AZURE_ACR.azurecr.io/$PREFIX/nginx-ingress:$NGINX_VERSION
   docker push $AZURE_ACR.azurecr.io/$PREFIX/nginx-ingress:$NGINX_VERSION
   ```

5. Deploy NGINX+ Ingress Controller to AKS

   Update your kubectl config file with the credentials to access AKS.

   ```bash
   az aks get-credentials --name $AZURE_AKSCLUSTER --resource-group $AZURE_RG --file ~/.kube/config
   kubectx $AZURE_AKSCLUSTER
   ```

   Prepare the helm settings and deploy your NGINX to the cluster.

   ```bash
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
   ```

   To check your instance, try the commands below.

   ```bash
   kubectl describe service -n nginx-ingress $PREFIX-nginx-ingress
   ```

6. Review

   Take note of your Argo CD **admin password** and **service URL**. Also, you will need the NGINX Ingress public IP address to configure the `host` in VirtualServer and the `target` in OWASP ZAP.

   Use the commands to get the Argo CD credentials and hostname, and the NGINX Ingress IP:

   ```bash
   echo "Your Argo CD admin password: `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo`"
   echo "Your Argo CD URL: https://`kubectl get svc -n argocd argocd-server -o jsonpath='{.status.loadBalancer.ingress[0].ip}'`"
   echo "Your NGINX Ingress IP: `kubectl get svc -n nginx-ingress $PREFIX-nginx-ingress -o jsonpath='{.status.loadBalancer.ingress[0].ip}'`"
   ```

  Now you are ready to start the CI/CD demo with NGINX+ Ingress Controller with App Protect.

## Run the demo

### Part 1

Go back to your parent project folder and clone the demo repository.

```bash
cd ~/cicd-demo-resources/
git clone https://github.com/rafaelsampaio/cicd-demo.git
cd cicd-demo
echo "Your project folder: `pwd`"
```

Your application hostname will be resolved using [nip.io](https://nip.io). Use dashes (-) instead of dots (.) in your hostname with `app-` prefix, like `app-192-168-1-250.nip.io` that resolves to to `192.168.1.250`.

Use your NGINX Ingress Controller public IP address from *Step 5* to update your URLs to `app-PUBLIC-IP-ADDRESS-WITH-DASHES.nip.io`.

**EDIT** all URLs and namespace in the files below. All URLs are hardcoded, so updated them **BEFORE** the first commit.

- [argo/application.yaml](argo/application.yaml) update `name`, `repoURL`, and `namespace`. **DO NOT change** the namespace *argocd* in `metadata`
- [app/app-namespace.yaml](app/app-namespace.yaml) update `name`.
- [app/kustomization.yaml](app/kustomization.yaml) update `namespace`.
- [app/nap-policy.yaml](app/nap-policy.yaml) update `logDest`.
- [app/nap-vs.yaml](app/nap-vs.yaml) update `host` and `ingressClassName`.
- [app/nap-waf-policy.yaml](app/nap-waf-policy.yaml) update `responsePageReference` and `whitelistIpReference` links to your repo.
- [workflows/scan.yml](workflows/scan.yml) update the `target` to your NGINX service URL.

Push the code to your repository:

```bash
cd ~/cicd-demo-resources/cicd-demo
git add --all
git commit -m "first commit"
git branch -M main
git remote add demo git@github.com:$GITHUB_ACCOUNT/cicd-demo.git
git push -u demo main
```

Deploy your Application manifest to Argo CD:

```bash
kubectl apply -n argocd -f https://raw.githubusercontent.com/$GITHUB_ACCOUNT/cicd-demo/main/argo/application.yaml
```

Open Argo CD dashboard and check if your application was imported. Wait a few minutes for the first deployment. Take a time to explore Argo, your applications, the icons and what they represent. Deploy the dashboards to Kibana and take note of your instance URL at the end.

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
echo "Your Kibana URL: $KIBANA_URL"
```

Navigate to your Kibana, Dashboard -> Overview to view the events from NGINX App Protect. It should be empty at this time.

### Part 2

Create the `.github` folder and move the GitHub Actions [workflows](/workflows/) to that folder.

```bash
cd ~/cicd-demo-resources/cicd-demo
mkdir .github
mv workflows/ .github
git add --all
git commit -m "second commit - 1st scan"
git push -u demo main
```

Go to your application in Argo CD and check if your deployment was updated. It shouldn't have been. Can you tell why? Check the application settings and look for the `path` setting. Argo will only update the deployment if the changes are within the `path` in your repository.

GitHub Actions is triggered with any change in the repository. From now on, any push to the repository will start a task to scan the app and generate or update an issue in GitHub with a report. Each scan takes about 5 minutes to finish.

You can check the GitHub Actions tasks in the URL:

```bash
echo "Your project repository actions: https://github.com/$GITHUB_ACCOUNT/cicd-demo/actions"
```

You can find out the issues in the URL:

```bash
echo "Your project repository issues: https://github.com/$GITHUB_ACCOUNT/cicd-demo/issues"
```

### Part 3 - After the 1st scan

After the first scan, open your browser and go to the section Issues in your repository in GitHub. You will see a lots of vulnerabilities. You will fix some of them in this demo with **NGINX App Protect**.

Check the file [app/nap-policy.yaml](app/nap-policy.yaml) to understand how to attach a WAF policy with `apPolicy`. Also, we configure a logging policy using the `securityLog` that point to our ELK stack.

Check the file [app/nap-waf-policy.yaml](app/nap-waf-policy.yaml) to understand how to build a WAF policy with App Protect for NGINX+ Ingress Controller.

Check out the complete documentatio in [Using with NGINX App Protect](https://docs.nginx.com/nginx-ingress-controller/app-protect/configuration/) and [NGINX App Protect WAF Configuration Guide](https://docs.nginx.com/nginx-app-protect/configuration-guide/configuration/)

Edit the [app/nap-vs.yaml](app/nap-vs.yaml), **after** the `tls` settings, add the `policies` settings to enable a policy in the VirtualServer.

```yaml
  policies:
    - name: nap-policy
```

Your manifest will look similar to this example. Please, pay attention to the indentation. Also, you must replace some values with your variables.

```yaml
apiVersion: k8s.nginx.org/v1
kind: VirtualServer
metadata:
  name: juice-shop
spec:
  host: CHANGE_THIS_TO_YOUR_NGINX_HOST
  tls:
    secret: juice-shop-secret
  policies:
    - name: nap-policy
  ingressClassName: CHANGE_THIS_TO_YOUR_PREFIX-nginx-ingress  
  upstreams:
  - name: juice-shop
    service: juice-shop-svc
    port: 80
  routes:
  - path: /
    action:
      proxy: 
        upstream: juice-shop
        requestHeaders:
          pass: true
```

Update your application code.

```bash
cd ~/cicd-demo-resources/cicd-demo
git add --all
git commit -m "add nginx app protect - 2nd scan"
git push -u demo main
```

Go to your application in Argo CD and check if the updates are deployed.

### Part 4 - After the 2nd scan

NGINX Ingress Controller with App Protect will log all accesses to your application. Access the Kibana dashboard and check the logs.

Edit [app/nap-vs.yaml](app/nap-vs.yaml), **after** the `requestHeaders` settings, add the following to fix some server/application issues.

```yaml
        responseHeaders:
          hide:
            - Access-Control-Allow-Origin
            - Feature-Policy
          add:
            - name: Access-Control-Allow-Credentials
              value: "true"
            - name: Access-Control-Allow-Origin
              value: http://CHANGE_THIS_TO_YOUR_NGINX_HOST
            - name: Content-Security-Policy
              value: default-src 'self'; script-src 'self' 'unsafe-inline' cdnjs.cloudflare.com; style-src 'self' 'unsafe-inline' cdnjs.cloudflare.com
            - name: Permissions-Policy
              value: payment 'self'
```

Your manifest will look similar to this example. Please, pay attention to the indentation. Also, you must replace some values with your variables.

```yaml
apiVersion: k8s.nginx.org/v1
kind: VirtualServer
metadata:
  name: juice-shop
spec:
  host: CHANGE_THIS_TO_YOUR_NGINX_HOST
  tls:
    secret: juice-shop-secret
  policies:
    - name: nap-policy
  ingressClassName: CHANGE_THIS_TO_YOUR_PREFIX-nginx-ingress  
  upstreams:
  - name: juice-shop
    service: juice-shop-svc
    port: 80
  routes:
  - path: /
    action:
      proxy: 
        upstream: juice-shop
        requestHeaders:
          pass: true
        responseHeaders:
          hide:
            - Access-Control-Allow-Origin
            - Feature-Policy
          add:
            - name: Access-Control-Allow-Credentials
              value: "true"
            - name: Access-Control-Allow-Origin
              value: http://CHANGE_THIS_TO_YOUR_NGINX_HOST
            - name: Content-Security-Policy
              value: default-src 'self'; script-src 'self' 'unsafe-inline' cdnjs.cloudflare.com; style-src 'self' 'unsafe-inline' cdnjs.cloudflare.com
            - name: Permissions-Policy
              value: payment 'self'
```

Edit [app/nap-waf-policy.yaml](app/nap-waf-policy.yaml), change the following violations to **block** by including the `block: true` setting. Please, pay attention to the indentation.

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

Still in [app/nap-waf-policy.yaml](app/nap-waf-policy.yaml), **before** `blocking-settings`, add the following to block methods, and enable `bot-defense` too:

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

Your manifest will look similar to this example. Please, pay attention to the indentation. Also, you must replace some values with your variables.

```yaml
apiVersion: appprotect.f5.com/v1beta1
kind: APPolicy
metadata:
  name: nap-waf-policy
spec:
  policy:
    template:
      name: POLICY_TEMPLATE_NGINX_BASE  
    applicationLanguage: utf-8
    signature-sets:
    - name: All Signatures
      alarm: true
      block: true
    - name: All Response Signatures
      block: true
      alarm: true
    signatures:
    - enabled: false
      signatureId: 200020010
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
    blocking-settings:
      violations:
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
      - description: Threat Campaigns
        name: VIOL_THREAT_CAMPAIGN
      - description: Illegal meta character in value
        name: VIOL_PARAMETER_VALUE_METACHAR
      - description: Illegal Base64 value
        name: VIOL_PARAMETER_VALUE_BASE64
      - description: Illegal request content type
        name: VIOL_URL_CONTENT_TYPE
      - description: Illegal cookie length
        name: VIOL_COOKIE_LENGTH
      - description: Illegal parameter data type
        name: VIOL_PARAMETER_DATA_TYPE
      - description: Illegal POST data length
        name: VIOL_POST_DATA_LENGTH
      - description: Null in multi-part parameter value
        name: VIOL_PARAMETER_MULTIPART_NULL_VALUE
      - description: Illegal parameter
        name: VIOL_PARAMETER
      - description: Illegal HTTP status in response
        name: VIOL_HTTP_RESPONSE_STATUS
      - description: CSRF attack detected
        name: VIOL_CSRF
      - description: Modified ASM cookie
        name: VIOL_ASM_COOKIE_MODIFIED
      - description: Failed to convert character
        name: VIOL_ENCODING
      - description: Illegal request length
        name: VIOL_REQUEST_LENGTH
      - description: Illegal URL
        name: VIOL_URL
      - description: Illegal repeated parameter name
        name: VIOL_PARAMETER_REPEATED
      - description: Illegal meta character in parameter name
        name: VIOL_PARAMETER_NAME_METACHAR
      - description: Illegal parameter location
        name: VIOL_PARAMETER_LOCATION
      - description: Illegal query string length
        name: VIOL_QUERY_STRING_LENGTH
      - description: 'Data Guard: Information leakage detected'
        name: VIOL_DATA_GUARD
      - description: Illegal header length
        name: VIOL_HEADER_LENGTH
      - description: Illegal URL length
        name: VIOL_URL_LENGTH
      - description: Evasion technique detected
        name: VIOL_EVASION
      - description: Illegal meta character in header
        name: VIOL_HEADER_METACHAR
    server-technologies:
    - serverTechnologyName: AngularJS
    - serverTechnologyName: Express.js
    - serverTechnologyName: JavaScript
    - serverTechnologyName: MongoDB
    - serverTechnologyName: Node.js
    - serverTechnologyName: SQLite
    - serverTechnologyName: jQuery
    urls:
    - attackSignaturesCheck: true
      clickjackingProtection: false
      description: ''
      disallowFileUploadOfExecutables: false
      html5CrossOriginRequestsEnforcement:
        enforcementMode: disabled
      isAllowed: true
      mandatoryBody: false
      method: "*"
      methodsOverrideOnUrlCheck: false
      name: "/#/login"
      protocol: http
      type: explicit
      urlContentProfiles:
      - headerName: "*"
        headerOrder: default
        headerValue: "*"
        type: apply-value-and-content-signatures
      - headerName: Content-Type
        headerOrder: '1'
        headerValue: "*form*"
        type: form-data
      - contentProfile:
          name: Default
        headerName: Content-Type
        headerOrder: '2'
        headerValue: "*json*"
        type: json
      - contentProfile:
          name: Default
        headerName: Content-Type
        headerOrder: '3'
        headerValue: "*xml*"
        type: xml
    data-guard:
      creditCardNumbers: true
      enabled: true
      lastCcnDigitsToExpose: 4
      lastSsnDigitsToExpose: 4
      maskData: true
      usSocialSecurityNumbers: true
    responsePageReference:
      link: "https://raw.githubusercontent.com/CHANGE_THIS_TO_YOUR_REPO/cicd-demo/main/app/nap-response-page.json"
    whitelistIpReference:
      link: "https://raw.githubusercontent.com/CHANGE_THIS_TO_YOUR_REPO/cicd-demo/main/app/nap-ip-allowlist.json"
    enforcementMode: blocking
    name: nap-waf-policy
```

Update your application code.

```bash
cd ~/cicd-demo-resources/cicd-demo
git add --all
git commit -m "update nginx app protect - 3rd scan"
git push -u demo main
```

Go to your application in Argo CD and check if the updates are deployed. Each and everytime the application code changes, Argo CD will deploy the new version and GitHub Actions will scan the application. So, the WAF settings can be implemented by the Security Team without locking, blocking, or breaking up the pipeline for the Development Team. A developer can include new features and the Security Team can test the applied policies looking for false-positives and fine tunings.

From the dashboard we demonstrate how operations activities can be integrated with security settings.

### Part 5 - After the 3rd scan

Some alerts triggered by the scanner are related to the content and they are not necessarily a matter for the Security Team.

So, we close the issue and forwarding the issue to be fixed by the dev team.

#### Optional step

Edit [.zap/rules.tsv](.zap/rules.tsv) and add the following lines to ignore some rules, separated by **tab** instead of **spaces**:

```text
10096 IGNORE (Timestamp Disclosure - Unix)
10055 IGNORE (CSP: Wildcard Directive)
10055 IGNORE (CSP: script-src unsafe-inline)
10055 IGNORE (CSP: style-src unsafe-inline)
```

Update your application code.

```bash
cd ~/cicd-demo-resources/cicd-demo
git add --all
git commit -m "update scanner settings"
git push -u demo main
```

## Finish the demo

```bash
az group delete $AZURE_RG
```

## Versioning

1.0.0

## Authors

- **Rafael Sampaio**: @rafaelsampaio <https://github.com/rafaelsampaio>
- **Mauricio Ocampo**

## Acknowledgements

- Carlos Valencia - for helping me moving from EKS to AKS.
- Cristian Bayona - for discovering and solving the ELK memory problem.
