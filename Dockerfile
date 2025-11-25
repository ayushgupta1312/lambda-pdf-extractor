# Use the official AWS Lambda Python 3.13 base image
FROM public.ecr.aws/lambda/python:3.13

# Set environment variables
ENV BUCKET_NAME=magnifact-pdf
ENV INPUT_FOLDER_NAME=input-pdf-files
ENV OUTPUT_FOLDER_NAME=output-files

# Copy requirements file
COPY requirements.txt ${LAMBDA_TASK_ROOT}/

# Install dependencies
RUN pip install --no-cache-dir -r ${LAMBDA_TASK_ROOT}/requirements.txt

# Copy function code
COPY src/lambda_function.py ${LAMBDA_TASK_ROOT}/

# Set the CMD to the Lambda handler
CMD ["lambda_function.lambda_handler"]
