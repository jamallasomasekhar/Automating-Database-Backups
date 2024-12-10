#!/bin/bash

# Function to display a loading animation
show_loading() {
  chars="/-\|"
  while :; do
    for (( i=0; i<${#chars}; i++ )); do
      printf "\r%s" "${chars:$i:1}"
      sleep 0.1
    done
  done
}

# Function to install the required database client
install_client() {
  case "$1" in
    mysql) sudo apt-get install -y mysql-client ;;
    postgres) sudo apt-get install -y postgresql-client ;;
    mssql) sudo apt-get install -y mssql-tools ;;
    oracle) echo "Oracle client installation not automated. Please install manually." ;;
    db2) echo "IBM Db2 client installation not automated. Please install manually." ;;
    mongodb)
      wget -qO - https://www.mongodb.org/static/pgp/server-6.0.asc | sudo apt-key add -
      echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu $(lsb_release -cs)/mongodb-org/6.0 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-6.0.list
      sudo apt-get update -y
      sudo apt-get install -y mongodb-database-tools ;;
    *) echo "Unsupported database type."; exit 1 ;;
  esac
}

# Function to perform the backup
backup_database() {
  local db_type=$1
  local connection=$2
  local backup_path=$3

  case "$db_type" in
    mysql)
      eval "mysqldump $connection > $backup_path" ;;
    postgres)
      eval "pg_dump $connection > $backup_path" ;;
    mssql)
      eval "sqlcmd -S $connection -Q \"BACKUP DATABASE mydb TO DISK='$backup_path'\"" ;;
    mongodb)
      eval "mongodump --uri=$connection --out=$backup_path" ;;
    *) echo "Backup not implemented for $db_type."; exit 1 ;;
  esac
}

# Ask the user for database type
echo "Select database type:"
echo "1) MySQL"
echo "2) PostgreSQL"
echo "3) Microsoft SQL Server"
echo "4) Oracle Database"
echo "5) IBM Db2"
echo "6) MongoDB"
read -rp "Enter your choice (1-6): " db_choice

case $db_choice in
  1) db_type="mysql" ;;
  2) db_type="postgres" ;;
  3) db_type="mssql" ;;
  4) db_type="oracle" ;;
  5) db_type="db2" ;;
  6) db_type="mongodb" ;;
  *) echo "Invalid choice."; exit 1 ;;
esac

# Ask for connection method
echo "How do you want to provide connection details?"
echo "1) Direct input (host, database, username, password)"
echo "2) Environment file"
echo "3) URL"
read -rp "Enter your choice (1-3): " conn_choice

case $conn_choice in
  1)
    read -rp "Enter host: " host
    read -rp "Enter database name: " dbname
    read -rp "Enter username: " username
    read -rsp "Enter password: " password
    echo
    if [[ $db_type == "mysql" ]]; then
      connection="-h $host -u $username -p$password $dbname"
    elif [[ $db_type == "postgres" ]]; then
      connection="--host=$host --username=$username $dbname"
    elif [[ $db_type == "mongodb" ]]; then
      connection="mongodb://$username:$password@$host/$dbname"
    fi
    ;;
  2)
    read -rp "Enter path to environment file: " env_file
    if [[ -f "$env_file" ]]; then
      source "$env_file"
      if [[ -z "$DB_HOST" || -z "$DB_USER" || -z "$DB_PASSWORD" || -z "$DB_NAME" ]]; then
        echo "Environment file is missing required variables (DB_HOST, DB_USER, DB_PASSWORD, DB_NAME)."
        exit 1
      fi
      if [[ $db_type == "mysql" ]]; then
        connection="-h $DB_HOST -u $DB_USER -p$DB_PASSWORD $DB_NAME"
      elif [[ $db_type == "postgres" ]]; then
        connection="--host=$DB_HOST --username=$DB_USER $DB_NAME"
      elif [[ $db_type == "mongodb" ]]; then
        connection="mongodb://$DB_USER:$DB_PASSWORD@$DB_HOST/$DB_NAME"
      fi
    else
      echo "Invalid environment file path. File does not exist."
      exit 1
    fi
    ;;
  3)
    read -rp "Enter connection URL: " connection
    ;;
  *) echo "Invalid choice."; exit 1 ;;
esac

# Install the required client
install_client "$db_type"

# Ask for backup path
read -rp "Enter the path where backup should be stored: " backup_path
if [[ -d "$backup_path" ]]; then
  backup_path="$backup_path/backup-$(date +%F-%H-%M-%S).dump"
elif [[ ! -d "$(dirname "$backup_path")" ]]; then
  echo "Invalid path. Directory does not exist."
  exit 1
fi

# Start backup
echo "Starting backup..."
show_loading &
LOADING_PID=$!
backup_database "$db_type" "$connection" "$backup_path"
kill $LOADING_PID
wait $LOADING_PID 2>/dev/null

echo "Backup completed successfully!"

# Remove the installed client
case "$db_type" in
  mysql) sudo apt-get remove -y mysql-client ;;
  postgres) sudo apt-get remove -y postgresql-client ;;
  mongodb) sudo apt-get remove -y mongodb-database-tools ;;
  *) echo "Manual cleanup required for $db_type." ;;
esac

exit 0