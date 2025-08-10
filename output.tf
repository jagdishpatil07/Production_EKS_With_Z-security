output "cluster_id" {
  value = aws_eks_cluster.jagdish.id
}

output "node_group_id" {
  value = aws_eks_node_group.jagdish.id
}

output "vpc_id" {
  value = aws_vpc.jagdish_vpc.id
}

output "private_subnet_ids" {
  value = aws_subnet.private_subnet[*].id
}
