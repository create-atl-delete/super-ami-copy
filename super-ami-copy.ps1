param (
    $srcProfile = "srcAccountID", # The AWS CLI profile to use for actions in the source account 
    $srcRegion = "us-gov-west-1", 
    $srcBucket = "super-ami-copy-source-bucket", # Do not include "s3://"
    $dstProfile = "dstAccountID", # The AWS CLI profile to use for actions in the destination account 
    $dstRegion= "us-east-1",
    $dstBucket= "ami-copy-destination-bucket", # Do not include "s3://"
    $amiName = "ami-copy-$(Get-Date -Format MM-dd-yyyy)", # The name the AMI will receive in the destination account 
    $deleteOnComplete = 0, # Change to 1 to keep local files after completion
    $ErrorActionPreference = "Stop"
)

Try {
    Write-Host "Verifying credentials..."
    aws sts get-caller-identity --profile $srcProfile | Out-Null
    If (!$?) {
        Do {
            Write-host "No valid credentials found for $srcProfile. Please update credentials and press ENTER to try again" -Back Black -Fore Yellow -NoNewLine
            Read-Host 
            aws sts get-caller-identity | Out-Null
        }
        While (!$?)
    }
    aws sts get-caller-identity --profile $dstProfile | Out-Null
    If (!$?) {
        Do {
            Write-host "No valid credentials found for $dstProfile. Please update credentials and press ENTER to try again" -Back Black -Fore Yellow -NoNewLine
            Read-Host 
            aws sts get-caller-identity | Out-Null
        }
        While (!$?)
    }

    $AMI = Read-Host "Enter the ID of the AMI you want to backup:"
    Write-Host  "Starting backup..."
    aws ec2 create-store-image-task --image-id $AMI --bucket $srcBucket --region $srcRegion --profile $srcProfile

    $Percent = 0
    Do
        Start-Sleep -s 15
        $Percent = & aws ec2 describe-image-store-tasks --image-id $AMI --output text --query 'StoreImageTaskResults[*].ProgressPercentage' --region $srcRegion --profile $srcProfile
        Write-Host "$Percent complete..."
    Until ($Percent -eq 100)

    Write-Host "Backup complete. Downloading $AMI.bin to $(Get-Location)..."
    aws s3 cp s3://$srcBucket/$AMI'.bin' . --profile $srcProfile

    Write-Host "Download complete. Uploading $AMI.bin to $dstBucket..."
    $Prefix = & "C:\Program Files\Git\usr\bin\openssl.exe" rand -base64 12
    New-Item $Prefix -ItemType directory 
    & "C:\Program Files\Git\usr\bin\split.exe" -b 3000m "$AMI.bin" "$Prefix/$AMI.bin"
    aws s3api create-multipart-upload --bucket $dstBucket --key $Prefix/$AMI --profile $dstProfile
    $UploadID = & aws s3api list-multipart-uploads --bucket $dstBucket --prefix $Prefix --output text --query 'Uploads[*].UploadID' --profile $dstProfile
    $Part = 0
    $Parts = (Get-ChildItem .\* | Measure-Object).Count
    For ($File in (Get-Item .\*)) {
        $Part++
        $MD5 = & Get-FileHash $File -Algorithm MD5
        # If you use temporary credentials (aws-azure-login, saml2aws, etc.) with a short TTL, add a line to refresh your credentials here
        # Ex. saml2aws login -a $dstProfile --skip-prompt --force 
        Write-Host "Uploading part $Part of $Parts..."
        aws s3api upload-part --bucket $dstBucket --key $Prefix/$AMI --part-number $Part --body $File --content-md5 $MD5 --upload-id $UploadID --profile $dstProfile
    }
    aws s3api list-parts --bucket $dstBucket --key $Prefix/$AMI --upload-id $UploadID --profile $dstProfile | Set-Content "$Prefix/$AMI.json"
    & "C:\Program Files\Git\usr\bin\sed.exe" -i '/LastModified/d;/Size/d;/ETag/s/,$//;/]/s/,$//;Initiator/,/StorageClass/d' "$Prefix/$AMI.json"
    aws s3api complete-multipart-upload --multipart-upload "file://$Prefix/$AMI.json" --bucket $dstBucket --key $Prefix/$AMI --upload-id $UploadID --profile $dstProfile

    Write-Host "Upload complete. Starting restoration to AMI..."
    aws ec2 create-restore-image-task --bucket $dstBucket --object-key $Prefix/$AMI --name $amiName --region $dstRegion --profile $dstProfile
    Write-Host "Task started. You can check the progress in the EC2 console."

    If ($Cleanup) { 
        Write-Host "Removing $AMI.bin"
        Remove-Item "$AMI.bin"
        Remove-Item $Prefix -Recurse -Force
    }
    Exit 0
}
Catch {
	Write-Warning "An error occured. `n$_"
    Write-Host "Press ENTER to exit" -Back Black -Fore Yellow -NoNewLine
	Read-Host
	Exit 1 
}