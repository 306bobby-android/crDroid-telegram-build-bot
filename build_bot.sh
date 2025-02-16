#!/bin/bash

# Prep build environment

source build/envsetup.sh

# Telegram Bot API Token and Chat ID
TELEGRAM_BOT_TOKEN=""
TELEGRAM_CHAT_ID=""
TELEGRAM_TOPIC_ID=""

# Log file
LOG_FILE="build.log"

# Function to log messages with timestamps
log_message() {
    local message="$1"
    echo "$(date +'%Y-%m-%d %H:%M:%S') - $message" | tee -a "$LOG_FILE"
}

# Function to send message to Telegram
send_message() {
    local message="$1"
    log_message "Sending message to Telegram: $message"
    response=$(curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
        -d "chat_id=$TELEGRAM_CHAT_ID" \
        -d "message_thread_id=$TELEGRAM_TOPIC_ID" \
        -d "text=$message" \
        -d "parse_mode=markdownv2")
    if [[ $(echo "$response" | grep '"ok":true') ]]; then
        log_message "Message sent successfully"
    else
        log_message "Failed to send message: $response"
    fi
}

# Function to edit a message on Telegram
edit_message() {
    local message_id="$1"
    local new_text="$2"
    log_message "Editing message on Telegram: $new_text"
    response=$(curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/editMessageText" \
        -d "chat_id=$TELEGRAM_CHAT_ID" \
        -d "message_id=$message_id" \
        -d "text=$new_text" \
	-d "parse_mode=markdownv2")
    if [[ $(echo "$response" | grep '"ok":true') ]]; then
        log_message "Message edited successfully"
    else
        log_message "Failed to edit message: $response"
    fi
}

# Function to upload OTA file via FTP
upload_ota() {
    local device="$1"
    local ota_file_path=$(ls out/target/product/$device/crDroid*.zip | head -n 1)
    local ota_boot_path=out/target/product/$device/boot.img
    local ota_dtbo_path=out/target/product/$device/dtbo.img
    local ota_vendor_boot_path=out/target/product/$device/vendor_boot.img


    if [ -f "$ota_file_path" ]; then
        curl --ssl -k -T "$ota_file_path" ftp://upme.crdroid.net/files/$device/11.x/ --user username:pass
        curl --ssl -k -T "$ota_boot_path" ftp://upme.crdroid.net/files/$device/11.x/boot+dtbo/ --user username:pass
        curl --ssl -k -T "$ota_dtbo_path" ftp://upme.crdroid.net/files/$device/11.x/boot+dtbo/ --user username:pass
        curl --ssl -k -T "$ota_vendor_boot_path" ftp://upme.crdroid.net/files/$device/11.x/recovery/ --user username:pass
        log_message "OTA file uploaded for $device: $ota_file_path"
        send_message "OTA file **uploaded** for *$device*: [Link to SF](https://sourceforge.net/projects/crdroid/files/$device/11.x/) check SourceForge **within 10 minutes**\\. Automatic OTA through settings is not supported *yet*, please wait for push or download manually\\. "
    else
        log_message "OTA file not found for $device"
        send_message "OTA file not found for $device"
    fi
}

# Function to send file to Telegram
send_file_to_telegram() {
    local device="$1"
    local file_path=$(ls out/target/product/$device/crDroid*.zip | head -n 1)
    if [ -f "$file_path" ]; then
        log_message "Sending file $file_path to Telegram"
        response=$(curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendDocument" \
            -F "chat_id=$TELEGRAM_CHAT_ID" \
            -F "document=@$file_path")
        if [[ $(echo "$response" | grep '"ok":true') ]]; then
            log_message "File sent successfully"
            send_message "Build output above"
        else
            log_message "Failed to send file: $response"
        fi
    else
        log_message "File not found: $file_path"
    fi
}


# Function to build for a single device
build_device() {
    local device="$1"
    send_message "Building _crDroid 11\\.x_ for *$device*\\.\\.\\."

    # Extract the message ID from the response
    message_id=$(echo $response | jq -r '.result.message_id')

    local start_time=$(date +%s)

    log_message "Starting build for $device"

   # Capture the output of the build command (both stdout and stderr) and log it continuously
    build_output=$(mktemp)
    { breakfast $device && brunch $device; } 2>&1 | tee -a "$LOG_FILE" | tee "$build_output" |
    while IFS= read -r line; do
        log_message "$line"
        if [[ "$line" =~ ([0-9]+)% ]]; then
            local percentage="${BASH_REMATCH[1]}"
            if (( percentage != last_percentage )); then
                last_percentage=$percentage
                edit_message "$message_id" "Building crDroid 11\\.x for *$device*\\ ${percentage}% *Brought to you by BuildPC NEXT*"
            fi
        fi
    done

    if echo "$build_output" | grep -q "Failed to build some targets"; then
        local build_status=1
    else
        local build_status=0
    fi

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    local duration_minutes=$((duration / 60))
    local duration_seconds=$((duration % 60))

    if [ $build_status -eq 0 ]; then
        send_message "Build for *$device* completed **successfully** in *${duration_minutes} minutes and ${duration_seconds} seconds*\\."
        log_message "Build for $device completed successfully in ${duration_minutes} minutes and ${duration_seconds} seconds."
        upload_ota "$device"  # Upload the OTA file after a successful build
    else
        send_message "Build for *$device* **failed** after *${duration_minutes} minutes and ${duration_seconds} seconds*\\."
        log_message "Build for $device failed after ${duration_minutes} minutes and ${duration_seconds} seconds."
    fi

    rm -f "$build_output"
}

# List of devices to build for
devices=("redfin" "bramble" "barbet")

# Loop through devices and build
for device in "${devices[@]}"; do
    build_device "$device"
done

# Notify completion
send_message "All builds completed\\."
log_message "All builds completed."
