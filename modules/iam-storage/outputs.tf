output "role_arn" {
  description = "ARN of the self-assuming Unity Catalog storage trust role"
  value       = aws_iam_role.storage.arn
}
