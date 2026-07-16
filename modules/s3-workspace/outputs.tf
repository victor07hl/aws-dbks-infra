output "bucket_name" {
  description = "Name of the workspace S3 bucket"
  value       = aws_s3_bucket.workspace.bucket
}

output "bucket_arn" {
  description = "ARN of the workspace S3 bucket"
  value       = aws_s3_bucket.workspace.arn
}
