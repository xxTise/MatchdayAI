data "archive_file" "fetch_match_data" {
  type        = "zip"
  source_dir  = "${path.module}/../backend/lambdas/fetchMatchData"
  output_path = "${path.module}/../backend/lambdas/fetchMatchData.zip"
}

resource "aws_iam_role" "lambda_exec" {
  name = "lambda_exec_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Effect    = "Allow",
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "fetch_match_data" {
  function_name    = "fetch_match_data"
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  role             = aws_iam_role.lambda_exec.arn
  filename         = data.archive_file.fetch_match_data.output_path
  source_code_hash = data.archive_file.fetch_match_data.output_base64sha256

  environment {
    variables = {
      API_FOOTBALL_KEY = "f2ad1aa313783118a569cedb91c852a6"
      CACHE_TABLE      = aws_dynamodb_table.match_cache.name
    }
  }
}

# ───────────────────────────────────────────────────────
# EventBridge: trigger fetch_match_data every 5 minutes

resource "aws_cloudwatch_event_rule" "every_5_min" {
  name                = "every_5_min"
  schedule_expression = "rate(5 minutes)"
}

resource "aws_cloudwatch_event_target" "fetch_match_target" {
  rule      = aws_cloudwatch_event_rule.every_5_min.name
  target_id = "fetch_match_data_target"
  arn       = aws_lambda_function.fetch_match_data.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.fetch_match_data.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.every_5_min.arn
}
# ───────────────────────────────────────────────────────

# ───────────────────────────────────────────────────────
# DynamoDB Table for Match Data Caching

resource "aws_dynamodb_table" "match_cache" {
  name           = "MatchDataCache"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "fixture_id"

  attribute {
    name = "fixture_id"
    type = "S"
  }
}

resource "aws_iam_role_policy" "dynamo_access" {
  name = "lambda_dynamo_policy"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action   = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem"
        ],
        Effect   = "Allow",
        Resource = aws_dynamodb_table.match_cache.arn
      }
    ]
  })
}
# ───────────────────────────────────────────────────────
