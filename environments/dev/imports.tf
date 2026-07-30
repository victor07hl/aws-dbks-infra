# IT-70: brownfield import of the pre-existing single-node cluster created
# manually via Compute -> Create cluster in the DEV workspace (the
# smoke-test cluster from docs/manual-deployment-findings.md's
# post-deployment verification step). Live config confirmed via
# `databricks clusters get` (OAuth M2M creds) rather than assumed: it's a
# simplified single-node cluster (is_single_node = true, kind =
# "CLASSIC_PREVIEW"), so Databricks auto-manages custom_tags/spark_conf/
# num_workers rather than them being set explicitly in Terraform.
#
# Remove this file once `terraform apply` has bound the resource into state
# (import blocks are one-time; leaving it is harmless but unnecessary).

import {
  to = module.databricks_cluster.databricks_cluster.this
  id = "0715-220618-5iractu9"
}
