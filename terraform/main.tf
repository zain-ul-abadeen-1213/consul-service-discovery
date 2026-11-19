terraform {
  required_version = ">= 1.5.0"
  required_providers {
    consul = {
      source  = "hashicorp/consul"
      version = "~> 2.20"
    }
  }
}

provider "consul" {
  address    = "127.0.0.1:8500"
  scheme     = "http"
  datacenter = "dc1"
}

resource "consul_keys" "web_config" {
  key {
    path  = "config/web/app_name"
    value = "ZainTech Web Service"
  }
  key {
    path  = "config/web/environment"
    value = "home-lab"
  }
  key {
    path  = "config/web/owner"
    value = "Zain Tech Automation Solutions"
  }
}

output "note" {
  value = "KV values Terraform se Consul me set ho gayi hain, consul kv get se verify karo"
}
