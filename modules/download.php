<?php
require_once __DIR__ . '/Parsedown.php';

function removeMetaTags($filePath) {
    $file = fopen($filePath, 'r');
    $content = '';
    $inMeta = false;

    if ($file) {
        while (($line = fgets($file)) !== false) {
            $trimmedLine = trim($line);
            if ($trimmedLine === '---') {
                $inMeta = !$inMeta;
                continue; // Skip meta markers
            }
            if (!$inMeta) {
                $content .= $line; // Append non-meta content
            }
        }
        fclose($file);
    }

    return $content;
}

ob_start();

// Sanitize input parameters
$filePath = isset($_GET['file']) ? realpath($_GET['file']) : null;
$format = isset($_GET['format']) ? strtolower(trim($_GET['format'])) : '';

// Validate input
if (!$filePath || !file_exists($filePath) || pathinfo($filePath, PATHINFO_EXTENSION) !== 'md') {
    http_response_code(400);
    echo "Invalid file request.";
    exit;
}

if (!in_array($format, ['pdf', 'markdown', 'html'])) {
    http_response_code(400);
    echo "Invalid format request.";
    exit;
}

// Read the file content and remove meta tags
$contentWithoutMeta = removeMetaTags($filePath);

// Generate the output content based on format
$baseName = pathinfo($filePath, PATHINFO_FILENAME); // Base name of the file (no extension)
$outputFileName = "$baseName.$format";

switch ($format) {
    case 'markdown':
        // Serve the cleaned Markdown file
        header('Content-Type: text/markdown');
        header("Content-Disposition: attachment; filename=\"$outputFileName\"");
        echo $contentWithoutMeta;
        ob_end_flush();
        exit;

    case 'html':
        // Convert Markdown to HTML using Parsedown
        $parsedown = new Parsedown();
        $htmlContent = $parsedown->text($contentWithoutMeta);

        header('Content-Type: text/html');
        header("Content-Disposition: attachment; filename=\"$outputFileName\"");
        echo $htmlContent;
        ob_end_flush();
        exit;

    case 'pdf':
        // Convert Markdown to PDF using Pandoc
        $tempFilePath = sys_get_temp_dir() . "/$baseName.md";
        $tempOutputPath = sys_get_temp_dir() . "/$baseName.pdf";

        // Save the cleaned Markdown content to a temporary file
        file_put_contents($tempFilePath, $contentWithoutMeta);

        putenv('PATH=' . getenv('PATH') . ':/nix/store/k3dqr1xajnqc8k2ydr2ggwqy8q8ws1c3-pandoc-cli-3.1.11.1/bin/');

        // Command to run Pandoc
        $command = escapeshellcmd("pandoc " . escapeshellarg($tempFilePath) . " -o " . escapeshellarg($tempOutputPath));
        exec($command . " 2>&1", $output, $returnCode);

        // Cleanup the temporary Markdown file
        unlink($tempFilePath);

        if ($returnCode !== 0) {
            // Echo the command and its output for debugging
            http_response_code(500);
            echo "<p>Failed to generate PDF.</p>";
            echo "<p>Command: <code>$command</code></p>";
            echo "<p>Output:</p><pre>" . htmlspecialchars(implode("\n", $output)) . "</pre>";
            exit;
        }

        // Serve the generated PDF
        header('Content-Type: application/pdf');
        header("Content-Disposition: attachment; filename=\"$outputFileName\"");
        readfile($tempOutputPath);

        // Clean up temporary PDF file
        unlink($tempOutputPath);
        ob_end_flush();
        exit;
}

// Fallback for unsupported formats
http_response_code(400);
echo "Unsupported format.";
ob_end_flush();
exit;
?>
