# The hosts: plain Ubuntu machines on their own network, reachable from one
# address. Nothing here configures them; that is Ansible's job, in module.k3s.

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.66"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.4"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.9"
    }
  }
}

variable "name_prefix" {
  description = "Prefix for every Name tag and the key pair's name."
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for every host."
  type        = string
}

variable "agent_count" {
  description = "k3s agents beside the one server."
  type        = number
  default     = 1
}

variable "operator_cidr" {
  description = "The network allowed in on 22 and 6443."
  type        = string
}

variable "key_file" {
  description = "Absolute path the SSH private key is written to, for Ansible."
  type        = string
}

variable "ubuntu_image" {
  description = <<-EOT
    Canonical's AMI name pattern; the newest image that matches it is used.
    The hosts ignore later images (their ignore_changes), so a new release
    replaces nothing.
  EOT
  type        = string
  default     = "ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = [var.ubuntu_image]
  }
}

# k3s takes 10.42.0.0/16 for pods and 10.43.0.0/16 for services, so the VPC
# stays clear of both.
resource "aws_vpc" "this" {
  cidr_block           = "10.80.0.0/16"
  enable_dns_hostnames = true

  tags = { Name = var.name_prefix }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = { Name = var.name_prefix }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = "10.80.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = { Name = "${var.name_prefix}-public" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = { Name = "${var.name_prefix}-public" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "nodes" {
  name        = "${var.name_prefix}-nodes"
  description = "k3s hosts: SSH and the API from the operator, everything between hosts"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "SSH, for Ansible"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.operator_cidr]
  }

  ingress {
    description = "The Kubernetes API, for the kubernetes provider"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = [var.operator_cidr]
  }

  # The agent joins the server over its private address, and flannel's VXLAN
  # and the kubelets talk host to host. Traffic between members only.
  ingress {
    description = "Everything between the hosts"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  # k3s installs from get.k3s.io and pulls its images from public registries.
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name_prefix}-nodes" }
}

# The key Ansible connects with. Generated here so the example needs nothing on
# disk beforehand; the private half is in state and in key_file, both of which
# a real deployment would keep elsewhere.
resource "tls_private_key" "ssh" {
  algorithm = "ED25519"
}

resource "aws_key_pair" "this" {
  key_name   = var.name_prefix
  public_key = tls_private_key.ssh.public_key_openssh
}

resource "local_sensitive_file" "ssh_key" {
  filename             = var.key_file
  content              = tls_private_key.ssh.private_key_openssh
  file_permission      = "0600"
  directory_permission = "0700"
}

# Nothing the hosts read names the route out of the subnet, so without the
# depends_on the route is free to go first on the way down: a destroy would
# delete the route table while the cluster objects in module.demo still need
# the API, and an IGW cannot detach while hosts hold public addresses. Ordered
# here, everything that reaches a host through module.k3s or the kubernetes
# provider is also after the route on the way up, and before it on the way down.
resource "aws_instance" "server" {
  depends_on = [aws_route_table_association.public]

  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.nodes.id]
  key_name               = aws_key_pair.this.key_name

  root_block_device {
    volume_size = 16
    volume_type = "gp3"
  }

  tags = { Name = "${var.name_prefix}-server" }

  # A new ami replaces the host, and the cluster with it, so the host keeps the
  # image it was created from when Canonical publishes another. A host created
  # later, or replaced, starts from the newest.
  lifecycle {
    ignore_changes = [ami]
  }
}

resource "aws_instance" "agent" {
  count      = var.agent_count
  depends_on = [aws_route_table_association.public]

  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.nodes.id]
  key_name               = aws_key_pair.this.key_name

  root_block_device {
    volume_size = 16
    volume_type = "gp3"
  }

  tags = { Name = "${var.name_prefix}-agent-${count.index}" }

  # As the server's.
  lifecycle {
    ignore_changes = [ami]
  }
}

output "server" {
  description = "The server's Name tag, instance id and both addresses."
  value = {
    name       = aws_instance.server.tags.Name
    id         = aws_instance.server.id
    public_ip  = aws_instance.server.public_ip
    private_ip = aws_instance.server.private_ip
  }
}

output "agents" {
  description = "Each agent's Name tag, instance id and both addresses."
  value = [for a in aws_instance.agent : {
    name       = a.tags.Name
    id         = a.id
    public_ip  = a.public_ip
    private_ip = a.private_ip
  }]
}

output "server_public_ip" {
  description = "Where the operator reaches the Kubernetes API."
  value       = aws_instance.server.public_ip
}

output "ssh_user" {
  description = "The login Canonical's Ubuntu images create."
  value       = "ubuntu"
}

output "key_file" {
  description = "The SSH private key's path, once written."
  value       = local_sensitive_file.ssh_key.filename
}
