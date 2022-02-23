## About
Super AMI Copy allows you to copy AMIs across AWS partitions. It does this by:
1. Backing up the AMI to S3 in the source account 
2. Downloading the resulting AMI.bin file to your local machine
3. Splitting the AMI.bin file into segments
4. Uploading to the destination account via multipart upload 
4. Restoring the AMI.bin file to AMI