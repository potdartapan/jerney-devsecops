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

# 2. Install the Root Application SECOND
resource "helm_release" "argocd_apps" {
  name       = "argocd-apps"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-apps"
  namespace  = "argocd"
  version    = "2.0.4"
  
  # This is the magic line. It forces Terraform to wait for the CRDs!
  depends_on = [helm_release.argocd]

  values = [
    yamlencode({
      applications = {
        "root-application" = {
          namespace = "argocd"
          project   = "default"
          source = {
            repoURL        = "https://github.com/potdartapan/jerney-devsecops.git"
            targetRevision = "HEAD"
            path           = "argo/charts/jerney-app" 
          }
          destination = {
            server    = "https://kubernetes.default.svc"
            namespace = "argocd"
          }
          syncPolicy = {
            automated = {
              prune    = true
              selfHeal = true
            }
          }
        }
      }
    })
  ]
}