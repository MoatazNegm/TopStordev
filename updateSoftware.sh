
#!/bin/bash

# Check if a version argument is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <version_name>"
    exit 1
fi

### Decrypt and extract updates

# Define file paths
output_dir="/TopStordata"
encrypted_filename="$output_dir/software_update_$1.zip.enc"
zip_filename="$output_dir/software_update_$1.zip"
encryption_password="your_password"  # Replace with your own password
# QSD5.352 r5 (validator N3): a package uploaded through software/localFileUpdate is saved in /TopStordata/uploads, a downloaded
# one (downloadSoftwareUpdate.sh) in /TopStordata; take the upload when /TopStordata has none (a symlink is never taken)
if [ ! -f "$encrypted_filename" ] && [ -f "$output_dir/uploads/software_update_$1.zip.enc" ] && [ ! -L "$output_dir/uploads/software_update_$1.zip.enc" ]; then
    encrypted_filename="$output_dir/uploads/software_update_$1.zip.enc"
fi

# Check if the encrypted file exists
if [ ! -f "$encrypted_filename" ]; then
    echo "Error: Encrypted file $encrypted_filename not found."
    exit 1
fi

# Decrypt the file using OpenSSL (AES-256 encryption with PBKDF2)
openssl enc -aes-256-cbc -d -pbkdf2 -in "$encrypted_filename" -out "$zip_filename" -pass pass:"$encryption_password"

# Extract the zip file into TopStordata/
unzip -o "$zip_filename" -d "$output_dir"

# Clean up the decrypted zip file
rm "$zip_filename"

# Output result
echo "The encrypted file has been decrypted and extracted in $output_dir."

#### Update main repos

# Define repository paths
repo1="/TopStor"
repo2="/pace"
repo3="/topstorweb"
temp_repo1="$output_dir/TopStor"
temp_repo2="$output_dir/pace"
temp_repo3="$output_dir/topstorweb"

# Function to pull changes from temp directory to the main repository
pull_changes() {
    local repo_path="$1"
    local temp_repo_path="$2"
    #if [ ! -d "$repo_path/.git" ]; then
    #    echo "Error: $repo_path is not a valid git repository. Failed"
    #    return
    #fi
    echo "Pulling changes from $temp_repo_path to $repo_path..."
    cd "$repo_path"
    git remote add temprepo "/TopStor/$temp_repo_path"
    git pull temprepo "$3"
}

# Perform git pull for each repository
pull_changes "$repo1" "$temp_repo1" $1
pull_changes "$repo2" "$temp_repo2" $1
pull_changes "$repo3" "$temp_repo3" $1

# Output result

### TODO: myrepopush

echo "Software Update Completed"
