# Bitnami WP Backup Scripts

A backup script that can be run on a [Bitnami WordPress server](https://bitnami.com/stack/wordpress) to backup the
default WordPress install (database and files), optionally to AWS S3.

## Prerequisites

-   If you want to backup to S3, ensure the `aws` CLI is installed: `sudo apt install awscli`
-   [`wp`](https://developer.wordpress.org/cli/) which is installed by default on bitnami instances.

## Setup

### Step 1: Clone and place this repository

1.  SSH into your Bitnami WordPress server as the `bitnami` user
2.  `cd /opt`
3.  `sudo git clone https://github.com/bericp1/bitnami-wp-backup.git wp-backup`
4.  `cd wp-backup/`
5.  `sudo mkdir logs`
6.  `sudo chown -R bitnami:bitnami .`
7.  `sudo chmod +x *.sh`

### Step 2 (Optional): Set up S3 backups

1.  Create an S3 bucket with no public permissions
2.  Create an IAM user with read/write access to that bucket, this policy should work (replace `bucket-name` with the
    name of your bucket):
    ```json
    {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Sid": "AllowAllReadWriteObjectActions",
                "Effect": "Allow",
                "Action": [
                    "s3:AbortMultipartUpload",
                    "s3:DeleteObject",
                    "s3:GetBucketAcl",
                    "s3:GetBucketLocation",
                    "s3:GetBucketPolicy",
                    "s3:GetObject",
                    "s3:GetObjectAcl",
                    "s3:ListBucket",
                    "s3:ListBucketMultipartUploads",
                    "s3:ListMultipartUploadParts",
                    "s3:PutObject",
                    "s3:PutObjectAcl"
                ],
                "Resource": [
                    "arn:aws:s3:::bucket-name/*"
                ]
            },
            {
                "Sid": "AllowRootAndHomeListingOfBucket",
                "Action": [
                    "s3:ListBucket"
                ],
                "Effect": "Allow",
                "Resource": [
                    "arn:aws:s3:::bucket-name"
                ],
                "Condition": {
                    "StringLike": {
                        "s3:prefix": [
                            "*"
                        ]
                    }
                }
            }
        ]
    }
    ```
3.  Place the IAM user's credentials in `/opt/wp-backup/s3creds.sh` (in the double quotes, replacing
    `YOUR_ACCESS_KEY_HERE` and `YOUR_SECRET_ACCESS_KEY_HERE`):
    ```shell script
    export AWS_ACCESS_KEY_ID="YOUR_ACCESS_KEY_HERE"
    export AWS_SECRET_ACCESS_KEY="YOUR_SECRET_ACCESS_KEY_HERE"
    ```
4.  Change the permissions appropriately:
    ```shell script
    chown bitnami:bitnami /opt/wp-backup/s3creds.sh && chmod 700 /opt/wp-backup/s3creds.sh
    ```

### Step 3: Test the script

If you are backing up to an S3 bucket, run (replacing `bucket-name` with the name of your bucket from above):

```shell script
source /opt/wp-backup/s3creds.sh && /opt/wp-backup/backup.sh "auto" "auto" "bucket-name"
```

Otherwise simply run:

```shell script
/opt/wp-backup/backup.sh
```

If an error occurs troubleshoot and fix it before continuing.

You may also want to test the cleanup script which deletes old backups

```shell script
 /opt/wp-backup/cleanup.sh
```

### Step 4: Schedule the scripts to run daily

These cron jobs will log all output to `/opt/wp-backup/logs/`.

1.  `sudo crontab -e -u bitnami` (select an editor if this is your first time running this script, nano is the easiest)
2.  Add the following 2 lines to schedule backups for 7:30 AM UTC and cleanups for 8:30 AM UTC:
    
    If you're using S3 (replace `bucket-name` with the name of your bucket from above):
    
    ```text
    30 7 * * * . /opt/bitnami/scripts/setenv.sh; . /opt/wp-backup/s3creds.sh; /opt/wp-backup/backup.sh "auto" "auto" "coffeeinbeakers-wp-backups" >> "/opt/wp-backup/logs/cron-backup-`date -u +\%s`.txt" 2>&1
    30 8 * * * . /opt/bitnami/scripts/setenv.sh; . /opt/wp-backup/s3creds.sh; /opt/wp-backup/cleanup.sh >> "/opt/wp-backup/logs/cron-cleanup-`date -u +\%s`.txt" 2>&1
    ```
    
    Otherwise:
    
    ```text
    30 7 * * * . /opt/bitnami/scripts/setenv.sh; /opt/wp-backup/backup.sh >> "/opt/wp-backup/logs/cron-backup-`date -u +\%s`.txt" 2>&1
    30 8 * * * . /opt/bitnami/scripts/setenv.sh; /opt/wp-backup/cleanup.sh >> "/opt/wp-backup/logs/cron-cleanup-`date -u +\%s`.txt" 2>&1
    ```

## Manual / Advanced Usage

### `backup.sh [wp-root] [site-name] [s3-bucket]`

Backs up a WordPress install.

If `wp-root` is not provided or is literally `"auto"`, we will use the global `wp` command to determine where the
WordPress install is. This works on bitnami's WordPress stack by default since the global `wp` command is automatically
preconfigured to point to the default WordPress install hosted in `/opt/bitnami/apps/wordpress/htdocs`. You can specify
a root explicitly if needed using this parameter to override this.

`site-name` is used in the names of the backup files and folders. It must be a sanitized string that's safe to be used
in the names of files and folders. If `site-name` is not provided or is literally `"auto"`, we will use the global `wp`
command to generate a site name slug using the following PHP:

```php
echo sanitize_title(get_bloginfo("name"));
```

If `s3-bucket` is provided, the backup will also be stored in s3 in the specified bucket. Ensure the
`AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` environment variables are set in order for the `aws` CLI to
authenticate. The backup script will bail out early if we're unable to write to the backup destination within the
bucket.

### `cleanup.sh`

Cleans up old local backups. Right now this is not configurable and it will always remove any backup anywhere in
`/opt/wp-backup/backups` that hasn't been modified in 1 week.
