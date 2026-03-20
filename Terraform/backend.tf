provider "azurerm" {
  features {}
}

terraform {
    required_version = ">= 0.14"

required_providers {
  azurerm = {
    source  = "hashicorp/azurerm"
    version = "~> 3.0"
  }

  helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0" 
    }
}

    backend "azurerm" {
        resource_group_name   = "gitops-project-tfstate-rg"
        storage_account_name  = "tfstate1769048995"
        container_name        = "jerney-tfstate"
        key                   = "terraform.tfstate"
    }
}

provider "helm" {
  kubernetes = {
    host                   = azurerm_kubernetes_cluster.jerney-aks.kube_config.0.host
    client_certificate     = base64decode(azurerm_kubernetes_cluster.jerney-aks.kube_config.0.client_certificate)
    client_key             = base64decode(azurerm_kubernetes_cluster.jerney-aks.kube_config.0.client_key)
    cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.jerney-aks.kube_config.0.cluster_ca_certificate)
  }
}