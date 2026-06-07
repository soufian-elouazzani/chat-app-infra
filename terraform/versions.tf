terraform {
  required_version = ">= 1.3.0"

  required_providers {
    grid5000 = {
      source  = "pmorillon/grid5000"
      version = "~> 0.0.8"
    }
  }
}
