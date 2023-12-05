#!/bin/bash

# Function to configure AWS
configure_aws() {
    aws configure set aws_access_key_id $AWS_ACCESS_KEY
    aws configure set aws_secret_access_key $AWS_SECRET_ACCESS_KEY
    aws configure set default.region $AWS_DEFAULT_REGION
}

# Configure AWS
configure_aws

# Function to send an email using AWS SNS
send_email() {
    local subject=$1
    local message=$2
    local output=$(aws sns publish --topic-arn "$SNS_TOPIC_ARN" --subject "$subject" --message "$message" --region "$AWS_DEFAULT_REGION" 2>&1)
    local exit_code=$?
    
    if [[ $exit_code -eq 0 ]]; then
        echo "Email sent successfully"
    else
        echo "Failed to send email: $output"
        echo "Failed to send email: $output" >> /var/www/html/email_error.log
    fi
}

# Retrieve the secret ARN from the command line argument
SECRET_ARN=$SECRET_ARN

# Retrieve the ENV datas from AWS Secret Manager
secret_value=$(aws secretsmanager get-secret-value --secret-id $SECRET_ARN --region $AWS_DEFAULT_REGION --query SecretString --output text)
if [ -z "$secret_value" ]; then
    error_message="Failed to retrieve secret from AWS Secret Manager"
    send_email "Deployment Failed" "$error_message"
    echo "$error_message"
    exit 1
fi

GIT_PAT_ENCODED=$(echo $secret_value | jq -r '.GIT_PAT')
GIT_USER=$(echo $secret_value | jq -r '.GIT_USER')
GIT_REPO=$(echo $secret_value | jq -r '.GIT_REPO')
GIT_MASTER_BRANCH=$(echo $secret_value | jq -r '.GIT_MASTER_BRANCH')
MDL_DB_TYPE=$(echo $secret_value | jq -r '.MDL_DB_TYPE')
MDL_DB_HOST=$(echo $secret_value | jq -r '.MDL_DB_HOST')
MDL_DB_NAME=$(echo $secret_value | jq -r '.MDL_DB_NAME')
MDL_DB_USER=$(echo $secret_value | jq -r '.MDL_DB_USER')
MDL_DB_PASS=$(echo $secret_value | jq -r '.MDL_DB_PASS')
MDL_WEB_ROOT=$(echo $secret_value | jq -r '.MDL_WEB_ROOT')
MDL_DATA=$(echo $secret_value | jq -r '.MDL_DATA')

# Check if any of the required environment variables are empty
if [ -z "$GIT_PAT_ENCODED" ] || [ -z "$GIT_USER" ] || [ -z "$GIT_REPO" ] || [ -z "$MDL_DB_TYPE" ] || [ -z "$MDL_DB_HOST" ] || [ -z "$MDL_DB_NAME" ] || [ -z "$MDL_DB_USER" ] || [ -z "$MDL_DB_PASS" ] || [ -z "$MDL_WEB_ROOT" ] || [ -z "$MDL_DATA" ]; then
    error_message="One or more required environment variables are missing"
    send_email "Deployment Failed" "$error_message"
    echo "$error_message"
    exit 1
fi

# Set as environment variables for PHP application
echo "export MDL_DB_TYPE='$MDL_DB_TYPE'" >> /etc/apache2/envvars
echo "export MDL_DB_HOST='$MDL_DB_HOST'" >> /etc/apache2/envvars
echo "export MDL_DB_NAME='$MDL_DB_NAME'" >> /etc/apache2/envvars
echo "export MDL_DB_USER='$MDL_DB_USER'" >> /etc/apache2/envvars
echo "export MDL_DB_PASS='$MDL_DB_PASS'" >> /etc/apache2/envvars
echo "export MDL_WEB_ROOT='$MDL_WEB_ROOT'" >> /etc/apache2/envvars
echo "export MDL_DATA='$MDL_DATA'" >> /etc/apache2/envvars

# Start the cron service
service cron start


# Construct the repository URL using the encoded PAT value
REPO_URL=https://$GIT_PAT_ENCODED@github.com/$GIT_USER/$GIT_REPO
REPO_NAME=svhs
REPO_PATH=/var/www/html
REPO_BRANCH=$GIT_MASTER_BRANCH

# Clone the repository
if sudo git clone --branch $REPO_BRANCH $REPO_URL $REPO_PATH/$REPO_NAME; then
    # Set safe directory for Git
    git config --global --add safe.directory /var/www/html/svhs

    # Set permissions for moodledata
    chown -R www-data:www-data /var/www/html/svhs
    chmod -R 755 /var/www/html/svhs

    # Define the new document root value
    NEW_DOCUMENT_ROOT="/var/www/html/svhs"

    # Update the document root in the 000-default.conf and default-ssl.conf file
    sed -i "s|DocumentRoot /var/www/html|DocumentRoot $NEW_DOCUMENT_ROOT|" /etc/apache2/sites-available/000-default.conf
    

    # Modify max_execution_time setting in php.ini-development and php.ini-production
    sed -i 's/max_execution_time = 30/max_execution_time = 120/' /usr/local/etc/php/php.ini-development
    sed -i 's/max_execution_time = 30/max_execution_time = 120/' /usr/local/etc/php/php.ini-production
    
    # Sleep for 60 seconds (1 minute) to allow ownership and permission changes to take effect
    sleep 60
    
    # Start Apache service in the background
    sudo /usr/sbin/apache2ctl -D FOREGROUND &

    # Store the process ID of the Apache service
    apache_pid=$!

    # Sleep for a few seconds to allow Apache to start
    sleep 10

    # Check if Apache process is still running
    if kill -0 $apache_pid 2>/dev/null; then
      # Send success email
      send_email "Deployment Success" "The deployment completed successfully."

      # Keep container running
      tail -f /dev/null
    else
        error_message="Apache server failed to start"
        send_email "Deployment Failed" "$error_message"
        echo "$error_message"
        exit 1
    fi

else
    error_message="Git clone failed"
    send_email "Deployment Failed" "$error_message"
    echo "$error_message"
    exit 1
fi

exec "$@"
