# Lambda PDF Extractor

An AWS Lambda function that automatically extracts tables from PDF files and converts them to Excel (XLSX) format. The function is deployed as a container image and triggers when new PDF files are uploaded to an S3 bucket.

## Features

- **Automatic PDF Processing**: Triggers automatically when PDF files are uploaded to S3
- **Table Extraction**: Uses pdfplumber for accurate table detection and extraction
- **Excel Output**: Generates well-formatted XLSX files with auto-adjusted column widths
- **Multi-table Support**: Handles multiple tables per PDF, creating separate sheets for each
- **Container-based Deployment**: Uses AWS Lambda container images for easy dependency management
- **Configurable**: Environment variables for bucket name and folder paths

## Architecture

```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐     ┌──────────────┐
│  S3 Upload  │────▶│ Lambda       │────▶│ PDF Extract │────▶│ S3 Output    │
│  (PDF)      │     │ Trigger      │     │ & Convert   │     │ (XLSX)       │
└─────────────┘     └──────────────┘     └─────────────┘     └──────────────┘
```

## Prerequisites

- Docker installed and running
- AWS CLI configured (for deployment)
- AWS Account with appropriate permissions
- Python 3.13+ (for local testing without Docker)

## Project Structure

```
lambda-pdf-extractor/
├── Dockerfile              # Docker configuration for Lambda container
├── requirements.txt        # Python dependencies
├── src/
│   └── lambda_function.py  # Main Lambda handler code
├── sample-input/           # Sample PDF files for testing
│   └── sample_data.pdf     # Example PDF with tables
├── sample-output/          # Output directory for generated Excel files
├── tests/                  # Unit tests
│   └── test_lambda.py      # Test cases for the Lambda function
└── README.md               # This file
```

## Environment Variables

| Variable | Description | Default Value |
|----------|-------------|---------------|
| `BUCKET_NAME` | S3 bucket name for input/output | `magnifact-pdf` |
| `INPUT_FOLDER_NAME` | Folder name for input PDF files | `input-pdf-files` |
| `OUTPUT_FOLDER_NAME` | Folder name for output XLSX files | `output-files` |

## Local Development

### Building the Docker Image

```bash
# Build the Docker image
docker build -t lambda-pdf-extractor .
```

### Running Locally with Docker

You can test the Lambda function locally using the Lambda Runtime Interface Emulator (RIE) that's built into the base image:

```bash
# Run the container locally
docker run -p 9000:8080 \
  -e BUCKET_NAME=magnifact-pdf \
  -e INPUT_FOLDER_NAME=input-pdf-files \
  -e OUTPUT_FOLDER_NAME=output-files \
  -v ~/.aws:/root/.aws:ro \
  lambda-pdf-extractor
```

### Testing the Local Lambda

In another terminal, send a test event:

```bash
# Test with a sample S3 event
curl -XPOST "http://localhost:9000/2015-03-31/functions/function/invocations" \
  -d '{
    "Records": [
      {
        "s3": {
          "bucket": {
            "name": "magnifact-pdf"
          },
          "object": {
            "key": "input-pdf-files/sample_data.pdf"
          }
        }
      }
    ]
  }'
```

### Running Tests

```bash
# Install dependencies
pip install -r requirements.txt
pip install pytest

# Run tests
pytest tests/ -v
```

### Testing Without Docker (Local Python)

For quick local testing without Docker:

```bash
# Install dependencies
pip install -r requirements.txt

# Run the local test script
python -c "
from src.lambda_function import extract_tables_from_pdf, create_excel_from_tables

# Read sample PDF
with open('sample-input/sample_data.pdf', 'rb') as f:
    pdf_content = f.read()

# Extract tables
tables = extract_tables_from_pdf(pdf_content)
print(f'Found {len(tables)} tables')

# Create Excel
excel_content = create_excel_from_tables(tables)

# Save output
with open('sample-output/sample_data.xlsx', 'wb') as f:
    f.write(excel_content)
print('Output saved to sample-output/sample_data.xlsx')
"
```

## AWS Deployment

### Step 1: Create ECR Repository

```bash
# Create ECR repository
aws ecr create-repository --repository-name lambda-pdf-extractor --region <your-region>

# Get the repository URI
REPO_URI=$(aws ecr describe-repositories --repository-names lambda-pdf-extractor --query 'repositories[0].repositoryUri' --output text)
echo $REPO_URI
```

### Step 2: Build and Push Docker Image

```bash
# Authenticate Docker to ECR
aws ecr get-login-password --region <your-region> | docker login --username AWS --password-stdin $REPO_URI

# Build and tag the image
docker build -t lambda-pdf-extractor .
docker tag lambda-pdf-extractor:latest $REPO_URI:latest

# Push to ECR
docker push $REPO_URI:latest
```

### Step 3: Create IAM Role for Lambda

Create a file named `trust-policy.json`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

