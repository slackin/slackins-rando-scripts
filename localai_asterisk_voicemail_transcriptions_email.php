<?php

function processFile($wav_file, $txt_file, $sender_email, $sender_name, $email, $txtData)
{
    // Fork a new process
    $pid = pcntl_fork();
    if ($pid == -1) {
        die('Could not fork');
    } else if ($pid) {
        // We are the parent process
        // Continue to the next file
        return;
    } else {
        // We are the child process
        // Process the file and send the email

        // Initialize a cURL session
        $ch = curl_init();

        // Set the URL
        curl_setopt($ch, CURLOPT_URL, 'http://your.localai.server:8080/v1/audio/transcriptions');

        // Set the request to POST
        curl_setopt($ch, CURLOPT_POST, 1);

        // Set the content type
        $headers = array();
        $headers[] = 'Content-Type: multipart/form-data';
        curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);

        // Prepare the file for upload
        $cfile = new CURLFile($wav_file);

        // Set the POST fields
        $postFields = array(
            'file' => $cfile,
            'model' => 'whisper-large-q5_0'
        );
        curl_setopt($ch, CURLOPT_POSTFIELDS, $postFields);

        // Set options to follow redirection and to return the response
        curl_setopt($ch, CURLOPT_FOLLOWLOCATION, true);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);

        // Execute the cURL request
        $response = curl_exec($ch);

        // Close the cURL session
        curl_close($ch);
        
        // Decode the JSON response
        $json_response = json_decode($response, true);

        // Get the 'text' field from the JSON data
        $transcription_output = $json_response['text'];

        // This part is left as a placeholder as PHP doesn't have a built-in way to execute curl commands
        //$transcription_output = $response;

        // Encode the .wav file in Base64
        $wav_base64 = base64_encode(file_get_contents($wav_file));

        // Get the file type and file name
        $file_type = mime_content_type($wav_file);
        $file_name = basename($wav_file);

        // Create an email message with the .txt file content and the transcription output
        $headers = "From: $sender_name <$sender_email>\r\n";
        $headers .= "MIME-Version: 1.0\r\n";
        $headers .= "Content-Type: multipart/mixed; boundary=\"BOUNDARY\"\r\n";
        $subject = $txtData['callerid'];

        $message = "--BOUNDARY\r\n";
        $message .= "Content-Type: text/plain; charset=us-ascii\r\n";
        $message .= "Content-Disposition: inline\r\n";
        $message .= "\r\n";
        $message .= "$transcription_output\r\n";
        $message .= "\r\n";

        // Add the .wav file to the email
        $message .= "--BOUNDARY\r\n";
        $message .= "Content-Type: $file_type; name=\"$file_name\"\r\n";
        $message .= "Content-Transfer-Encoding: base64\r\n";
        $message .= "Content-Disposition: attachment; filename=\"$file_name\"\r\n";
        $message .= "\r\n";
        $message .= "$wav_base64\r\n";
        $message .= "\r\n";
        $message .= "--BOUNDARY--";

        // Send the email
        mail($email, $subject, $message, $headers);

        // Exit the child process
        exit;
    }
}


$directory = "/var/spool/asterisk/voicemail/default/3520/INBOX";
$destDirectory = "/var/spool/asterisk/voicemail/default/3520/PROCESSED";
$sender_email = "someone@somewhere.net";
$email = "someone_else@somewhere.com";
$sender_name = "Asterisk Voicemail";

// Start an infinite loop to continuously monitor the directory
while (true) {
    // Check if any .wav file exists in the directory
    $wav_files = glob($directory . "/*.wav");

    // If at least one .wav file is found, process each file
    if (count($wav_files) > 0) {
        // Iterate over each found .wav file
        foreach ($wav_files as $wav_file) {
            // Print a message indicating that a .wav file is moved
            echo "A .wav file has been moved into the directory: $wav_file\n";

            // Extract the base filename (without extension) of the .wav file
            $base_name = pathinfo($wav_file, PATHINFO_FILENAME);

            // Construct the path to the corresponding .txt file
            $txt_file = $directory . "/" . $base_name . ".txt";

            // Check if the corresponding .txt file exists
            if (file_exists($txt_file)) {
                // Read the content of the .txt file
                $txt_content = file_get_contents($txt_file);

                // Explode the input data into lines
                $lines = explode("\n", $txt_content);

                // Initialize an empty array to store parsed data
                $txtData = array();

                // Loop through each line
                foreach ($lines as $line) {
                    // Explode each line into key-value pairs
                    $parts = explode('=', $line, 2);
                    if (count($parts) == 2) {
                        $key = trim($parts[0]);
                        $value = trim($parts[1]);
                        // Store the key-value pair in the parsedData array
                        $txtData[$key] = $value;
                    }
                }

                // Regular expression pattern to match the number between < and >
                $pattern = '/<(.*?)>/';

                // Perform the regular expression match
                if (preg_match($pattern, $txtData['callerid'], $matches)) {
                    // Extracted number will be in the first capturing group
                    $extractedNumber = $matches[1];
                    echo "Extracted Number: $extractedNumber";
                } else {
                    echo "No match found.";
                }

                // Print a message indicating that a .txt file is found and append it to the email
                echo "A .txt file is found: $txt_file\n";

                // Source file path
                $sourceTxtFile = $directory . "/" . $base_name . ".txt";
                $sourceWavFile = $directory . "/" . $base_name . ".wav";

                // Destination file path
                $destinationTxtFile = $destDirectory . "/" . $txtData['origtime'] . "-" . $extractedNumber . ".txt";
                $destinationWavFile = $destDirectory . "/" . $txtData['origtime'] . "-" . $extractedNumber . ".wav";

                // Move the file
                if (rename($sourceWavFile, $destinationWavFile)) {
                    echo "File moved successfully.";
                } else {
                    echo "Error: File could not be moved.";
                }

                // Move the file
                if (rename($sourceTxtFile, $destinationTxtFile)) {
                    echo "File moved successfully.";
                } else {
                    echo "Error: File could not be moved.";
                }

                // Process the file and send the email in a separate process
                processFile($destinationWavFile, $destinationTxtFile, $sender_email, $sender_name, $email, $txtData);
            }
        }
    }

    // Sleep for a while before checking the directory again
    sleep(1);
}