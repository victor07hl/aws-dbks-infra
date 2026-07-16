variable "bucket_name" {
  description = "Name of the per-environment workspace S3 bucket (holds workspace artifacts and UC managed data under /unity-catalog/*)"
  type        = string
}
