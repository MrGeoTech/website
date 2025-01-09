<?php
function renderSidebar($currentSection) {
    /**
     * Scans a directory and builds an array representing its structure.
     *
     * @param string $dir Directory to scan.
     * @return array Directory structure.
     */
    function scanDirectory($dir) {
        $items = scandir($dir);
        $results = [];

        foreach ($items as $item) {
            if ($item === '.' || $item === '..') continue;

            $fullPath = "$dir/$item";

            if (is_dir($fullPath)) {
                $subResults = scanDirectory($fullPath);
                if (!empty($subResults)) {
                    $results[$item] = $subResults;
                }
            } elseif (pathinfo($item, PATHINFO_EXTENSION) === 'md') {
                $results[] = $item;
            }
        }
        return $results;
    }

    /**
     * Extracts the title from a markdown file.
     *
     * @param string $filePath Path to the markdown file.
     * @return string|null Title of the file, or null if not found.
     */
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

/*
    function generateSidebarMenu($contents, $currentPath) {
        echo "<ul class='sidebar-list'>";
        foreach ($contents as $name => $value) {
            if (is_array($value)) {
                echo "<li class='directory'>
                        <span class='directory-name'>$name</span>
                        <div class='sub-list'>";
                generateSidebarMenu($value, "$currentPath/$name");
                echo "</div></li>";
            } else {
                $title = getMarkdownTitle("$currentPath/$value") ?? pathinfo($value, PATHINFO_FILENAME);
                echo "<li hx-get='/modules/render.php?file=" . urlencode($currentPath) . "/" . ltrim(urlencode($value), '/') . "' hx-trigger='click' hx-target='main'>$title</li>";
            }
        }
        echo "</ul>";
    }
*/
    /**
     * Recursively generates the sidebar menu.
     *
     * @param array $contents Directory structure.
     * @param string $currentPath Path to the current section.
     */
    function generateSidebarMenu($contents, $currentPath, $currentSection, $currentFile) {
        echo "<ul class='sidebar-list'>";
    
        foreach ($contents as $name => $value) {
            if (is_array($value)) {
                // For directories, display a collapsible structure
                echo "<li class='directory'>
                        <span class='directory-name'>$name</span>
                        <div class='sub-list'>";
                generateSidebarMenu($value, "$currentPath/$name", $currentSection, $currentFile);
                echo "</div></li>";
            } else {
                // For files, create a link with the current section and file path as URL parameters
                $fullFilePath = "$currentPath/$value";
                $title = getMarkdownTitle($fullFilePath) ?? pathinfo($value, PATHINFO_FILENAME);
                $encodedFilePath = urlencode($fullFilePath); // Encoding the file path for URL safety
                
                // Check if this is the current file and add the 'active' class
                $isActive = ($fullFilePath === $currentFile) ? "style='font-weight:bold;'" : "";
                echo "<li>
                        <a href='/?section=$currentSection&file=$encodedFilePath' class='sidebar-link' $isActive>$title</a>
                      </li>";
            }
        }
        echo "</ul>";
    }

    $currentPath = "docs/$currentSection";
    if (!is_dir($currentPath)) {
        return;
    }

    $contents = scanDirectory($currentPath);
    ?>
    <link rel="stylesheet" href="modules/sidebar.css">
    <aside class="sidebar">
        <h1>Directory</h1>
        <?php 
            $file = $_GET['file'] ?? '';
            generateSidebarMenu($contents, $currentPath, $currentSection, $file);
        ?>
        <div class='sidebar-padding'></div>
    </aside>

    <script>
        document.addEventListener("DOMContentLoaded", function () {
            const currentFileLink = document.querySelector(".sidebar-link[style*='font-weight:bold;']");
            if (currentFileLink) {
                let parent = currentFileLink.closest(".sub-list");
                while (parent) {
                    parent.classList.add("visible");
                    parent = parent.closest(".directory")?.closest(".sub-list");
                }
            }
        });
    
        // Handle toggling submenus when directory names are clicked
        document.querySelectorAll('.directory-name, .sub-directory-name').forEach(function (el) {
            el.addEventListener('click', function () {
                const submenu = this.nextElementSibling;
                if (submenu) {
                    submenu.classList.toggle('visible');
                }
            });
        });
    </script>
    <?php
}
?>
