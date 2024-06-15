<?php

function processFile($wav_file, $txt_file, $sender_email, $sender_name, $email, $cid_name, $cid_num)
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
        curl_setopt($ch, CURLOPT_URL, 'http://10.42.1.33:8080/v1/audio/transcriptions');

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

        echo "Transcribing voicemail...\n";
        // Record the start time
        $start_time = microtime(true);

        // Execute the cURL request
        $response = curl_exec($ch);

        // Record the end time
        $end_time = microtime(true);

        // Calculate the difference (this is the time it took for the cURL command to finish)
        $execution_time = $end_time - $start_time;

        echo "cURL execution time: $execution_time seconds.\n";

        echo "Transcription complete.\n";
        // Close the cURL session
        curl_close($ch);

        // Decode the JSON response
        $json_response = json_decode($response, true);

        // Get the 'text' field from the JSON data
        $transcription_output = $json_response['text'];

        // Read the files
        $wavFileContent = file_get_contents($wav_file);
        $txtFileContent = file_get_contents($txt_file);

        // Generate a boundary string
        $boundary = md5(uniqid(time()));

        // Set the subject of the email
        $subject = $cid_name . ' - ' . $cid_num . ' - Voicemail Transcription';

        // Message headers
        $headers = "From: $sender_name <$sender_email>\r\n";
        $headers .= "MIME-Version: 1.0\r\n";
        $headers .= "Content-Type: multipart/mixed; boundary=\"$boundary\"\r\n";

        // Message body
        $body = "--$boundary\r\n";
        $body .= "Content-Type: text/plain; charset=us-ascii\r\n";
        $body .= "Content-Disposition: inline\r\n";
        $body .= "\r\n";
        $body .= "Name: $cid_name\r\n";
        $body .= "Number: $cid_num\r\n";
        $body .= "\r\n";
        $body .= "$transcription_output\r\n";
        $body .= "\r\n";

        // Add wav file
        $body .= "--$boundary\r\n";
        $body .= "Content-Type: audio/wav; name=\"" . basename($wav_file) . "\"\r\n";
        $body .= "Content-Transfer-Encoding: base64\r\n";
        $body .= "Content-Disposition: attachment; filename=\"" . basename($wav_file) . "\"\r\n\r\n";
        $body .= chunk_split(base64_encode($wavFileContent));

        // Add txt file
        $body .= "--$boundary\r\n";
        $body .= "Content-Type: text/plain; name=\"" . basename($txt_file) . "\"\r\n";
        $body .= "Content-Transfer-Encoding: base64\r\n";
        $body .= "Content-Disposition: attachment; filename=\"" . basename($txt_file) . "\"\r\n\r\n";
        $body .= chunk_split(base64_encode($txtFileContent));

        // End of message
        $body .= "--$boundary--";

        // Send the email
        if (mail($email, $subject, $body, $headers)) {
            echo 'Message sent!\n';
        } else {
            echo 'Mailer Error.\n';
        }

        // Exit the child process
        exit;
    }
}

// Check if there are any arguments
if ($argc > 1) {
    // Print each argument
    for ($i = 1; $i < $argc; $i++) {
        echo "Argument $i: $argv[$i]\n";
    }
} else {
    echo "Please provide config: <php voicemail.php config.php>.\n";
    exit;
}

$config_file = $argv[1];

if (!file_exists($config_file)) {
    echo "Error: Configuration file does not exist.\n";
    exit;
}

require $config_file;

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
                    echo "Extracted Number: $extractedNumber\n";
                } else {
                    echo "No match found.\n";
                }

                // Regular expression pattern to match the text before the <
                $pattern = '/(.*?)</';

                // Perform the regular expression match
                if (preg_match($pattern, $txtData['callerid'], $matches)) {
                    // Extracted text will be in the first capturing group
                    $extractedText = trim($matches[1]);
                    echo "Extracted Text: $extractedText\n";
                } else {
                    echo "No match found.\n";
                }

                // set cid_name and cid_num
                $cid_name = $extractedText;
                $cid_num = $extractedNumber;

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
                    echo "File moved successfully. $sourceWavFile, $destinationWavFile\n";
                } else {
                    echo "Error: File could not be moved.\n";
                }

                // Move the file
                if (rename($sourceTxtFile, $destinationTxtFile)) {
                    echo "File moved successfully. $sourceTxtFile, $destinationTxtFile\n";
                } else {
                    echo "Error: File could not be moved.\n";
                }

                // Process the file and send the email in a separate process
                processFile($destinationWavFile, $destinationTxtFile, $sender_email, $sender_name, $email, $cid_name, $cid_num);
            }
        }
    }

    // Sleep for a while before checking the directory again
    sleep(1);
}