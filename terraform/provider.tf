# Original Source: https://github.com/TechDufus/home.io/blob/main/terraform/proxmox/provider.tf
terraform {
  required_version = ">= 1.1.0"
  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "3.0.1-rc1"
    }
  }
}

variable "PROXMOX_API_URL" {
  description = "Value of the Proxmox API URL, e.g.: https://0.0.0.0:8006/api2/json"
  type        = string
}

variable "PROXMOX_API_TOKEN_ID" {
  description = "Value of the Proxmox API Token ID, e.g.: terraform@pam!terraform"
  type        = string
  sensitive   = true
}

variable "PROXMOX_API_TOKEN_SECRET" {
  description = "Value of the Proxmox API Token Secret, e.g.: 00000000-0000-0000-0000-000000000000"
  type        = string
  sensitive   = true
}

variable "PROXMOX_TLS_INSECURE" {
  description = "Set to true if you want to skip TLS verification"
  type        = bool
  default     = false
}

provider "proxmox" {
  pm_api_url          = var.PROXMOX_API_URL
  pm_api_token_id     = var.PROXMOX_API_TOKEN_ID
  pm_api_token_secret = var.PROXMOX_API_TOKEN_SECRET
  pm_tls_insecure     = var.PROXMOX_TLS_INSECURE

  # # Debugging
  # pm_log_enable = true
  # pm_debug = true
  # pm_log_levels = {
  #   _default = "debug"
  #   # _capturelog = ""
  # }
}
