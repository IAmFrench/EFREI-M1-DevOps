# Select the training resource group
data "ibm_resource_group" "Training" {
  name = "Training"
}

variable "tags" {
  type = list(string)
}

# Create a VPC inside the Training resource group
resource "ibm_is_vpc" "PF_ITOPS_vpc" {
  name           = "pf-itops-vpc"
  resource_group = data.ibm_resource_group.Training.id
  tags           = var.tags
}

variable "zone" {
  type = string
}

resource "ibm_is_subnet" "public" {
  name                     = "pf-itops-public"
  vpc                      = ibm_is_vpc.PF_ITOPS_vpc.id
  zone                     = var.zone
  total_ipv4_address_count = 8
  resource_group           = data.ibm_resource_group.Training.id
  network_acl              = ibm_is_vpc.PF_ITOPS_vpc.default_network_acl
}

resource "ibm_is_subnet" "private" {
  name                     = "pf-itops-private"
  vpc                      = ibm_is_vpc.PF_ITOPS_vpc.id
  zone                     = var.zone
  total_ipv4_address_count = 8
  resource_group           = data.ibm_resource_group.Training.id
  network_acl              = ibm_is_vpc.PF_ITOPS_vpc.default_network_acl
}

resource "ibm_is_ssh_key" "ssh_Key" {
  name           = "pf-itops-apares"
  public_key     = file(var.pubKeyPath)
  resource_group = data.ibm_resource_group.Training.id
}

variable "pubKeyPath" {
  type = string
}


# The security group for instances in the public subnet
resource "ibm_is_security_group" "public" {
  name = "pf-itops-public-sg"
  vpc  = ibm_is_vpc.PF_ITOPS_vpc.id
  resource_group = data.ibm_resource_group.Training.id # Very very important
}

# Allow only traffic from Unicity Public wifi
resource "ibm_is_security_group_rule" "public_sg_rule_all_in_from_unicity" {
  group     = ibm_is_security_group.public.id
  direction = "inbound"
  remote = "217.163.58.252/32"
}

# Allow only traffic from home
resource "ibm_is_security_group_rule" "public_sg_rule_all_in_from_home" {
  group     = ibm_is_security_group.public.id
  direction = "inbound"
  remote = "46.193.4.20/32"
}

# Allow all exiting traffic
resource "ibm_is_security_group_rule" "public_sg_rule_all_out" {
  group     = ibm_is_security_group.public.id
  direction = "outbound"
  remote = "0.0.0.0/0"
}


# NAT GWT INSTANCE
resource "ibm_is_instance" "nat_gwt_instance" {
  name    = "pf-itops-nat-gwt"
  image   = "r006-d2f5be47-f7fb-4e6e-b4ab-87734fd8d12b" # Ubuntu 18.04
  profile = "cp2-2x4"
  primary_network_interface {
    name   = "eth0"
    subnet = ibm_is_subnet.public.id
    security_groups = [ibm_is_security_group.public.id]
  }
  vpc            = ibm_is_vpc.PF_ITOPS_vpc.id
  zone           = var.zone
  keys           = [ibm_is_ssh_key.ssh_Key.id]
  user_data      = file(var.natGwtStartupScript)
  resource_group = data.ibm_resource_group.Training.id
}

variable "natGwtStartupScript" {
  type = string
}

resource "ibm_is_floating_ip" "nat_gwt_instance_floating_ip" {
  name   = "pf-itops-nat-gwt-flt-ip"
  target = ibm_is_instance.nat_gwt_instance.primary_network_interface[0].id
  resource_group = data.ibm_resource_group.Training.id
}



# security group for instances in the private subnet
resource "ibm_is_security_group" "private" {
  name = "pf-itops-private-sg"
  vpc  = ibm_is_vpc.PF_ITOPS_vpc.id
  resource_group = data.ibm_resource_group.Training.id
}

# Allow only traffic from the public subnet
resource "ibm_is_security_group_rule" "private_sg_rule_all_in_from_public_subnet" {
  group     = ibm_is_security_group.private.id
  direction = "inbound"
  remote = ibm_is_subnet.public.ipv4_cidr_block # IP range of the public subnet
  # remote = "0.0.0.0/0" # test, allow all incoming traffic
}

# Allow all exiting traffic
resource "ibm_is_security_group_rule" "private_sg_rule_all_out" {
  group     = ibm_is_security_group.private.id
  direction = "outbound"
  remote = "0.0.0.0/0"
}

# Private INSTANCE
resource "ibm_is_instance" "private_instance" {
  name    = "pf-itops-private"
  image   = "r006-d2f5be47-f7fb-4e6e-b4ab-87734fd8d12b" # Ubuntu 18.04
  profile = "cp2-2x4"
  primary_network_interface {
    name   = "eth0"
    subnet = ibm_is_subnet.private.id
    security_groups = [ibm_is_security_group.private.id]
  }
  vpc            = ibm_is_vpc.PF_ITOPS_vpc.id
  zone           = var.zone
  keys           = [ibm_is_ssh_key.ssh_Key.id]
  resource_group = data.ibm_resource_group.Training.id # super important
}


output "ngwt-instance" {
  value = ibm_is_floating_ip.nat_gwt_instance_floating_ip.address
}

output "private-instance" {
  value = ibm_is_instance.private_instance.primary_network_interface[0].primary_ipv4_address
}

output "public_sub-ipv4_cidr_block" {
  value = ibm_is_subnet.public.ipv4_cidr_block
}
output "private_sub-ipv4_cidr_block" {
  value = ibm_is_subnet.private.ipv4_cidr_block
}


resource "ibm_is_vpc_route" "private_sub" {
  name        = "pf-itops-route-private"
  vpc         = ibm_is_vpc.PF_ITOPS_vpc.id
  zone        = var.zone
  destination = "0.0.0.0/0"
  next_hop    = ibm_is_instance.nat_gwt_instance.primary_network_interface[0].primary_ipv4_address
}

variable "team_prefix" {
  type = string
}