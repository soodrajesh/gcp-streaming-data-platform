variable "project_id" {
  type = string
}

variable "region" {
  type    = string
  default = "europe-west1"
}

variable "bq_location" {
  type    = string
  default = "EU"
}

variable "billing_account_id" {
  type = string
}

variable "budget_amount" {
  type    = number
  default = 10
}

variable "alert_email" {
  type = string
}

variable "admin_email" {
  type = string
}

variable "image" {
  description = "Container image (digest-pinned) for the enricher service and generator job. Empty = phase 1 (infrastructure only)."
  type        = string
  default     = ""
}
