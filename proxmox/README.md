# Proxmox VM setup

## Overview
This directory contains tooling for:
- creating a Proxmox VM template to use as a source for future VMs (Ansible)
- provisioning VMs based on the created template (Terraform)

Required software:
- Ansible: `pip3 install ansible`
- Terraform: `brew install terraform`

Contents:
- [create-vm-template.yaml](create-vm-template.yaml) - contains an Ansible playbook to
run tasks for downloading a cloud-init image and creating a VM template in PVE. The playbook should be run as root
on the PVE host itself.
- [terraform/main.tf](terraform/main.tf) contains the definition of the VMs and their quantity/resources etc.

## Creating cloud-init template

To create new cloud-init VM template:
- update [ansible/inventory.yaml](ansible/inventory.yaml) and replace `proxmox.local` with the address of the PVE host
- modify `vars` section in [ansible/create-vm-template.yaml](ansible/create-vm-template.yaml) as needed
  - note: `cloud_image_path` must have a `.qcow2` extension due to PVE compatibility issue
- from directory root, run:
  ```
  ansible-playbook -i ansible/inventory.yaml ansible/create-vm-template.yaml -K
  ```

## Provisioning VMs

To provision VMs:
- update [terraform/variables.tf](terraform/variables.tf) as needed; replace `proxmox.local` with the address of the PVE host
- update/modify [terraform/main.tf](terraform/main.tf) to tweak the configuration of VMs
- from [terraform](terraform) directory, run
  ```
  terraform init
  terraform plan -var="pm_user=root@pam" -var="pm_password=<PVE root password>" -out plan

  terraform apply "plan"
  ```

## References:
- [docs for Terraform Proxmox provider](https://registry.terraform.io/providers/Telmate/proxmox/latest/docs)
- [Deploy Proxmox virtual machines using Cloud-init](https://norocketscience.at/deploy-proxmox-virtual-machines-using-cloud-init/)
- [Proxmox VMs with Terraform](https://norocketscience.at/provision-proxmox-virtual-machines-with-terraform/)
- [Proxmox, Terraform, and Cloud-Init](https://yetiops.net/posts/proxmox-terraform-cloudinit-saltstack-prometheus/)
