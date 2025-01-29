<?php
// Define the base directory for Markdown files
$baseDirectory = __DIR__ . '/../docs/'; // Adjust this path to your Markdown directory
$prefix = '/docs/'; // Prefix for the paths

// Normalize baseDirectory to an absolute path
$baseDirectory = realpath($baseDirectory); // This converts to an absolute path

// Function to extract the title from a Markdown file
function getMarkdownTitle($filePath) {
    $fileContent = file($filePath);
    if ($fileContent === false) return null;

    $metaTitle = null;
    $inMeta = false;

    foreach ($fileContent as $line) {
        $trimmedLine = trim($line);

        // Detect the start and end of the meta block
        if ($trimmedLine === '---') {
            $inMeta = !$inMeta;
            continue;
        }

        // Check for a title in the meta block
        if ($inMeta && preg_match('/^title:\s*(.+)$/i', $trimmedLine, $matches)) {
            $metaTitle = trim($matches[1]);
        }

        // If not in meta, look for the first H1 heading
        if (!$inMeta && preg_match('/^# (.+)/', $trimmedLine, $matches)) {
            return $metaTitle ?: trim($matches[1]); // Return meta title or H1 title
        }
    }

    return $metaTitle; // Return meta title if no H1 title is found
}

// Get and sanitize the query parameter
$query = isset($_GET['q']) ? trim($_GET['q']) : '';
$section = isset($_GET['section']) ? trim($_GET['section']) : '';
if (empty($query)) {
    echo "Error: Empty query.";
    exit;
}

// Validate the section if provided
$sectionPath = $baseDirectory;
if (!empty($section)) {
    // Normalize the section path
    $normalizedSection = trim($section, '/');
    $sectionPath = realpath($baseDirectory . DIRECTORY_SEPARATOR . $normalizedSection);

    // Validate the resolved path
    if (!$sectionPath || strpos($sectionPath, realpath($baseDirectory)) !== 0) {
        echo "Error: Invalid section. " . ($sectionPath ?: "Path resolution failed");
        exit;
    }
}

// Function to recursively get all Markdown files
function getMarkdownFiles($dir) {
    $files = [];
    $iterator = new RecursiveIteratorIterator(new RecursiveDirectoryIterator($dir));
    foreach ($iterator as $file) {
        if ($file->isFile() && pathinfo($file->getFilename(), PATHINFO_EXTENSION) === 'md') {
            $files[] = $file->getPathname();
        }
    }
    return $files;
}

// Get all Markdown files in the directory and subdirectories
$markdownFiles = getMarkdownFiles($sectionPath);

// Array to store results with rankings
$results = [];

// Process each Markdown file
foreach ($markdownFiles as $filePath) {
    // Normalize file path to be relative to $baseDirectory
    $relativePath = realpath($filePath); // Get absolute path
    if (strpos($relativePath, $baseDirectory) === 0) {
        // Strip the base directory from the absolute path to get relative path
        $relativePath = str_replace($baseDirectory, '', $relativePath);
        // Ensure the result is in the format /docs/...
        $relativePath = '/docs' . $relativePath;
    } else {
        continue; // Skip files outside the base directory
    }

    $fileName = basename($filePath, '.md');
    $fileContent = file_get_contents($filePath);

    $rank = 0;

    // Check for file name match
    if (stripos($fileName, $query) !== false) {
        $rank += 10; // High weight for file name matches
    }

    // Search for title/subtitle matches
    preg_match_all('/^(#+)\s+(.*)$/m', $fileContent, $matches, PREG_SET_ORDER);
    foreach ($matches as $match) {
        $title = trim($match[2]);
        if (stripos($title, $query) !== false) {
            $rank += 7; // Medium weight for title/subtitle matches
            break; // Prevent over-ranking due to multiple matches
        }
    }

    // Search for general content matches
    if (stripos($fileContent, $query) !== false) {
        $rank += 3; // Lower weight for general content matches
    }

    // Add the file to results if it has a rank
    if ($rank > 0) {
        $title = getMarkdownTitle($filePath) ?? '(No Title)';
        $results[] = ['filePath' => $relativePath, 'title' => $title, 'rank' => $rank];
    }
}

// Sort results by rank in descending order
usort($results, function ($a, $b) {
    return $b['rank'] <=> $a['rank'];
});

// Return a newline-separated list of paths and titles
header('Content-Type: text/plain');
foreach ($results as $result) {
    echo $result['filePath'] . " | " . $result['title'] . "\n";
}
?>
