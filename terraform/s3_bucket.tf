resource "aws_s3_bucket" "b" {
  bucket = "tf-bucket-vivian-test-846248"
}

resource "aws_s3_bucket_ownership_controls" "b" {
  bucket = aws_s3_bucket.b.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "b" {
  depends_on = [aws_s3_bucket_ownership_controls.b]

  bucket = aws_s3_bucket.b.id
  acl    = "private"
}

resource "aws_s3_bucket_versioning" "b" {
  bucket = aws_s3_bucket.b.id
  versioning_configuration {
    status = "Enabled"
  }
}