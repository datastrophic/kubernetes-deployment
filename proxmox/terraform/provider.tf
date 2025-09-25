terraform {
  required_providers {
    proxmox = {
      source = "telmate/proxmox"
      version = "v3.0.2-rc03"
    }
  }
}

provider "proxmox" {
  pm_parallel       = 1
  pm_tls_insecure   = true
  pm_api_url        = var.pm_api_url
  pm_password       = var.pm_password
  pm_user           = var.pm_user
  pm_minimum_permission_check = false
}
