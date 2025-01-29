<?php
// Load a markdown parser (e.g., Parsedown)
require_once __DIR__ . '/Parsedown.php';

function validateFile($filePath, $baseDir) {
    // Ensure the file is within the allowed base directory
    $realBaseDir = realpath($baseDir);
    $realFilePath = realpath($filePath);

    if (!$realFilePath || strpos($realFilePath, $realBaseDir) !== 0) {
        return false; // Invalid file path
    }

    return is_file($realFilePath) && pathinfo($realFilePath, PATHINFO_EXTENSION) === 'md';
}

function parseMetaTags($filePath) {
    $file = fopen($filePath, 'r');
    $metadata = [];
    $inMeta = false;

    if ($file) {
        while (($line = fgets($file)) !== false) {
            $line = trim($line);
            if ($line === '---') {
                $inMeta = !$inMeta;
                if (!$inMeta) break; // End of meta block
            } elseif ($inMeta) {
                $parts = explode(':', $line, 2);
                if (count($parts) == 2) {
                    $key = trim($parts[0]);
                    $value = trim($parts[1]);
                    $metadata[$key] = $value;
                }
            }
        }
        fclose($file);
    }

    return $metadata;
}

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

function updateRelativeLinksInHtml($html, $basePath) {
    // Create a DOMDocument instance
    $dom = new DOMDocument();

    // Suppress errors due to malformed HTML during load
    libxml_use_internal_errors(true);
    $dom->loadHTML($html, LIBXML_HTML_NOIMPLIED | LIBXML_HTML_NODEFDTD);
    libxml_clear_errors();

    // Update <img> tags
    foreach ($dom->getElementsByTagName('img') as $img) {
        $src = $img->getAttribute('src');
        if (!preg_match('#^(https?:)?//#', $src) && strpos($src, '/') !== 0) {
            // If src is relative, prepend the base path
            $img->setAttribute('src', $basePath . '/' . ltrim($src, '/'));
        }
    }

    // Update <a> tags
    foreach ($dom->getElementsByTagName('a') as $a) {
        $href = $a->getAttribute('href');
        if (!preg_match('#^(https?:)?//#', $href) && strpos($href, '/') !== 0) {
            // If href is relative, prepend the base path
            $a->setAttribute('href', $basePath . '/' . ltrim($href, '/'));
        }
    }

    // Return the updated HTML
    return $dom->saveHTML();
}

function generateDownloadButton($filePath) {
    // Sanitize the file path to prevent directory traversal
    $fileName = basename($filePath);
    $encodedFile = urlencode($filePath); // For safe usage in URLs

    // Define the monochrome floppy disk SVG
    $floppyDiskSVG = <<<SVG
<svg height="1.25rem" width="1.25rem" version="1.1" id="Capa_1" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 288.27 288.27" xml:space="preserve">
<g>
	<path style="fill:var(--text);" d="M23.051,288.27H265.22c12.015,0,21.756-9.741,21.756-21.756V21.756   C286.976,9.741,277.235,0,265.22,0h-37.796v83.724H55.669V0H23.051C11.036,0,1.294,9.741,1.294,21.756v244.758   C1.294,278.529,11.036,288.27,23.051,288.27z M49.196,152.511c0-12.015,9.741-21.756,21.756-21.756h147.23   c12.015,0,21.756,9.741,21.756,21.756v86.813c0,12.015-9.741,21.756-21.756,21.756H70.953c-12.015,0-21.756-9.741-21.756-21.756   V152.511z"/>
	<path style="fill:var(--text);" d="M95.646,234.086h97.838c10.122,0,18.324-8.202,18.324-18.324v-39.678   c0-10.122-8.202-18.324-18.324-18.324H95.646c-10.122,0-18.324,8.202-18.324,18.324v39.678   C77.322,225.884,85.524,234.086,95.646,234.086z"/>
	<path style="fill:var(--text);" d="M162.264,21.756v24.476c0,12.015,8.523,21.756,19.037,21.756s19.037-9.741,19.037-21.756V21.756   C200.337,9.741,191.814,0,181.3,0S162.264,9.741,162.264,21.756z"/>
</g>
</svg>
SVG;

    // Return the HTML for the download button
    return <<<HTML
<div id="download-container">
    <button id="download-button">{$floppyDiskSVG}</button>
    <div id="download-options">
        <ul>
            <li><a href="/modules/download.php?file={$encodedFile}&format=pdf" title="Download as PDF">PDF</a></li>
            <li><a href="/modules/download.php?file={$encodedFile}&format=markdown" title="Download as Markdown">MD</a></li>
            <li><a href="/modules/download.php?file={$encodedFile}&format=html" title="Download as HTML">HTML</a></li>
        </ul>
    </div>
</div>
<script>
    document.getElementById('download-button').addEventListener('click', function() {
        const options = document.getElementById('download-options');
        options.style.display = options.style.display === 'none' ? 'block' : 'none';
    });
    document.addEventListener('click', function(event) {
        const container = document.getElementById('download-container');
        if (!container.contains(event.target)) {
            document.getElementById('download-options').style.display = 'none';
        }
    });
</script>
HTML;
}

