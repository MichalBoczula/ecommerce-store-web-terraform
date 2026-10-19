# EcommerceStore Angular hosting

Terraform for a temporary portfolio deployment of
[ecommerce-store-web](https://github.com/MichalBoczula/ecommerce-store-web).
Create the hosting, upload a production Angular build, capture the portfolio
material, and destroy this stack when finished. Deployment and destruction are
manual; GitHub checks never sign in to Azure or apply resources.

## Ownership and cost

| Managed here | Default |
| --- | --- |
| Resource group | `rg-ecommercestore-web-dev` |
| Static Web App | `swa-ecommercestore-web-dev` |
| Plan | Standard, with preview environments disabled |
| Region | West Europe; static content is distributed globally |
| Optional production API link | Existing ACA BFF; disabled until supplied |

Standard supports the later linked ACA backend and was approximately **USD 9 per
730-hour month** when reviewed on 18 October 2026. It is billed for provisioned
time (approximately USD 0.30/day); inactivity does not stop the charge. Destroy
the web stack after collecting screenshots and demos. Bandwidth overage, custom
domains and other services are separate. No enterprise edge add-on is enabled.
See [SWA pricing](https://azure.microsoft.com/en-us/pricing/details/app-service/static/).

This root creates no ACA environment, VNet, SQL database, photo account, Key Vault,
or identity. Products owns its database and photos; the BFF stack owns its app.
Destroying web removes the SWA, its deployed files and optional backend link,
then its dedicated resource group. It leaves the independent state account and
other application stacks in place. Don't put unrelated resources in the web RG.

The separately managed backend is:

```text
Account:   stecomtfstatemb261011
Container: tfstate
Key:       web/development.terraform.tfstate
```

Products uses `products/development.terraform.tfstate`; the BFF will have its own
key. Never reuse either application's key for this root. Separate environments
also need separate keys. Keep the state blob after destroy. Recreating a site
can produce a different generated hostname; read the new output each time.

## 1. Prepare the local checkout

Use PowerShell 7.2+, Azure CLI, Terraform 1.16.5, and Node.js 22.12+ with npm
(Node 22 is used for the Windows upload CLI check). Linux uploads can also need
the SWA CLI's native keychain build prerequisites, including `pkg-config` and
`libsecret-1-dev`; `-BuildOnly` does not install the upload CLI.
Keep the two repositories
as separate checkouts, for example:

```text
D:\Programowanie\Apps\ecommerce-store-web-terraform
D:\Programowanie\Apps\ecommerce-store-web
```

```powershell
Set-Location D:\Programowanie\Apps\ecommerce-store-web-terraform
$ErrorActionPreference = 'Stop'
$ecommerceTerraform = Join-Path $env:LOCALAPPDATA `
    'Programs\Terraform\1.16.5\terraform.exe'
if (-not (Test-Path -LiteralPath $ecommerceTerraform)) { throw 'Terraform executable not found' }

az login
if ($LASTEXITCODE -ne 0) { throw 'Azure login failed' }
az account set --subscription 'fcbf086b-8ce4-4ca5-a3d7-0c56489e25f6'
if ($LASTEXITCODE -ne 0) { throw 'Subscription selection failed' }
$env:TF_VAR_subscription_id = az account show --query id --output tsv
if ($LASTEXITCODE -ne 0) { throw 'Subscription lookup failed' }

# Create local inputs only when absent; never overwrite a working backend.
if (-not (Test-Path -LiteralPath .\backend.hcl)) {
    Copy-Item .\backend.hcl.example .\backend.hcl
}
if (-not (Test-Path -LiteralPath .\terraform.tfvars)) {
    Copy-Item .\terraform.tfvars.example .\terraform.tfvars
}
Get-Content .\backend.hcl
```

Check that the displayed account/container/key match the web backend above.
Only `subscription_id` is required; web does not need the SQL password or
operator object ID. Your Azure identity needs permission to manage this web RG,
read the SWA deployment token, register `Microsoft.Web` if necessary, and access
the existing state container using Entra data-plane permissions. No account key
or GitHub repository-admin token is supplied to Terraform.

## 2. Validate, plan, and provision hosting

```powershell
& $ecommerceTerraform init '-backend-config=backend.hcl' '-lockfile=readonly'
if ($LASTEXITCODE -ne 0) { throw 'Initialization failed' }
& $ecommerceTerraform fmt '-check' '-recursive'
if ($LASTEXITCODE -ne 0) { throw 'Formatting check failed' }
& $ecommerceTerraform validate
if ($LASTEXITCODE -ne 0) { throw 'Validation failed' }
& $ecommerceTerraform test
if ($LASTEXITCODE -ne 0) { throw 'Mocked tests failed' }
& $ecommerceTerraform plan '-input=false' '-out=web-hosting.tfplan'
if ($LASTEXITCODE -ne 0) { throw 'Hosting planning failed' }
```

For a fresh default stack expect **2 to add, 0 to change, 0 to destroy**: the RG
and SWA. Review the plan and confirm Standard/West Europe, the web names and no
BFF link. A subsequent reviewed backend link adds one resource. If init reports
a backend change, verify the account and **web** key first; don't migrate another
application's state or delete the state to work around it.

Apply the reviewed plan separately:

```powershell
& $ecommerceTerraform apply web-hosting.tfplan
if ($LASTEXITCODE -ne 0) { throw 'Hosting apply failed; keep state and inspect the error' }
& $ecommerceTerraform output -json web_deployment
if ($LASTEXITCODE -ne 0) { throw 'Deployment output lookup failed' }
```

The output contains resource names and the generated HTTPS URL. It contains no
deployment token. An empty SWA is not the Angular application: upload the build
in the next step. AzureRM stores its computed SWA API key in remote Terraform
state, so keep state and saved plans private and restrict backend access.

## 3. Build and upload Angular

First review the Angular checkout and its own checks. The uploader uses `npm ci`
and a production build, stages only `browser/` files, and copies this repository's
`web/staticwebapp.config.json` into the deployment artifact. It does not change
Angular source, its API clients, or its application configuration.

To check the build without using Terraform outputs, Azure credentials, or an
upload:

```powershell
.\scripts\Publish-Web.ps1 `
    -WebProjectPath D:\Programowanie\Apps\ecommerce-store-web `
    -BuildOnly
```

Deploy after provisioning the SWA:

```powershell
.\scripts\Publish-Web.ps1 `
    -WebProjectPath D:\Programowanie\Apps\ecommerce-store-web `
    -TerraformPath $ecommerceTerraform
```

The helper reads the targets from this root's Terraform output, builds Angular,
retrieves the deployment token using your Azure login, and uploads explicitly
to **production** with SWA CLI **2.0.10**. The token is passed in the environment,
never in process arguments or a file, and the previous environment value is
restored after success or failure. The uploader checks every native exit code.
Don't run it with shell tracing that would expose secrets.

The first run of `npx` downloads the pinned CLI and its deployment client.
Compiled files are kept in ignored `.artifacts/site`. Redeploy this same way
after an application change. GitHub workflows in this repository run checks
only; they don't automatically deploy or create paid resources.

## 4. Verify static hosting, then integrate the BFF

```powershell
$raw = (& $ecommerceTerraform output -json web_deployment) -join "`n"
if ($LASTEXITCODE -ne 0) { throw 'Deployment output lookup failed' }
$web = $raw | ConvertFrom-Json

$home = Invoke-WebRequest $web.base_url -TimeoutSec 30
if ($home.StatusCode -ne 200 -or $home.Content -notmatch '<app-root') {
    throw 'The Angular document was not served'
}
Start-Process $web.base_url
```

Open an actual Angular details route from the app and refresh it. It should serve
Angular rather than a platform 404. Inspect browser Network/Console for failed
assets. Missing `/api`, `/backend` and asset requests are excluded from SPA
fallback so errors cannot silently become `200` responses containing index HTML.

**Static hosting is the first checkpoint.** The current Angular app calls
`/backend`, while local/container hosting uses Nginx to strip that prefix. SWA
does not execute `nginx.conf`. Before the complete Products list/photo demo:

1. Deploy the BFF into the same ACA environment as Products, with ingress
   reachable by SWA. Products can keep internal ingress.
2. Configure the BFF's Products destination with its ACA internal address.
3. Adjust Angular to call same-origin `/api`, and make the BFF accept that prefix
   before forwarding to its existing routes. SWA forwards the **entire** `/api`
   path; it does not strip it. Coordinate this with generated-client checks in
   the application repositories rather than editing generated files here.
4. Add the existing BFF resource ID and its actual region to local tfvars:

```hcl
bff_backend = {
  resource_id = "/subscriptions/<your-subscription-uuid>/resourceGroups/rg-ecommercestore-bff-dev/providers/Microsoft.App/containerApps/ca-ecommercestore-bff-dev"
  region      = "northeurope"
}
```

Review a fresh plan/apply, redeploy the adjusted Angular build, and verify a
same-origin `/api/mobile-phones?amount=15` response, rendered product cards, direct
details refresh and an anonymous Blob photo. Before exposing mutation endpoints,
complete the intended application access policy; CORS is not authorization.

The optional Terraform child resource manages the SWA link, not the BFF app or
its environment. Azure's linking service configures `Azure Static Web Apps
(Linked)` authentication on the BFF. Declare ownership of that integration when
implementing the BFF stack. Unlinking/destroying SWA does **not** automatically
remove the BFF's linked authentication provider or open the BFF anonymously.
It is separate from the later end-user Entra ID work.

See [linked ACA APIs](https://learn.microsoft.com/en-us/azure/static-web-apps/apis-container-apps),
[SWA configuration](https://learn.microsoft.com/en-us/azure/static-web-apps/configuration),
and [the upload CLI](https://learn.microsoft.com/en-us/azure/static-web-apps/static-web-apps-cli-deploy).

## 5. Capture the portfolio material and destroy web

Save screenshots, demo recordings, architecture notes and validation results
before deleting the site. Keep application/photo source in their repositories.
The generated URL stops working after destruction. Destroying web alone leaves
Products, BFF and any paid shared networking running: tear down those stacks
separately when the full exercise is finished, with consumers before shared
resources. This root never deletes the shared state storage.

Use this same directory, backend and `TF_VAR_subscription_id`; retain all local
tfvars (including an optional BFF link) until cleanup finishes. For a new shell,
repeat the Azure session and Terraform executable setup from step 1.

```powershell
$raw = (& $ecommerceTerraform output -json web_deployment) -join "`n"
if ($LASTEXITCODE -ne 0) { throw 'Read the web targets before the first destroy plan' }
$web = $raw | ConvertFrom-Json
& $ecommerceTerraform plan '-destroy' '-input=false' '-out=web-destroy.tfplan'
if ($LASTEXITCODE -ne 0) { throw 'Destroy planning failed; nothing was deleted' }
```

Review that only web-owned resources and its optional link are being removed.
Then run:

```powershell
& $ecommerceTerraform apply web-destroy.tfplan
if ($LASTEXITCODE -ne 0) { throw 'Destroy stopped; keep state and inspect the error' }
& $ecommerceTerraform state list
if ($LASTEXITCODE -ne 0) { throw 'State verification failed' }
az group exists --subscription $env:TF_VAR_subscription_id --name $web.resource_group_name
if ($LASTEXITCODE -ne 0) { throw 'Resource group verification failed' }
```

Expect an empty state list and `false` for the RG. If Azure reports
a polling error, check the actual resource status and rerun a fresh destroy plan;
keep state rather than using `state rm` to hide a live resource. Old saved plans
are disposable; create new plans for every later deployment/destroy operation.

## Checks without Azure provisioning

```powershell
& $ecommerceTerraform init '-backend=false' '-input=false' '-lockfile=readonly'
& $ecommerceTerraform fmt '-check' '-recursive'
& $ecommerceTerraform validate
& $ecommerceTerraform test
pwsh -NoProfile -File .\tests\Test-PublishWeb.ps1
```

Run these in a separate check-only checkout if you have initialized the real
backend already. CI uses a fresh checkout, mocked Terraform providers, and
offline uploader tests on Linux and Windows. Windows CI also installs the pinned
SWA CLI and checks its deployment command. These checks verify configuration,
tool startup and failure handling; the Azure/browser acceptance checks remain manual.
