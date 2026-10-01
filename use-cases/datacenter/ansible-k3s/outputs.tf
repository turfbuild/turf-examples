# Outputs from every layer, so `outputs` alone shows how far the run got: the
# hosts after round 1, the nodes the cluster registered after round 2, the
# custom resource after round 3.

output "server_public_ip" {
  description = "The server host's public address; the Kubernetes API listens on 6443."
  value       = module.nodes.server_public_ip
}

output "hosts" {
  description = "Every host, by Name tag, with its addresses."
  value       = concat([module.nodes.server], module.nodes.agents)
}

output "k3s_version" {
  description = "The k3s release the playbook installed."
  value       = module.k3s.k3s_version
}

output "cluster_nodes" {
  description = "The nodes registered with the cluster Ansible built."
  value       = module.demo.node_names
}

output "crd_name" {
  description = "The CustomResourceDefinition applied to that cluster."
  value       = module.demo.crd_name
}

output "cr_name" {
  description = "The custom resource of the CRD's kind."
  value       = module.demo.cr_name
}

output "cr_message" {
  description = "spec.message on that custom resource."
  value       = module.demo.cr_message
}

output "ssh" {
  description = "How to log in to the server yourself."
  value       = "ssh -i .k3s/id_ed25519 ubuntu@${module.nodes.server_public_ip}"
}
