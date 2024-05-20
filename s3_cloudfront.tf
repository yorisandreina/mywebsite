resource "aws_s3_bucket" "mybucket" {
  bucket = "my-static-webpage-andreinayoris"
}

resource "aws_s3_bucket_public_access_block" "website_bucket_public_access_block" {
  bucket                  = aws_s3_bucket.mybucket.id
  ignore_public_acls      = true
  block_public_acls       = true
  restrict_public_buckets = true
  block_public_policy     = true
}

locals {
  content_type_map = {
    html = "text/html; charset=UTF-8"
  }
}

resource "aws_s3_bucket_website_configuration" "mybucket_website_config" {
  bucket = aws_s3_bucket.mybucket.id

  index_document {
    suffix = "index.html"
  }

  routing_rule {
    redirect {
      replace_key_with = "index.html"
    }
  }
}

resource "aws_s3_object" "provision_source_files" {
  bucket = aws_s3_bucket.mybucket.id
  key    = "index.html"
  source = "index.html"
  content_type = local.content_type_map["html"]
}

locals {
  s3_origin_id = "s3-origin"
}

resource "aws_cloudfront_origin_access_identity" "mybucket_oai" {
  comment = "OAI for S3 frontend"
}

data "aws_iam_policy_document" "oai_access_policy" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.mybucket.arn}/*"]

    principals {
      type        = "AWS"
      identifiers = [aws_cloudfront_origin_access_identity.mybucket_oai.iam_arn]
    }
  }
}

resource "aws_s3_bucket_policy" "oai_access" {
  bucket = aws_s3_bucket.mybucket.id
  policy = data.aws_iam_policy_document.oai_access_policy.json
}

resource "aws_s3_bucket_cors_configuration" "mybucket_cors_config" {
  bucket = aws_s3_bucket.mybucket.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET"]
    allowed_origins = ["*"]
    expose_headers  = []
    max_age_seconds = 3600
  }
}

resource "aws_cloudfront_distribution" "mybucket_cf_distribution" {
  origin {
    domain_name = aws_s3_bucket.mybucket.bucket_regional_domain_name
    origin_id   = local.s3_origin_id

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.mybucket_oai.cloudfront_access_identity_path
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "Distribution for static webpage"
  default_root_object = "index.html" 

  default_cache_behavior {
    allowed_methods         = ["GET", "HEAD", "OPTIONS"]
    cached_methods          = ["GET", "HEAD"]
    target_origin_id        = local.s3_origin_id
    viewer_protocol_policy  = "redirect-to-https"
    min_ttl                 = 0
    default_ttl             = 3600
    max_ttl                 = 86400
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }

  price_class = "PriceClass_100"

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  wait_for_deployment = true
}

output "service_ip" {
  value = aws_cloudfront_distribution.mybucket_cf_distribution.domain_name
}