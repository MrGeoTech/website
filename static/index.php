<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Isaac George</title>
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Roboto:ital,wght@0,100;0,300;0,400;0,500;0,700;0,900;1,100;1,300;1,400;1,500;1,700;1,900&display=swap" rel="stylesheet">
    <link href="https://fonts.googleapis.com/css2?family=Roboto+Mono:ital,wght@0,100..700;1,100..700&family=Roboto:ital,wght@0,100;0,300;0,400;0,500;0,700;0,900;1,100;1,300;1,400;1,500;1,700;1,900&display=swap" rel="stylesheet">

    <link rel="stylesheet" href="catppuccin.css"/>
    <link rel="stylesheet" href="styles.css"/>

    <link rel="stylesheet" href="modules/render.css"/>
    <link rel="stylesheet" href="https://prismjs.catppuccin.com/mocha.css"/>
</head>
<body class="mocha">
    <div id="throbber" class="throbber"></div>

    <?php 
        require_once 'modules/header.php';
        renderHeader("docs"); 
    ?>

    <div class="content">
        <?php
        if (isset($_GET['section'])) {
            echo '<div id="collapsible">';
            require_once 'modules/sidebar.php';
            renderSidebar($_GET['section']);
            echo '<div class="tab">';
            echo '<div id="sidebar-tab"></div>';
            echo '<div class="negative"></div>';
            echo '</div>';
            echo '</div>';
        }
        ?>
        <main>
            <?php
            // Check if the 'file' query parameter is set
            if (isset($_GET['file'])) {
                // Get the file path from the query parameter
                $file = $_GET['file'];

                require_once 'modules/render.php';
            } else {
                // Fallback if no file is specified, show an index or default content
                require_once 'modules/get_index_file.php';
                echo getIndexFileContents($_GET);
            }
            ?>
        </main>
    </div>

    <!-- Theme Switcher -->
    <div class="theme-switcher">
        <label class="switch">
            <input type="checkbox" id="theme-toggle">
            <span class="slider">
                <span class="symbol light-symbol">☀️</span>
                <span class="symbol dark-symbol">🌙</span>
            </span>
        </label>
    </div>

    <script src="scripts.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/prismjs@1.29.0/prism.min.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/prismjs@v1.x/plugins/autoloader/prism-autoloader.min.js"></script>
</body>
</html>
