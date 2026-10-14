# Bare hosts to a custom resource: Terraform, Ansible, Terraform again

Two plain Ubuntu hosts on EC2, made into a Kubernetes cluster by
[k3s-ansible](https://github.com/k3s-io/k3s-ansible), with a CRD and an object of
its kind applied to that cluster — from **one configuration, in one dependency
graph**. Terraform creates the hosts. An `ansible_playbook_run` action installs
k3s across them. The playbook hands the cluster's kubeconfig back as a file, and
the `kubernetes` provider is configured from that file.

## In plain terms

Standing up a cluster on your own machines usually means three tools, run by
hand and in order. Terraform creates the machines. Then you copy their addresses
into an Ansible inventory and run a playbook that installs Kubernetes on them.
Then you copy the cluster's credentials off the server and run Terraform (or
`kubectl`) again to put things into the cluster. Tearing it down is the same
dance backwards, and getting the order wrong strands something.

This example writes the whole chain as one configuration, and Turf runs it as
one graph, each step as soon as what it needs exists:

1. Create a network and two Ubuntu machines.
2. Build Ansible's inventory from the machines' addresses, and run the k3s
   playbook across both of them.
3. Read the cluster's credentials back from the file the playbook saved.
4. Use them to create a custom resource type (a CRD) in the new cluster, then an
   object of that type.

