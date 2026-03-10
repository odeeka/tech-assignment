# EKS with Karpenter, Graviton & Spot Instances

Terraform code that deploys an EKS cluster with [Karpenter](https://karpenter.sh/) for autoscaling, supporting **x86** and **Graviton (ARM64)** instances with **Spot** and **On-Demand** capacity.

## Components

| Component | What it does |
| - | - |
| **VPC** | Private/public subnets across 3 AZs, single NAT gateway |
| **EKS Cluster** | Managed Kubernetes `1.35` control plane |
| **System Node Group** | 2× `t4g.medium` Graviton (Bottlerocket OS) - runs Karpenter and system addons |
| **Karpenter** | Autoscaler that provisions nodes on demand based on pod requirements |
| **NodePool** | Allows `c`/`m`/`r` families, gen 6+, both architectures, Spot + On-Demand |
| **EC2NodeClass** | Bottlerocket AMI, auto-discovers subnets and security groups via tags |

## Project Structure

```text
terraform/
├── 01-base-infra/          # Stage 1 - VPC, EKS, Karpenter IAM/SQS (AWS provider only)
├── 02-cluster-config/      # Stage 2 - Karpenter Helm chart, NodePool, EC2NodeClass
├── examples/               # Sample K8s deployments (x86, Graviton, Spot)
├── root.hcl                # Shared Terragrunt config
└── mise.toml               # Tool versions
```

**Why two stages?** The Helm/kubectl providers need a running cluster to plan against. Stage 1 creates the cluster; Stage 2 configures it. Terragrunt handles the dependency automatically.

## Prerequisites

- AWS account with permissions for VPC, EKS, IAM, SQS, EC2
- AWS CLI v2
- Tools: Terraform, Terragrunt, kubectl, Helm

All tool versions are pinned in `mise.toml`. If you use [mise](https://mise.jdx.dev/):

```bash
mise install && eval "$(mise activate)"
```

## Authentication

### AWS credentials (for Terraform and kubectl)

Terraform and the Helm/kubectl providers authenticate to AWS using the standard AWS credential chain.

Configure one of the following **before** running any Terraform commands:

**Option A - Environment variables (simplest):**

```bash
export AWS_ACCESS_KEY_ID="AKIA..."
export AWS_SECRET_ACCESS_KEY="wJal..."
export AWS_REGION="eu-central-1"
```

**Option B - Named profile:**

```bash
aws configure --profile my-profile
export AWS_PROFILE=my-profile
```

**Option C - SSO (recommended for organizations):**

```bash
aws sso login --profile my-sso-profile
export AWS_PROFILE=my-sso-profile
```

Verify your identity before deploying:

```bash
aws sts get-caller-identity
```

### EKS cluster access (for kubectl)

After Stage 1 completes, the IAM identity that ran `terraform apply` is automatically granted **cluster admin** access (via `enable_cluster_creator_admin_permissions = true` in the EKS module).

To configure kubectl:

```bash
aws eks update-kubeconfig --region eu-central-1 --name opsfleet-eks
```

This writes a kubeconfig entry that uses `aws eks get-token` for short-lived authentication - no static tokens or certificates are stored.

### How provider auth works internally

| Provider | Auth method |
| - | - |
| **AWS** (both stages) | Standard AWS credential chain (env vars / profile / instance role) |
| **Helm** (Stage 2) | Calls `aws eks get-token` via exec plugin - same IAM identity |
| **kubectl** (Stage 2) | Same exec plugin as Helm |

All three providers use the same IAM identity. No separate service accounts or tokens are needed.

## Deploy

### Step 1 - Configure variables

```bash
cd terraform/
cp 01-base-infra/terraform.tfvars.example  01-base-infra/terraform.tfvars
cp 02-cluster-config/terraform.tfvars.example  02-cluster-config/terraform.tfvars
# Edit the .tfvars files if you want to change region, cluster name, etc.
```

### Step 2 - Apply

**With Terragrunt (recommended):**

```bash
terragrunt run --all -- init
terragrunt run --all -- validate
terragrunt run --all -- plan
terragrunt run --all -- apply
```

This deploys Stage 1 first, then automatically passes outputs to Stage 2.

**With plain Terraform:**

```bash
# Stage 1
cd 01-base-infra
terraform init && terraform apply

# Stage 2 - pass Stage 1 outputs as variables
cd ../02-cluster-config
terraform init
terraform apply \
  -var="cluster_endpoint=$(terraform -chdir=../01-base-infra output -raw cluster_endpoint)" \
  -var="cluster_certificate_authority_data=$(terraform -chdir=../01-base-infra output -raw cluster_certificate_authority_data)" \
  -var="karpenter_queue_name=$(terraform -chdir=../01-base-infra output -raw karpenter_queue_name)" \
  -var="karpenter_node_iam_role_name=$(terraform -chdir=../01-base-infra output -raw karpenter_node_iam_role_name)"
```

Deployment takes ~20 minutes (EKS cluster creation is the longest part).

### Step 3 - Connect to the cluster

```bash
aws eks update-kubeconfig --region eu-central-1 --name opsfleet-eks
```

The exact command is also shown in the Stage 1 output (`configure_kubectl`).

SAMPLE OUTPUT

```text
arn:aws:eks:eu-central-1:<ACCOUNT_ID>:cluster/opsfleet-eks
```

### Step 4 - Verify

```bash
kubectl get nodes                                                    # system nodes
kubectl get pods -n kube-system -l app.kubernetes.io/name=karpenter  # Karpenter pods
kubectl get nodepools,ec2nodeclasses                                 # Karpenter CRDs

helm ls -aA                                                          # Check installed Helm release
```

SAMPLE OUTPUT

```text
NAME                                           STATUS   ROLES    AGE     VERSION
ip-10-0-22-140.eu-central-1.compute.internal   Ready    <none>   2m24s   v1.35.2-eks-f69f56f
ip-10-0-38-162.eu-central-1.compute.internal   Ready    <none>   2m21s   v1.35.2-eks-f69f56f

NAME                         READY   STATUS    RESTARTS   AGE
karpenter-6f5fb7b7f9-d7bjc   1/1     Running   0          47s
karpenter-6f5fb7b7f9-m94g8   1/1     Running   0          47s

NAME                            NODECLASS   NODES   READY   AGE
nodepool.karpenter.sh/default   default     0       True    47s

NAME                                     READY   AGE
ec2nodeclass.karpenter.k8s.aws/default   True    47s

NAME     	NAMESPACE  	REVISION	UPDATED                                	STATUS  	CHART          	APP VERSION
karpenter	kube-system	1       	2026-03-10 22:40:02.371769327 +0100 CET	deployed	karpenter-1.9.0	1.9.0 
```

## Terraform State

Both stages use **local state** by default (`terraform.tfstate` in each stage directory). This is fine for individual use, but for teams or production you need a remote backend with locking.

### Option A - S3 + DynamoDB (AWS-native)

Create a state bucket and lock table (one-time setup, can be done via a separate Terraform root or manually):

```bash
aws s3api create-bucket --bucket my-org-terraform-state --region eu-central-1 \
  --create-bucket-configuration LocationConstraint=eu-central-1
aws s3api put-bucket-versioning --bucket my-org-terraform-state \
  --versioning-configuration Status=Enabled
aws dynamodb create-table --table-name terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST
```

Then add a backend block to each stage's provider config:

```hcl
# In 01-base-infra/provider.tf (and similarly for 02-cluster-config/versions.tf)
terraform {
  backend "s3" {
    bucket         = "my-org-terraform-state"
    key            = "eks/01-base-infra/terraform.tfstate"  # unique per stage
    region         = "eu-central-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}
```

Or let Terragrunt generate it automatically in `root.hcl`:

```hcl
remote_state {
  backend = "s3"
  config = {
    bucket         = "my-org-terraform-state"
    key            = "${path_relative_to_include()}/terraform.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}
```

This gives each stage its own state key (`01-base-infra/terraform.tfstate`, `02-cluster-config/terraform.tfstate`) under a single bucket.

### Option B - Terraform Cloud / HCP Terraform

Use Terraform Cloud workspaces for state, locking, and optional remote execution:

```hcl
terraform {
  cloud {
    organization = "my-org"
    workspaces {
      name = "eks-base-infra"   # or "eks-cluster-config" for Stage 2
    }
  }
}
```

Set the `TF_TOKEN_app_terraform_io` env var or run `terraform login`. Cross-stage output sharing is done via `tfe_outputs` data source or Terragrunt dependency (as already configured).

### Option C - Spacelift

[Spacelift](https://spacelift.io/) provides orchestration, policy-as-code, and drift detection on top of state management:

1. Create two **stacks** - one per stage (`01-base-infra`, `02-cluster-config`).
2. Set the Stage 2 stack to **depend on** Stage 1 (Spacelift triggers Stage 2 after Stage 1 succeeds).
3. Use output/input references between stacks to pass cluster endpoint, CA cert, etc.
4. Spacelift manages state internally - no S3 bucket or DynamoDB table needed.

This replaces both Terragrunt orchestration and remote state configuration with a single platform.

### Comparison

| | S3 + DynamoDB | Terraform Cloud | Spacelift |
| - | - | - | - |
| **State storage** | S3 bucket (you manage) | Managed by HashiCorp | Managed by Spacelift |
| **Locking** | DynamoDB | Built-in | Built-in |
| **Cross-stage deps** | Terragrunt `dependency` or `terraform_remote_state` | `tfe_outputs` data source | Stack dependencies |
| **Orchestration** | Terragrunt / CI pipeline | Run triggers between workspaces | Built-in stack dependencies |
| **Cost** | S3/DynamoDB (near-zero) | Free tier for small teams | Free tier for small teams |
| **Best for** | AWS-only, full control | Multi-cloud, HashiCorp ecosystem | Policy-heavy, drift detection |

## Running Workloads

Use `nodeSelector` to control where pods run. Karpenter provisions the right instance automatically.

| Scenario | nodeSelector | Example |
| - | - | - |
| **x86 only** | `kubernetes.io/arch: amd64` | `kubectl apply -f examples/x86-deployment.yaml` |
| **Graviton only** | `kubernetes.io/arch: arm64` | `kubectl apply -f examples/graviton-deployment.yaml` |
| **Spot only** | `karpenter.sh/capacity-type: spot` | `kubectl apply -f examples/spot-deployment.yaml` |
| **Graviton + Spot** | Both of the above | `kubectl apply -f examples/graviton-spot-deployment.yaml` |
| **Auto (cheapest)** | *(none)* | Karpenter picks the most cost-efficient option |

Example - force a deployment onto Graviton Spot instances:

```yaml
spec:
  template:
    spec:
      nodeSelector:
        kubernetes.io/arch: arm64
        karpenter.sh/capacity-type: spot
      containers:
        - name: app
          image: my-app:latest   # must be a multi-arch or arm64 image
```

> **Note:** Graviton requires ARM64-compatible images. Most official Docker Hub / ECR Public images are multi-arch.

### Testing Karpenter end-to-end

**1. Deploy an x86 workload - Karpenter provisions an AMD64 node:**

```bash
kubectl apply -f examples/x86-deployment.yaml
kubectl get pods -w                              # watch Pending -> Running
kubectl get nodes -L kubernetes.io/arch          # new amd64 node appears
```

**2. Deploy a Graviton workload - Karpenter provisions an ARM64 node:**

```bash
kubectl apply -f examples/graviton-deployment.yaml
kubectl get pods -w
kubectl get nodes -L kubernetes.io/arch          # new arm64 node appears
```

SAMPLE OUTPUT (with new node)

```text
NAME                                           STATUS   ROLES    AGE     VERSION               INTERNAL-IP   EXTERNAL-IP   OS-IMAGE                                KERNEL-VERSION                   CONTAINER-RUNTIME
ip-10-0-22-140.eu-central-1.compute.internal   Ready    <none>   7m25s   v1.35.2-eks-f69f56f   10.0.22.140   <none>        Amazon Linux 2023.10.20260216           6.12.68-92.122.amzn2023.x86_64   containerd://2.1.5
ip-10-0-37-230.eu-central-1.compute.internal   Ready    <none>   31s     v1.35.0-eks-ac2d5a0   10.0.37.230   <none>        Bottlerocket OS 1.56.0 (aws-k8s-1.35)   6.12.68                          containerd://2.1.6+bottlerocket
ip-10-0-38-162.eu-central-1.compute.internal   Ready    <none>   7m22s   v1.35.2-eks-f69f56f   10.0.38.162   <none>        Amazon Linux 2023.10.20260216           6.12.68-92.122.amzn2023.x86_64   containerd://2.1.5
```

**3. Deploy a Graviton + Spot workload (best price/performance):**

```bash
kubectl apply -f examples/graviton-spot-deployment.yaml
kubectl get nodes -L kubernetes.io/arch,karpenter.sh/capacity-type
```

SAMPLE OUTPUT

```text
NAME                                           STATUS   ROLES    AGE     VERSION               ARCH    CAPACITY-TYPE
ip-10-0-22-140.eu-central-1.compute.internal   Ready    <none>   9m18s   v1.35.2-eks-f69f56f   amd64   
ip-10-0-33-176.eu-central-1.compute.internal   Ready    <none>   65s     v1.35.0-eks-ac2d5a0   arm64   spot
ip-10-0-37-230.eu-central-1.compute.internal   Ready    <none>   2m24s   v1.35.0-eks-ac2d5a0   arm64   spot
ip-10-0-38-162.eu-central-1.compute.internal   Ready    <none>   9m15s   v1.35.2-eks-f69f56f   amd64  
```

**4. Inspect Karpenter node details:**

```bash
kubectl get nodeclaims                           # Karpenter's view of provisioned nodes
kubectl describe nodeclaim <name>                # instance type, zone, capacity-type
```

**5. Test scale-down - delete workloads and watch Karpenter remove idle nodes:**

```bash
kubectl delete -f examples/
kubectl get nodes -w                             # Karpenter-managed nodes terminate
```

## Cleanup (!!!)

```bash
# Terragrunt
terragrunt run --all -- destroy

# Or plain Terraform (destroy Stage 2 first, then Stage 1)
cd 02-cluster-config && terraform destroy
cd ../01-base-infra && terraform destroy
```

Delete any LoadBalancer/PVC workloads before destroying to avoid orphaned AWS resources.