$file = $_POST['file'] ?? $_GET['file'] ?? '';

function renderFile($file) {
    // Base directory for markdown files
    $baseDir = realpath(__DIR__ . '/..');
    
    // Get the requested file from the query string
    $filePath = $baseDir . '/' . ltrim($file, '/');

    // Validate the file path
    if (!validateFile($filePath, $baseDir)) {
        http_response_code(400);
        echo "<p class='error'>Error: Invalid file path.</p>";
        exit;
    }
    
    // Parse metadata
    $metadata = parseMetaTags($filePath);
    
    // Check if the file has password protection
    if (isset($metadata['password'])) {
        // Get the password from the metadata
        $password = $metadata['password'];
    
        // Validate the password if it's provided
        if (!empty($_POST['password'])) {
            // Check if the provided password matches the one in the metadata
            if (!hash_equals($password, $_POST['password'])) {
                // Password is incorrect, show the password form again
                echo "
                <h1>Enter Password:</h1>
                <p>This file is password protected. If you are a professor/grader, the password should be submitted on Blackboard.</p>
                <p style='color:var(--red);'>Incorrect password. Please try again.</p>
                <form method='post' hx-post='/modules/render.php' hx-target='main' hx-swap='innerHTML'>
                    <input type='hidden' name='file' value='" . htmlspecialchars($file) . "'>
                    <input type='password' id='password' name='password' placeholder='Enter password' required>
                    <button type='submit' id='password-submit'>Submit</button>
                </form>";
                exit;
            }
            // Password is correct, continue with rendering the markdown content
            // Render your markdown content here after validation
        } else {
            // No password provided yet, show the password form
            echo "
            <h1>Enter Password:</h1>
            <p>This file is password protected. If you are a professor/grader, the password should be submitted on Blackboard.</p>
            <form method='post' hx-post='/modules/render.php' hx-target='main' hx-swap='innerHTML'>
                <input type='hidden' name='file' value='" . htmlspecialchars($file) . "'>
                <input type='password' id='password' name='password' placeholder='Enter password' required>
                <button type='submit' id='password-submit'>Submit</button>
            </form>";
            exit;
        }
    }
    
    // Render markdown as HTML
    $parsedown = new Parsedown();
    $content = removeMetaTags($filePath);
    
    // Convert Markdown to HTML
    $htmlContent = $parsedown->text($content);
    
    // Determine base path from file location
    $basePath = '/' . rtrim(dirname($file), '/');
    
    // Post-process the rendered HTML
    $updatedHtmlContent = updateRelativeLinksInHtml($htmlContent, $basePath);
    
    // Add MathJax script to render the math
    $mathjaxScript = <<<EOD
    <script type="text/javascript">
    window.MathJax = {
        loader: {load: ['input/tex', 'output/chtml']},
        tex: {
            inlineMath: [['$', '$']],
            displayMath: [['$$', '$$']],
            tags: 'none',
            maxMacros: 1000
        },
        chtml: {
            scale: 1,
            mtextInheritFont: true,
            merrorInheritFont: true,
            linebreaks: {automatic: true}
        }
    };
    </script>
    <script type="text/javascript" id="MathJax-script" async
        src="https://cdn.jsdelivr.net/npm/mathjax@3.0.0/es5/tex-svg.js">
    </script>
    EOD;
    
    // Combine HTML and MathJax
    $finalHtml = $updatedHtmlContent . $mathjaxScript;
    
    echo $finalHtml . generateDownloadButton($filePath);
}

renderFile($file);
?>
