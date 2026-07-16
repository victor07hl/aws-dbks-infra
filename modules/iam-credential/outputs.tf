output "role_arn" {
  description = "ARN of the cross-account credential IAM role"
  value       = aws_iam_role.credential.arn
}