Create a file named `s3-policy.json`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject"
      ],
      "Resource": "arn:aws:s3:::magnifact-pdf/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:*"
    }
  ]
}
```

```bash
# Create IAM role
aws iam create-role \
  --role-name lambda-pdf-extractor-role \
  --assume-role-policy-document file://trust-policy.json

# Attach permissions policy
aws iam put-role-policy \
  --role-name lambda-pdf-extractor-role \
  --policy-name lambda-pdf-extractor-policy \
  --policy-document file://s3-policy.json
```

### Step 4: Create Lambda Function

```bash
# Get the role ARN
ROLE_ARN=$(aws iam get-role --role-name lambda-pdf-extractor-role --query 'Role.Arn' --output text)

# Create Lambda function
aws lambda create-function \
  --function-name pdf-to-excel-converter \
  --package-type Image \
  --code ImageUri=$REPO_URI:latest \
  --role $ROLE_ARN \
  --timeout 300 \
  --memory-size 1024 \
  --environment "Variables={BUCKET_NAME=magnifact-pdf,INPUT_FOLDER_NAME=input-pdf-files,OUTPUT_FOLDER_NAME=output-files}"
```

### Step 5: Create S3 Bucket and Configure Trigger

```bash
# Create S3 bucket (if it doesn't exist)
aws s3 mb s3://magnifact-pdf --region <your-region>

# Create the input and output folders
aws s3api put-object --bucket magnifact-pdf --key input-pdf-files/
aws s3api put-object --bucket magnifact-pdf --key output-files/

# Add Lambda permission for S3 to invoke it
aws lambda add-permission \
  --function-name pdf-to-excel-converter \
  --principal s3.amazonaws.com \
  --statement-id s3-trigger \
  --action lambda:InvokeFunction \
  --source-arn arn:aws:s3:::magnifact-pdf \
  --source-account <your-account-id>
```

### Step 6: Configure S3 Event Notification

Create a file named `s3-notification.json`:

```json
{
  "LambdaFunctionConfigurations": [
    {
      "Id": "PDFUploadTrigger",
      "LambdaFunctionArn": "arn:aws:lambda:<your-region>:<your-account-id>:function:pdf-to-excel-converter",
      "Events": ["s3:ObjectCreated:*"],
      "Filter": {
        "Key": {
          "FilterRules": [
            {
              "Name": "prefix",
              "Value": "input-pdf-files/"
            },
            {
              "Name": "suffix",
              "Value": ".pdf"
            }
          ]
        }
      }
    }
  ]
}
```

```bash
# Apply the S3 notification configuration
aws s3api put-bucket-notification-configuration \
  --bucket magnifact-pdf \
  --notification-configuration file://s3-notification.json
```

## Using the Function

Once deployed, simply upload a PDF file to the S3 bucket:

```bash
# Upload a PDF file
aws s3 cp your-file.pdf s3://magnifact-pdf/input-pdf-files/

# The Lambda will automatically process it and create an Excel file
# Check the output folder after a few seconds
aws s3 ls s3://magnifact-pdf/output-files/
```

## PDF Table Extraction Notes

### Supported PDF Types

- **Native PDFs**: PDFs with embedded text work best
- **Table formats**: Both bordered and borderless tables are supported
- **Multi-page PDFs**: All pages are processed

### Limitations

- **Scanned PDFs**: PDFs that are scanned images require OCR (not included in this version)
- **Complex layouts**: Highly complex layouts with merged cells may not extract perfectly
- **Non-tabular data**: Only tabular data is extracted; regular text paragraphs are ignored

### Adding OCR Support (Optional)

If you need to process scanned PDFs, you can add OCR capabilities by:

1. Add `pytesseract` and `pdf2image` to requirements.txt
2. Install Tesseract OCR in the Dockerfile
3. Modify the extraction logic to detect and handle image-based PDFs

Example Dockerfile modification for OCR:

```dockerfile
# Add after FROM statement
RUN yum install -y tesseract poppler-utils
```

## Troubleshooting

### Common Issues

1. **Permission Denied**: Ensure the Lambda role has proper S3 permissions
2. **Timeout**: Increase the Lambda timeout for large PDFs (default is 300 seconds)
3. **Memory Issues**: Increase Lambda memory for large PDFs (default is 1024 MB)
4. **No tables found**: The PDF might not contain properly formatted tables

### Viewing Logs

```bash
# View CloudWatch logs
aws logs tail /aws/lambda/pdf-to-excel-converter --follow
```

## Updating the Function

```bash
# After making code changes, rebuild and push
docker build -t lambda-pdf-extractor .
docker tag lambda-pdf-extractor:latest $REPO_URI:latest
docker push $REPO_URI:latest

# Update the Lambda function
aws lambda update-function-code \
  --function-name pdf-to-excel-converter \
  --image-uri $REPO_URI:latest
```

## License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.