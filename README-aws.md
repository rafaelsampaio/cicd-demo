# CI/CD Demo with NGINX+ Ingress Controller and NGINX App Protect

## How to setup the demo

### Technology

- [NGINX+ Ingress Controller](https://www.nginx.com/products/nginx-ingress-controller/)
- [NGINX App Protect](https://www.nginx.com/products/nginx-app-protect/)
- [AWS EKS](https://aws.amazon.com/eks/)
- [ArgoCD](https://argo-cd.readthedocs.io/en/stable/)
- [GitHub Actions](https://docs.github.com/en/actions)
- [OWASP ZAP](https://www.zaproxy.org/docs/docker/full-scan/)
- [OWASP Juice Shop](https://hub.docker.com/r/bkimminich/juice-shop/)
- [Elastic Stack](https://hub.docker.com/r/sebp/elk/)

### Demo setup

1. Install all required tools and set your own AWS credentials and vars. Don't forget to update the ***PREFIX*** to your namespace and the ***TAG_VALUE*** to your email.

    Install these tools using your prefered way:
    - git
    - helm
    - jq
    - kubectl
    - kubectx
    - awscli
    - eksctl

    Set your env var. Please, use your username as the `PREFIX` and `namespace`:

    ```bash
    export PREFIX=CHANGE_THIS_TO_YOUR_NAMESPACE
    export GITHUB_ACCOUNT=CHANGE_THIS_TO_YOUR_GITHUB_ACCOUNT
    export AWSREGION=us-west-2
    export TAG_KEY="Owner"
    export TAG_VALUE="CHANGE_THIS_TO_YOUR_EMAIL"
    export NGINX_VERSION=2.2.1
    ```

    If you don't have an account in [GitHub](https://github.com), create one now. Also, [create](https://github.com/new) a **public** repository with the name `cicd-demo`.

2. Configure AWS.

    ```bash
    aws configure
    ```

    Update the region and output settings:

    ```text
    Default region name [None]: us-west-2
    Default output format [None]: json
    ```

3. Create AWS EKS - this will take a looooong time. **For lab admin only. SKIP the procedure below if you are NOT the lab administrator.**

    You will need to deploy a cluster to each account that your users belongs to.

    ```bash
    export EKSCLUSTER_NAME=$PREFIX-ekscluster
    eksctl create cluster \
      --name $EKSCLUSTER_NAME \
      --nodes 10 \
      --instance-selector-vcpus=4 \
      --instance-selector-memory=16 \
      --with-oidc \
      --region $AWSREGION \
      --tags "$TAG_KEY=$TAG_VALUE" \
      --full-ecr-access
    eksctl get cluster $EKSCLUSTER_NAME --region $AWSREGION
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

6. Upload NGINX image to ECR.

    ```bash
    aws ecr create-repository --repository-name $PREFIX/nginx-ingress --region $AWSREGION --tags '[{"Key":"'$TAG_KEY'","Value":"'$TAG_VALUE'"},{"Key":"Name","Value":"'$PREFIX'-ecr"}]'
    aws ecr describe-repositories --region $AWSREGION --output json --repository-names $PREFIX/nginx-ingress
    ECRURI=$(aws ecr describe-repositories --region $AWSREGION --output json --repository-names $PREFIX/nginx-ingress | jq -r ".repositories[0] .repositoryUri")
    echo $ECRURI
    aws ecr get-login-password --region $AWSREGION | docker login --username AWS --password-stdin $ECRURI
    docker tag nginx-ingress:$NGINX_VERSION $ECRURI:$NGINX_VERSION
    docker push $ECRURI:$NGINX_VERSION
    ```

7. Deploy NGINX+ IC to EKS. Take note of your ***NGINX service URL***.

    Ask you lab admin for the EKS cluster name and change the var.

    ```bash
    export EKSCLUSTER_NAME=ASK_YOUR_ADMIN_FOR_THE_EKSCLUSTER_NAME
    aws eks --region $AWSREGION update-kubeconfig --name $EKSCLUSTER_NAME
    ```

    Then deploy your NGINX to the cluster.

    ```bash
    #git clone https://github.com/nginxinc/kubernetes-ingress/
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
      --set controller.image.repository=$ECRURI \
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
      --set controller.service.annotations."service\.beta\.kubernetes\.io\/aws-load-balancer-backend-protocol"="tcp" \
      --set controller.service.annotations."service\.beta\.kubernetes\.io\/aws-load-balancer-proxy-protocol"="*" \
      --set controller.config.proxy-protocol="true" \
      --set controller.config.real-ip-header="proxy_protocol" \
      --set controller.config.set-real-ip-from="0.0.0.0/0"
    ```

    To check your instance, try these commands:

    ```bash
    helm list -n nginx-ingress
    kubectl get svc -n nginx-ingress $PREFIX-nginx-ingress -o jsonpath="{.status.loadBalancer.ingress[0].hostname}"
    ```

    Edit the ConfigMap of your NGINX instance:

    ```bash
    kubectl edit configmaps -n nginx-ingress $PREFIX-ingress-nginx-ingress
    ```

    and add the annotations:

    ```yaml
    metadata:
      annotations:
        service.beta.kubernetes.io/aws-load-balancer-backend-protocol: tcp
        service.beta.kubernetes.io/aws-load-balancer-proxy-protocol: '*'
    ```

    Edit the Service of your NGINX instance:

    ```bash
    kubectl edit svc -n nginx-ingress $PREFIX-nginx-ingress
    ```

    and add the data settings:

    ```yaml
    data:
      proxy-protocol: "True"
      set-real-ip-from: 0.0.0.0/0
    ```

8. Deploy ArgoCD to EKS. Take note of your ArgoCD ***admin password*** and ***service URL***. There will be only one instance of ArgoCD.

    For lab admin only:

    ```bash
    kubectl create namespace argocd
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
    kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'
    ```

    Get the ArgoCD credentials and hostname:

    ```bash
    kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
    kubectl get svc -n argocd argocd-server -o jsonpath="{.status.loadBalancer.ingress[0].hostname}" 
    ```

### Demo

#### Part 1

First of all, clone the demo repository, update all URLs and namespace in the files below. All URLs are hardcoded, so updated them before the first commit and push.

```bash
git clone https://github.com/rafaelsampaio/cicd-demo.git
cd cicd-demo
```

- [application.yaml](argo/application.yaml) update to your GitHub account.
- [app-namespace.yaml](app/app-namespace.yaml) update to your namespace.
- [kustomization.yaml](app/kustomization.yaml) update to your namespace.
- [nap-policy.yaml](/app/nap-policy.yaml) update to your namaspace.
- [nap-vs.yaml](app/nap-vs.yaml) update the *host* to your NGINX service URL.
- [nap-waf-policy.yaml](app/nap-waf-policy.yaml) update the *responsePageReference* and *whitelistIpReference* links to your repo.
- [scan.yaml](workflows/scan.yml) update the *target* to your NGINX service URL.

Move the GitHub Actions workflow to `.github` folder.

```bash
mkdir .github
mv workflows/ .github
```

Push the code to your repository:

```bash
git remote add demo git@github.com:$GITHUB_ACCOUNT/cicd-demo.git
git push -u -f demo master
```

Deploy Application config to ArgoCD:

 ```bash
 kubectl apply -n argocd -f https://raw.githubusercontent.com/$GITHUB_ACCOUNT/cicd-demo/main/argo/application.yaml
 ```

Wait a few seconds for the first deployment, then check your Application in Argo. Using your namespace, get your Kibana URL to deploy the dashboards:

```bash
KIBANA_HOST=`kubectl get svc -n $PREFIX elk-kibana-svc -o jsonpath="{.status.loadBalancer.ingress[0].hostname}"`
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
```

#### Part 2

Make sure there is no opened issue for the ***ZAP Full Scan Report***.
Do a simple change, like add a file, add a dummy content in this file, whatever, then commit and push to the repo. That will trigger a app scan and generate a issue with the report.

#### Part 3 - After the 1st scan

After the first scan, we notice a lots of vulnerabilities that could be easy fixed with **NGINX App Protect**.
In [nap-vs.yaml](app/nap-vs.yaml), after `tls` settings block, to enable a policy in the NGINX VirtualServer, add the following:

```yaml
  policies:
  - name: nap-policy
```

#### Part 4 - After the 2nd scan

To access the Kibana dashboard, point to your NGINX service URL using port 5601.
When we check a reduced number of vulnerabilities, some of them related to content and settings in application and server, and the dashboard show some alerts.
We can fix some server/application issues in NGINX, by adding the following to [nap-vs.yaml](app/nap-vs.yaml), after the `requestHeaders` settings:

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

After this, we demonstrate that the WAF settings can be implemented by the Security Team without locking, blocking, or breaking up the pipeline for the Development Team. From the dashboard we demonstrate how operations activities can be integrated with security settings.

### Part 5 - After the 3rd scan

Some alerts triggered by the scanner are related to the content and they are not necessarily a matter for the Security Team.
So, we close the issue and forwarding the issue to be fixed by the dev team.

#### Optional step

Add to ignore settings to the [.zap/rules.tsv](.zap/rules.tsv), separated by **tab**:

```text
10096 IGNORE (Timestamp Disclosure - Unix)
10055 IGNORE (CSP: Wildcard Directive)
10055 IGNORE (CSP: script-src unsafe-inline)
10055 IGNORE (CSP: style-src unsafe-inline)
```

## Versioning

1.0.0

## Authors

- **Rafael Sampaio**: @rafaelsampaio <https://github.com/rafaelsampaio>
- **Mauricio Ocampo**

## Acknowledgements

- Carlos Valencia - for helping me with the integration of NGINX IC and EKS, especially resolving the issue of real IP addresses.
- Cristian Bayona - for discovering and solving the ELK memory problem.
