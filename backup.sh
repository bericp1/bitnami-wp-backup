#!/usr/bin/env bash

set -e

# Process args
WP_ROOT_DIR="${1}"
if [ -z "${WP_ROOT_DIR}" ] || [ "${WP_ROOT_DIR}" == "auto" ]
then
  WP_ROOT_DIR=`wp eval 'echo dirname(WP_CONTENT_DIR);' 2>/dev/null`
fi
if [ -z "${WP_ROOT_DIR}" ]
then
  echo "Could not detect wordpress root directory!"
  echo "Try setting WP_CLI_CONFIG_PATH to a valid wp-cli.yml config file that points to your WP install"
  echo "or providing the path as the first argument to this script."
  exit 1;
fi
SITE_NAME="${2}"
if [ -z "${SITE_NAME}" ] || [ "${SITE_NAME}" == "auto" ]
then
  SITE_NAME=`wp --path="${WP_ROOT_DIR}" eval 'echo sanitize_title(get_bloginfo("name"));' 2>/dev/null`
fi
if [ -z "${SITE_NAME}" ]
then
  SITE_NAME="wordpress"
  echo "WARNING: could not detect site name using wp-cli and none provided as an argument. Using 'wordpress'."
fi
S3_BUCKET="${3}"

# Precalculate all of our paths, etc.
NOW=`date -u +%s`
NOW_YEAR=`date -u +%Y`
NOW_MONTH=`date -u +%m`
NOW_STR=`date -u +%Y-%m-%dT%H:%M:%S`

ROOT_DIR="/opt/wp-backup"
BACKUP_NAME="backup_${SITE_NAME}_${NOW_STR}"
STAGING_ROOT_DIR="${ROOT_DIR}/staging"
STAGING_DIR="${STAGING_ROOT_DIR}/${BACKUP_NAME}"
SQL_STAGING_PATH="${STAGING_DIR}/backup.sql"
CONTENT_STAGING_PATH="${STAGING_DIR}/wp-content.tar.gz"
INFO_STAGING_PATH="${STAGING_DIR}/info.txt"
DEST_ROOT_DIR="${ROOT_DIR}/backups"
DEST_SUBDIR="${NOW_YEAR}/${NOW_MONTH}"
DEST_DIR="${DEST_ROOT_DIR}/${DEST_SUBDIR}"
DEST_FILE_NAME="${BACKUP_NAME}.tar.gz"
DEST_PATH="${DEST_DIR}/${DEST_FILE_NAME}"
if [ -z "${S3_BUCKET}" ]
then
  DEST_S3_URI=""
else
  DEST_S3_URI="s3://${S3_BUCKET}/${DEST_SUBDIR}/${DEST_FILE_NAME}"
fi

# Give the user some info and time to abort
echo "Starting backup..."
echo "User:              `id -zun`"
echo "Group:             `id -zgn`"
echo "WordPress Install: ${WP_ROOT_DIR}"
echo "Site Name:         ${SITE_NAME}"
echo "Now:               ${NOW_STR} (${NOW})"
echo "Backup Name:       ${BACKUP_NAME}"
echo "Staging:           ${STAGING_DIR}"
echo "Local Destination: ${DEST_PATH}"
if [ -z "${DEST_S3_URI}" ]
then
  echo "S3 Destination:    (will not upload to s3, no bucket name provided)"
else
  echo "S3 Destination:    ${DEST_S3_URI}"
fi
echo "Waiting 10 seconds before continuing in case something looks off..."
sleep 10
echo "Off we go!"
echo ""

# Ensure directories exist
echo "Ensuring directories exist..."
mkdir -p "${STAGING_DIR}"
mkdir -p "${DEST_DIR}"
echo "Done ensuring directories exist"
echo ""

# If the s3 destination is specified, check AWS access
if [ ! -z "${DEST_S3_URI}" ]
then
  echo "Checking S3 write access to '${S3_BUCKET}'..."
  echo "Testing write access at ${NOW}..." > "${STAGING_DIR}/s3test-${BACKUP_NAME}.txt"
  tar -czvf "${DEST_PATH}" -C "${STAGING_DIR}" "s3test-${BACKUP_NAME}.txt"
  aws s3 cp "${DEST_PATH}" "${DEST_S3_URI}"
  echo "Success! '${DEST_S3_URI}' is writable! Cleaning up..."
  aws s3 rm "${DEST_S3_URI}"
  rm -f "${DEST_PATH}"
  rm -f "${STAGING_DIR}/s3test-${BACKUP_NAME}.txt"
  echo "Done checking S3 write access"
  echo ""
fi

# Create info file
echo "Generating info file for backup at '${INFO_STAGING_PATH}'..."
echo "Backup started at ${NOW_STR} (${NOW})" > "${INFO_STAGING_PATH}"
echo "" >> "${INFO_STAGING_PATH}"
echo "User:              `id -zun`" >> "${INFO_STAGING_PATH}"
echo "Group:             `id -zgn`" >> "${INFO_STAGING_PATH}"
echo "WordPress Install: ${WP_ROOT_DIR}" >> "${INFO_STAGING_PATH}"
echo "Site Name:         ${SITE_NAME}" >> "${INFO_STAGING_PATH}"
echo "Backup Name:       ${BACKUP_NAME}" >> "${INFO_STAGING_PATH}"
echo "Staging:           ${STAGING_DIR}" >> "${INFO_STAGING_PATH}"
echo "Local Destination: ${DEST_PATH}" >> "${INFO_STAGING_PATH}"
echo "S3 Destination:    ${DEST_S3_URI:-'(no s3 upload)'}" >> "${INFO_STAGING_PATH}"
echo "" >> "${INFO_STAGING_PATH}"
echo "Done generating info file"
echo ""

# Backup database and compress database backup file
echo "Backing up database to '${SQL_STAGING_PATH}'..."
wp --path="${WP_ROOT_DIR}" db export "${SQL_STAGING_PATH}" --add-drop-table
echo "Compressing database backup to '${SQL_STAGING_PATH}.gz'"
gzip --suffix ".gz" "${SQL_STAGING_PATH}"
echo "Done backing up and compressing database"
echo ""

# Backup wp-content
echo "Backing up and compressing wp-content to '${CONTENT_STAGING_PATH}'..."
tar -czf "${CONTENT_STAGING_PATH}" --ignore-failed-read -C "${WP_ROOT_DIR}" "wp-content"
echo "Done backing up and compressing wp-content"
echo ""

# Mark end time in info file.
echo "Marking end data in info file..."
echo "Backup completed at `date -u +%Y-%m-%dT%H:%M:%S` (`date -u +%s`)" >> "${INFO_STAGING_PATH}"
echo "Done marking end data in info file"
echo ""

# Archive and compress backup files
echo "Archiving and compressing all backup files to '${DEST_PATH}'..."
tar -czvf "${DEST_PATH}" -C "${STAGING_ROOT_DIR}" "${BACKUP_NAME}"

# Clean up staging directory
echo "Cleaning up the staging directory '${STAGING_DIR}'..."
rm -rf "${STAGING_DIR}"
echo "Done cleaning up the staging directory"
echo ""

# Upload backup to S3 if required
if [ -z "${DEST_S3_URI}" ]
then
  echo "Skipping S3 upload since no bucket name was specified"
  echo ""
else
  echo "Uploading backup to S3 at '${DEST_S3_URI}'..."
  aws s3 cp "${DEST_PATH}" "${DEST_S3_URI}"
  echo "Done uploading backup to S3"
  echo ""
fi

echo "Backup completed successfully."
