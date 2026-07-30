removed {
  from = kubernetes_daemon_set_v1.img-fetch["coder-workspace"]
  lifecycle {
    destroy = false
  }
}

removed {
  from = kubernetes_daemon_set_v1.img-fetch["coder-workspace-static"]
  lifecycle {
    destroy = false
  }
}

removed {
  from = kubernetes_manifest.mutate_img_policy
  lifecycle {
    destroy = false
  }
}