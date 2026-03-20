resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  create_namespace = true
  version          = "5.51.6" # It is best practice to pin the Helm chart version

  # We use yamlencode to pass the Root App directly into the Helm chart
  values = [
    yamlencode({
      server = {
        additionalApplications = [
          {
            name      = "root-application"
            namespace = "argocd"
            project   = "default"
            source = {
              repoURL        = "https://github.com/tapanpotdar/jerney.git"
              targetRevision = "HEAD"
              path           = "argocd-apps"
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
        ]
      }
    })
  ]
}