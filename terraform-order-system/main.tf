# Provider — tells Terraform we are using AWS
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Region — tells Terraform which AWS region to use
provider "aws" {
  region = "us-east-2"
}

# DynamoDB Table
resource "aws_dynamodb_table" "orders_table" {
  name         = "ordersTable-tf"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "UserId"
  range_key    = "name"

  attribute {
    name = "UserId"
    type = "S"
  }

  attribute {
    name = "name"
    type = "S"
  }

  tags = {
    Name        = "ordersTable-tf"
    Environment = "production"
  }
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda_role" {
  name = "lambda-order-role-tf"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# IAM Policy — DynamoDB least privilege
resource "aws_iam_role_policy" "lambda_dynamodb_policy" {
  name = "lambda-dynamodb-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:Query"
        ]
        Resource = aws_dynamodb_table.orders_table.arn
      }
    ]
  })
}

# IAM Policy — SES least privilege
resource "aws_iam_role_policy" "lambda_ses_policy" {
  name = "lambda-ses-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ses:SendEmail"
        ]
        Resource = "*"
      }
    ]
  })
}

# IAM Policy — CloudWatch logs
resource "aws_iam_role_policy" "lambda_logs_policy" {
  name = "lambda-logs-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

# Lambda — Place Order Function
resource "aws_lambda_function" "place_order" {
  filename         = "place_order.zip"
  function_name    = "placeOrderFunction-tf"
  role             = aws_iam_role.lambda_role.arn
  handler          = "place_order.lambda_handler"
  runtime          = "python3.12"
  source_code_hash = filebase64sha256("place_order.zip")

  tags = {
    Environment = "production"
  }
}

# Lambda — Get Order Function
resource "aws_lambda_function" "get_order" {
  filename         = "get_order.zip"
  function_name    = "getOrderFunction-tf"
  role             = aws_iam_role.lambda_role.arn
  handler          = "get_order.lambda_handler"
  runtime          = "python3.12"
  source_code_hash = filebase64sha256("get_order.zip")

  tags = {
    Environment = "production"
  }
}

# API Gateway
resource "aws_apigatewayv2_api" "orders_api" {
  name          = "OrdersAPI-tf"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["POST", "GET", "OPTIONS"]
    allow_headers = ["Content-Type"]
  }
}

# API Gateway Stage
resource "aws_apigatewayv2_stage" "orders_stage" {
  api_id      = aws_apigatewayv2_api.orders_api.id
  name        = "prod"
  auto_deploy = true
}

# Integration — POST Lambda
resource "aws_apigatewayv2_integration" "place_order_integration" {
  api_id             = aws_apigatewayv2_api.orders_api.id
  integration_type   = "AWS_PROXY"
  integration_uri    = aws_lambda_function.place_order.invoke_arn
  integration_method = "POST"
}

# Integration — GET Lambda
resource "aws_apigatewayv2_integration" "get_order_integration" {
  api_id             = aws_apigatewayv2_api.orders_api.id
  integration_type   = "AWS_PROXY"
  integration_uri    = aws_lambda_function.get_order.invoke_arn
  integration_method = "POST"
}

# Route — POST /orders
resource "aws_apigatewayv2_route" "post_orders" {
  api_id    = aws_apigatewayv2_api.orders_api.id
  route_key = "POST /orders"
  target    = "integrations/${aws_apigatewayv2_integration.place_order_integration.id}"
}

# Route — GET /orders/{userId}
resource "aws_apigatewayv2_route" "get_orders" {
  api_id    = aws_apigatewayv2_api.orders_api.id
  route_key = "GET /orders/{userId}"
  target    = "integrations/${aws_apigatewayv2_integration.get_order_integration.id}"
}

# Lambda permission — allow API Gateway to invoke POST Lambda
resource "aws_lambda_permission" "place_order_permission" {
  statement_id  = "AllowAPIGatewayInvokePlaceOrder"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.place_order.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.orders_api.execution_arn}/*/*"
}

# Lambda permission — allow API Gateway to invoke GET Lambda
resource "aws_lambda_permission" "get_order_permission" {
  statement_id  = "AllowAPIGatewayInvokeGetOrder"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_order.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.orders_api.execution_arn}/*/*"
}

# S3 Bucket for frontend
resource "aws_s3_bucket" "frontend" {
  bucket = "orders-form-bucket-tf"

  tags = {
    Environment = "production"
  }
}

# S3 Public Access
resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket                  = aws_s3_bucket.frontend.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# S3 Bucket Policy — public read
resource "aws_s3_bucket_policy" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  depends_on = [aws_s3_bucket_public_access_block.frontend]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.frontend.arn}/*"
      }
    ]
  })
}

# S3 Static Website Hosting
resource "aws_s3_bucket_website_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  index_document {
    suffix = "index.html"
  }
}

# Output — API Gateway URL
output "api_url" {
  value = aws_apigatewayv2_stage.orders_stage.invoke_url
}

# Output — S3 Website URL
output "website_url" {
  value = aws_s3_bucket_website_configuration.frontend.website_endpoint
}
# CloudFront Distribution
resource "aws_cloudfront_distribution" "frontend" {
  origin {
    domain_name = aws_s3_bucket_website_configuration.frontend.website_endpoint
    origin_id   = "S3-orders-form"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  enabled             = true
  default_root_object = "order-form-complete.html"

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-orders-form"

    forwarded_values {
      query_string = false
      cookies { forward = "none" }
    }

    viewer_protocol_policy = "redirect-to-https"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Environment = "production"
  }
}

# Output — CloudFront URL
output "cloudfront_url" {
  value = "https://${aws_cloudfront_distribution.frontend.domain_name}"
}