Some of these steps cannot even be *planned* until the earlier ones have run:
there is no address to put in the inventory, no credential for the cluster, no
such resource type yet. Turf plans what it can, applies it, and comes back for
the rest — three rounds, one command, about three and a half minutes. `destroy`
takes the same graph backwards: the objects leave the cluster while it still
exists, then the machines go, then the network. Stock Terraform 1.16.2 gets there
too, but needs three applies, two of them `-target`ed, after two plain applies
that fail at plan ([below](#on-plain-terraform)).

### The gist

Terraform hands Ansible an inventory built from the hosts it just created, and
runs the playbook once they exist (`modules/k3s/main.tf`, trimmed):

```hcl
data "ansible_inventory" "cluster" {
  group {
    name = "k3s_cluster"

    group {
      name = "server"
      host {
        name         = var.server.name
        ansible_host = var.server.public_ip # from module.nodes' aws_instance
        ansible_user = var.ssh_user
      }
    }
    # ...and an "agent" group, one host per agent
  }
}

# One anchor for the whole cluster: created once the hosts are, and replaced
# (re-running the playbook) whenever a host is.
resource "terraform_data" "install" {
  triggers_replace = concat([var.server.id], var.agents[*].id)

  lifecycle {
    action_trigger {
      events  = [after_create]
      actions = [action.ansible_playbook_run.k3s]
    }
  }
}

action "ansible_playbook_run" "k3s" {
  config {
    playbooks   = ["${var.playbook_dir}/wait.yml", "${var.playbook_dir}/site.yml"]
    inventories = [data.ansible_inventory.cluster.json]
  }
}
```

The playbook is k3s-ansible's own, unchanged, plus one play that saves the
cluster's credentials where Terraform will look for them (`playbooks/site.yml`):

```yaml
- name: Install k3s with k3s-ansible
  ansible.builtin.import_playbook: k3s.orchestration.site

- name: Hand the kubeconfig back to Terraform
  hosts: server
  become: true
  tasks:
    - name: Fetch the admin kubeconfig
      ansible.builtin.fetch:
        src: /etc/rancher/k3s/k3s.yaml
        dest: "{{ kubeconfig_out }}"
        flat: true
```

And Terraform reads that file back and talks to the cluster Ansible built
(`modules/k3s/main.tf`, `providers.tf` and `modules/demo/main.tf`, trimmed):

```hcl
data "local_sensitive_file" "kubeconfig" {
  filename   = var.kubeconfig_file
  depends_on = [terraform_data.install] # after the playbook has run
}

provider "kubernetes" {
  host                   = "https://${module.nodes.server_public_ip}:6443"
  cluster_ca_certificate = module.k3s.cluster_ca_certificate # decoded from that file
  client_certificate     = module.k3s.client_certificate
  client_key             = module.k3s.client_key
}

resource "kubernetes_manifest" "turf" {
  depends_on = [kubernetes_manifest.crd]

  manifest = {
    apiVersion = "demo.local/v1"
    kind       = "Turf"
    metadata   = { name = "built-by-ansible", namespace = var.namespace }
    spec       = { message = var.message }
  }
}
```

Nothing in between is a script: no inventory file, no `ansible-playbook` run by
hand, no kubeconfig copied around.

## What This Demonstrates

### Ansible as a step in the graph, not a script around it

- **The inventory is a value.** `data.ansible_inventory.cluster` builds k3s-ansible's
  `k3s_cluster` / `server` / `agent` groups straight from `module.nodes`' outputs.
  No inventory file, no dynamic-inventory script, no tag lookup. On the first
  round the hosts' addresses do not exist yet, so the read moves to the apply,
  after the hosts.
- **One anchor, one run.** Triggering the playbook from each host would run it
  once per host. Instead `terraform_data.install` carries the
  `after_create` trigger, and its `triggers_replace` is every host's id: replace a
  host (or change `agent_count`) and the playbook runs again across the new set.
- **A failed install is retried, not stranded.** `on_failure = taint` taints the
  anchor when the playbook fails, so the next run replaces it and installs again,
  rather than leaving a created anchor in front of a cluster that was never built.
- **An on-demand playbook.** `action.ansible_playbook_run.status` is triggered by
  nothing; run it when you want the nodes as the server sees them (see
  [Verify](#verify)).

### The way back is a file

An action returns nothing Terraform can bind. So the playbook's last play
fetches `/etc/rancher/k3s/k3s.yaml` to `.k3s/k3s.yaml`, and
`data.local_sensitive_file.kubeconfig` reads it back. Its `depends_on` the anchor
is load-bearing: on the first round it moves the read to the apply, after the
playbook. Without it the read would be planned, and a file that does not exist
yet is an error, not an unknown.

`module.k3s` turns that file into three sensitive outputs (CA, client
certificate, client key), and the root `provider "kubernetes"` takes the host's
address from Terraform and the credentials from those outputs. The server's
certificate names its public address because the inventory adds it to `tls-san`
(`server_config_yaml`); k3s-ansible adds only `api_endpoint` by itself.

### Teardown runs back through the same seam

`destroy` reaches the cluster the way the apply did. The refreshing destroy
re-reads the kubeconfig file, evaluates the module outputs over it, configures
the `kubernetes` provider from them, and deletes the custom resource and the CRD
through the cluster's API. Only then does it delete the hosts, and only after
the hosts the network (completion times, UTC):

```
module.demo.kubernetes_manifest.turf                21:44:57
module.demo.kubernetes_manifest.crd                 21:44:58
module.nodes.aws_instance.agent[0]                  21:45:19
module.nodes.aws_instance.server                    21:45:29
module.nodes.aws_route_table_association.public     21:45:29
module.nodes.aws_route_table.public                 21:45:30
module.nodes.aws_subnet.public                      21:45:30
module.nodes.aws_internet_gateway.this              21:45:31
module.nodes.aws_vpc.this                           21:45:32
```

The network coming down last is not automatic. Nothing the hosts read names the
route out of the subnet, so `module.nodes` gives both instances a `depends_on`
on the route table association. Without it, Terraform's own destroy deleted the
route first. The cluster objects then timed out reaching the API, and the
internet gateway could not detach while the hosts still held public addresses
(`DependencyViolation`), twenty minutes later.

## What it does when you run it

Measured on **Turf** at engine commit `d0910c1`, through the engine's development
driver before the v1 tools, from empty state, in `us-west-2` on 2026-10-01.

**Round 1** builds the hosts and runs the playbook. Everything that talks to the
cluster defers, because the provider's credentials are not known until the file
is read during this apply:

<!-- TODO(v1 re-run): replace with a round-by-round summary from a real v1 run -->
```
plan for phase p-28812504 (16 of 21 address(es) change):
  actions: 1 invocation(s) planned, 0 deferred
  read      data.http.operator_ip[0]
  create    module.nodes.aws_vpc.this
  ...
  create    module.nodes.aws_instance.agent[0]
  create    module.nodes.aws_instance.server
  create    module.k3s.random_password.token
  read      module.k3s.data.ansible_inventory.cluster  (read at apply)
  create    module.k3s.terraform_data.install
    invoke    module.k3s.action.ansible_playbook_run.k3s  (after_create, on_failure = taint)
  read      module.k3s.data.local_sensitive_file.kubeconfig  (read at apply)
  unspecified module.demo.data.kubernetes_nodes.all  (deferred)
  unspecified module.demo.kubernetes_manifest.crd  (deferred)
  unspecified module.demo.kubernetes_manifest.turf  (deferred)
phase p-28812504: applied (applied 15, failed 0, cancelled 0, invoked 1)
```

**Round 2** has a cluster to talk to. It creates the CRD; the custom resource
defers again, because the API does not serve the `Turf` kind until the CRD is
applied. **Round 3** creates it.

<!-- TODO(v1 re-run): replace with a round-by-round summary from a real v1 run -->
```
round 1 stages: ... plan 30.983s | apply 2m1.722s | ... | total 2m34.011s
round 2 stages: ... plan 19.127s | apply 5.114s   | ... | total 25.348s
round 3 stages: ... plan 19.029s | apply 4.256s   | ... | total 24.363s
converged in 3 round(s)
```

Three rounds and 204 seconds from nothing to a custom resource on a two-node
cluster; a fourth `up` plans 0 of 21 addresses. `destroy` removes all 21 in one
round, in 51 seconds.

## On plain Terraform

The same configuration on Terraform 1.16.2, from empty:

1. `terraform apply` **fails at plan.** The `kubernetes` provider is configured
   with an unknown host, and `data.kubernetes_nodes` dials the default instead:
   `Get "http://localhost/api/v1/nodes": dial tcp [::1]:80: connect: connection refused`.
2. `terraform apply -target=module.nodes -target=module.k3s` builds the hosts and
   runs the playbook (13 resources, 1 action, 127 s).
3. `terraform apply` **fails at plan** again, now on the custom resource:
   `API did not recognize GroupVersionKind from manifest (CRD may not be installed)`.
4. `terraform apply -target=module.demo.kubernetes_manifest.crd`.
5. `terraform apply` creates the custom resource; a following plan is clean.

`-target=module.k3s` alone is not enough: the targets' dependency closure must
reach the route out of the subnet, or the playbook cannot reach the hosts. The
instances' `depends_on` on the route table association is what makes it reach.

`terraform destroy` re-reads every data source first, as Turf's `destroy`
re-reads the kubeconfig. Unlike Turf, it also re-reads the ones no
teardown needs, such as `data.kubernetes_nodes`, so a destroy against a cluster
that is already unreachable fails on that read; `-refresh=false` gets past it.

## The modules

| Module | Tool | What it holds |
| --- | --- | --- |
| `modules/nodes` | Terraform (`hashicorp/aws`, `tls`, `local`) | a VPC clear of k3s's pod and service ranges, one public subnet, a security group admitting the operator on 22 and 6443 and the hosts to each other, an SSH key written to `.k3s/`, one server and `agent_count` agents |
| `modules/k3s` | Ansible (`ansible/ansible` 1.5.0) | the join token, the inventory as a value, the install anchor and its action, the kubeconfig read back, the on-demand `status` action |
| `modules/demo` | Terraform (`hashicorp/kubernetes`) | the registered nodes, a `turfs.demo.local` CRD, and a `Turf` named `built-by-ansible` |

The playbooks are short: `wait.yml` waits for SSH (a host is "running" to AWS
before sshd answers), `site.yml` imports k3s-ansible's own `site` playbook
unchanged and then fetches the kubeconfig back, and `status.yml` lists the nodes
from the server.

## Resources Created

- In AWS: a VPC, an internet gateway, a subnet, a route table and its
  association, a security group, a key pair, and two `t3.small` instances (one
  server, one agent). Everything that takes tags carries
  `turf.build/example = ansible-k3s`.
- On this machine: `.k3s/id_ed25519` (the SSH key) and `.k3s/k3s.yaml` (the
  kubeconfig). Both are also in state; a real deployment would keep them
  elsewhere.
- In the cluster: the CRD and one custom resource.

15 managed resources and 6 data sources, 21 addresses in all.

## Prerequisites

- **Turf**, installed and running as
  [Running the examples](../../../README.md#running-the-examples) describes.
  `ansible/ansible` is an action provider that serves plugin protocol 5 only.
- **An AWS account**, for two `t3.small` instances for a few minutes.
- **[mise](https://mise.jdx.dev)**, which builds the Ansible controller here and
  hands it, with your AWS account, to the providers Turf runs for this
  configuration. Once, in this directory:

  ```bash
  cd use-cases/datacenter/ansible-k3s
  mise trust && mise install && mise run setup
  ```

  The committed `mise.toml` pins Python, keeps a virtualenv in `.venv` and puts
  it on `PATH`, and its `setup` task installs `requirements.txt` into the venv and
  `requirements.yml`'s collections into `collections/`. Then name the account in
  a `mise.local.toml` beside it, which git ignores:

  ```toml
  [env]
  AWS_PROFILE = "my-profile"
  ```

  The `ansible/ansible` provider runs `ansible-playbook` from `PATH`, in this
  directory, so the venv's `ansible-playbook`, this `ansible.cfg` and
  `collections/` are the ones it uses, and the venv's Python carries `netaddr`.
  Skip `mise run setup` and the venv stays empty (Turf's evaluation of
  `mise.toml` creates `.venv` if it is missing), so the apply fails with the
  provider's own "ansible-playbook: not found".
- **Without mise**, build the venv by hand (`python3 -m venv .venv`, then
  `.venv/bin/pip install -r requirements.txt` and
  `.venv/bin/ansible-galaxy collection install -r requirements.yml -p collections`),
  and give the engine both in `~/.homebrew/services/turf.env`: `AWS_PROFILE`, and
  a `PATH` with this directory's `.venv/bin` first. A `PATH` there replaces the
  service's, so follow it with Homebrew's `bin` and the system directories. Then
  `brew services restart turf`.
- **Against a remote engine** (`TURF_RESTATE_URL`), the engine's image carries
  mise and Python, and the configuration's trust is the engine's
  `MISE_TRUSTED_CONFIG_PATHS`. The engine never installs anything, so run
  `mise run setup` where the checkout is made, in the engine's own image so the
  venv matches its architecture (an init container, or the job that makes the
  checkout).
- **`kubectl` is optional.** k3s-ansible copies a kubeconfig to the control node
  only when `kubectl` is installed there, and that step needs `netaddr` (pinned
  in `requirements.txt`). The example's own fetch does not depend on it.
- By default the security group admits only this machine's public address, as
  `checkip.amazonaws.com` reports it. Set `operator_cidr` in `terraform.tfvars`
  (see `terraform.tfvars.example`) if you run from behind a NAT whose egress
  address differs; with it set, the lookup is not read at all (its `count` is
  the gate).

## Usage

```bash
turf -C use-cases/datacenter/ansible-k3s up
```

Or from any MCP client: `init` the directory, `open`, then `up`, and
approve each round's plan with `apply`.

## Verify

```bash
cd use-cases/datacenter/ansible-k3s

# Every layer's outputs: the hosts, the nodes the cluster registered, the object.
jq '.outputs | map_values(.value)' terraform.tfstate

# The cluster, through the kubeconfig the playbook fetched back.
kubectl --kubeconfig .k3s/k3s.yaml --server "https://$(jq -r .outputs.server_public_ip.value terraform.tfstate):6443" \
  get nodes,turfs -A

# The nodes as the server sees them, through Ansible: from an MCP client,
#   invoke({ action_addr: "module.k3s.action.ansible_playbook_run.status" })
# then approve its plan with apply.

# Log in to the server yourself.
$(jq -r .outputs.ssh.value terraform.tfstate)
```

The fetched kubeconfig names `127.0.0.1` as its server, hence the `--server`.

## Cleanup

```bash
turf -C use-cases/datacenter/ansible-k3s destroy
rm -rf use-cases/datacenter/ansible-k3s/.k3s
```

`destroy` deletes the cluster objects through the cluster's API before it deletes
the hosts, so nothing is left in AWS or orphaned in state.

## Notes and known gaps

- **`ansible/ansible` 1.5.0 drops the end of a successful run's output.** The
  install's progress stops at the kubeconfig fetch and the `status` action's at
  "Show them"; the play recap and the node list never arrive. Terraform 1.16.2
  shows the same truncation, so it is the provider's, not the engine's. The
  playbooks still run to completion.
- **The hosts keep the image they were created from.** The AMI lookup takes
  Canonical's newest Ubuntu 24.04 image, and a new `ami` would replace both
  hosts, and so the cluster, so both declare `ignore_changes = [ami]`. A newly
  published image plans no change to a host that exists; a host created later,
  another agent or a replaced one, starts from the newest.
- **`hashicorp/aws` is `~> 6.66`.** Turf installs from
  registry.opentofu.org, which publishes a release or so behind
  registry.terraform.io; a constraint it cannot match yet stalls the install.
- **The root module names every provider**, including `tls`, `random` and
  `local`, which only child modules use, because Turf once loaded only the
  root's requirements before planning; `init` now installs child modules'
  providers too. A module that uses `ansible/ansible` names it in its own
  `required_providers` too, since it is not a HashiCorp source.
  <!-- TODO(v1 re-run): confirm the root no longer needs tls, random and local, then drop them from providers.tf and this note -->
- **k3s-ansible's own defaults** that this example overrides: `k3s_version` has
  no default and is used unguarded, so it is always set; the control node's
  kubeconfig merges into `~/.kube/config` at its default path, so the inventory
  points it into `.k3s/`.
