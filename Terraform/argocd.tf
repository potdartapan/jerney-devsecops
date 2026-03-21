resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  create_namespace = true
  version          = "5.51.6" 

  values = [
    yamlencode({
      # additionalApplications was removed in v5+. 
      # We now use extraObjects to inject the Application natively.
      extraObjects = [
        {
          apiVersion = "argoproj.io/v1alpha1"
          kind       = "Application"
          metadata = {
            name      = "root-application"
            namespace = "argocd"
          }
          spec = {
            project = "default"
            source = {
              repoURL        = "https://github.com/potdartapan/jerney-devsecops.git"
              targetRevision = "HEAD"
              
              # Ensure this points to the exact folder containing your Chart.yaml
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
      ]
    })
  ]
}