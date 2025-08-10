provider "aws" {
  region = "ap-south-1"
}

# VPC
resource "aws_vpc" "jagdish_vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "jagdish-vpc"
  }
}

# Public Subnets
resource "aws_subnet" "public_subnet" {
  count                   = 2
  vpc_id                  = aws_vpc.jagdish_vpc.id
  cidr_block              = cidrsubnet(aws_vpc.jagdish_vpc.cidr_block, 8, count.index)
  availability_zone       = element(["ap-south-1a", "ap-south-1b"], count.index)
  map_public_ip_on_launch = true

  tags = {
    Name = "jagdish-public-${count.index}"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "jagdish_igw" {
  vpc_id = aws_vpc.jagdish_vpc.id

  tags = {
    Name = "jagdish-igw"
  }
}

# NAT Gateway (for private subnets)
resource "aws_eip" "nat_eip" {
  domain = "vpc"
}

resource "aws_nat_gateway" "nat_gw" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_subnet[0].id

  tags = {
    Name = "jagdish-nat-gw"
  }
}

# Route Tables
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.jagdish_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.jagdish_igw.id
  }

  tags = {
    Name = "public-rt"
  }
}

resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.jagdish_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gw.id
  }

  tags = {
    Name = "private-rt"
  }
}

# Route Table Associations
resource "aws_route_table_association" "public_assoc" {
  count          = 2
  subnet_id      = aws_subnet.public_subnet[count.index].id
  route_table_id = aws_route_table.public_rt.id
}

# Security Groups
resource "aws_security_group" "jagdish_cluster_sg" {
  vpc_id = aws_vpc.jagdish_vpc.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "jagdish-cluster-sg"
  }
}

resource "aws_security_group" "jagdish_node_sg" {
  vpc_id = aws_vpc.jagdish_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["YOUR_PUBLIC_IP/32"] # Restrict SSH
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "jagdish-node-sg"
  }
}

# IAM Roles
resource "aws_iam_role" "jagdish_cluster_role" {
  name = "jagdish-cluster-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "eks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "jagdish_cluster_role_policy" {
  role       = aws_iam_role.jagdish_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role" "jagdish_node_group_role" {
  name = "jagdish-node-group-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "jagdish_node_group_role_policy" {
  role       = aws_iam_role.jagdish_node_group_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "jagdish_node_group_cni_policy" {
  role       = aws_iam_role.jagdish_node_group_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "jagdish_node_group_registry_policy" {
  role       = aws_iam_role.jagdish_node_group_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# EKS Cluster
resource "aws_eks_cluster" "jagdish" {
  name     = "jagdish-cluster"
  role_arn = aws_iam_role.jagdish_cluster_role.arn

  vpc_config {
    subnet_ids         = aws_subnet.public_subnet[*].id
    security_group_ids = [aws_security_group.jagdish_cluster_sg.id]
  }
}

# Node Group
resource "aws_eks_node_group" "jagdish" {
  cluster_name    = aws_eks_cluster.jagdish.name
  node_group_name = "jagdish-node-group"
  node_role_arn   = aws_iam_role.jagdish_node_group_role.arn
  subnet_ids      = aws_subnet.public_subnet[*].id

  scaling_config {
    desired_size = 2
    max_size     = 2
    min_size     = 2
  }

  instance_types = ["t2.medium"]

  remote_access {
    ec2_ssh_key               = var.ssh_key_name
    source_security_group_ids = [aws_security_group.jagdish_node_sg.id]
  }
}
