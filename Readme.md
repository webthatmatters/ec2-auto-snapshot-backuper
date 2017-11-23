# EC2 Automated AWS Instance Snapshot Creator

Connects to AWS CLI configured accounts and Creates a snapshot based on a cron for each specific Instance.

Optionally, adds permission to AWS Manager Account to manage all snapshots from one account.

## Installation

Install Python: `sudo apt-get install python-pip -y`

Install AWS CLI Tools: `sudo pip install awscli`


## Configuration

### AWS 


**IAM**

Create the IAM Policy with permissions:

```
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "Stmt1426256275000",
            "Effect": "Allow",
            "Action": [
                "ec2:CreateSnapshot",
                "ec2:CreateTags",
                "ec2:ModifySnapshotAttribute",
                "ec2:DeleteSnapshot",
                "ec2:DescribeSnapshots",
                "ec2:DescribeVolumes"
            ],
            "Resource": [
                "*"
            ]
        }
    ]
}
```
Now create an IAM User for each AWS account with permissions on the instances and attach the backuper Policy to the User.

`ModifySnapshotAttribute` is only required if manager account will exist.

**CLI**

Configure all the required AWS profiles for each account with permissions on desired Instances to your Linux User.

A `default` profile will be configured without the `--profile` attribute.

```
aws configure --profile backuper
```
```
AWS Access Key ID [None]: AKIAI44QH8DHBEXAMPLE
AWS Secret Access Key [None]: je7MtGbClwBF/2Zp9Utk/h3yCo8nvbEXAMPLEKEY
Default region name [None]: eu-west-1
Default output format [None]: text
```

### Instances

To Setup Automated snapshots to an Instance you must add a `.conf` file with your Instance configurations.

Copy the `instances/example.conf` to your configuration file and replace existing values with the correct values

```
vim instances/example.conf
```
```conf
Snapshot_Name          # Snapshot Name Attribute (no spaces available)
i-04081123123123123    # EBS Instance id
eu-west-1              # Instance Region
default                # AWS CLI profile with access on the Instance
7                      # Amount of days you want to retain backups.

```

### Cronjobs

In order to create Snapshots in different frequency between Instances, you must create a cron for each instance.

```
# AWS AUTOMATED SNAPSHOT BACKUPER
00 18 * * * AWS_CONFIG_FILE="/home/user/.aws/config" /path/to/ec2_snapshot_backuper/snapshot.sh < /path/to/ec2_snapshot_backuper/instances/dev_server.conf
```

### Manageer Account (Optional)

A manager account is used to copy all auto-created snapshots to 1 manager AWS account.

Copy the `manager-example.conf` to `manager.conf` and replace existing values with the correct values

```
vim manager.conf
```
```conf
default_aws_profile=default         # AWS CLI Manager configured profile
default_aws_user_id=3500000000      # AWS User Id for the Manager Account
```

## Logs

Logs for each instance is created in the `logs` directory with the snapshot name on the file name.

Max lines per instance log file is 5000.

-----
This script is created for Software Houses by [Web That Matters LLC.](https://webthatmatters.com/) to Automatically create and manage EC2 snapshots from Multiple Accounts. 
The basic snapshot script is forked from [Casey Labs Inc.](https://www.caseylabs.com).