# Tech Assignment – Opsfleet

This repository contains a demo infrastructure and architecture design for the Opsfleet technical assignment.

It demonstrates how to deploy a Kubernetes platform on AWS using **EKS, Karpenter, Graviton instances, and Spot capacity**, along with supporting infrastructure and documentation.

## Repository Structure

| Directory | Description |
| - | - |
| `terraform/` | Terraform + Terragrunt code that deploys the EKS cluster and Karpenter configuration |
| `architecture/` | Architecture design document explaining the cloud setup and design decisions for demo application |

## Documentation

- **Infrastructure setup:** [terraform/README.md](./terraform/README.md)
- **Architecture design:** [architecture/README.md](./architecture/README.md)
