resource "azurerm_resource_group" "jerney-rg" {
  name     = var.resource_group_name
  location = var.location
}

resource "azurerm_kubernetes_cluster" "jerney-aks" {
    name                = "jerney-aks"
    location            = azurerm_resource_group.jerney-rg.location
    resource_group_name = azurerm_resource_group.jerney-rg.name
    dns_prefix         = "jerneyaks"
    
    default_node_pool {
        name       = "default"
        node_count = 1
        vm_size    = "Standard_B2s"
    }
    
    identity {
        type = "SystemAssigned"
    }
}