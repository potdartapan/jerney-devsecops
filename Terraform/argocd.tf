# 1. Install Argo CD (and its CRDs) FIRST
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  create_namespace = true
  version          = "5.51.6" 
  
  # The extraObjects block has been completely removed!
}
