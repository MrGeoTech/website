<?php
/**
 * Get and return the contents of the requested section's HTML file.
 *
 * @param array $params The array of request parameters (e.g., $_GET or $_POST).
 * @return string The contents of the requested file or an error message if not found.
 */
function getIndexFileContents($params) {
    // Define the base directory for indexes
    $baseDir = __DIR__ . '/../indexes/';
    
    // Check if the 'section' parameter is provided, otherwise default to 'index'
    $section = isset($params['section']) ? $params['section'] : 'index';
    
    // Sanitize the section name to prevent directory traversal or malicious input
    if (preg_match('/[^\w\-]/', $section)) {
        // Invalid section name (contains characters like /, .., etc.)
        return "<p>Error: Invalid section name.</p>";
    }

    // Construct the full file path
    $filePath = $baseDir . basename($section) . '.html';
    
    // Check if the file exists; if not, default to "index.html"
    if (!file_exists($filePath)) {
        $filePath = $baseDir . 'index.html';
    }
    
    // If the file exists, return its contents
    if (file_exists($filePath)) {
        return file_get_contents($filePath);
    } else {
        // If the file doesn't exist, return an error message
        return "<p>Requested section not found.</p>";
    }
}
?>
