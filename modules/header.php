<?php
function renderHeader($docsDir = 'docs') {
?>
    <link rel="stylesheet" href="modules/header.css">
    <header class="site-header">
        <!-- Left side: Site Icon and Title -->
        <div class="header-left">
            <!-- Clicking the site icon or title goes to the homepage -->
            <a href="/" class="site-icon-link">
                <img src="icon.png" alt="Site Icon" class="site-icon">
            </a>
            <a href="/" class="site-title-link">
                <h1 class="site-title">Isaac<br>George</h1>
            </a>
        </div>

        <!-- Middle: Navigation Bar -->
        <nav class="header-middle">
            <ul class="nav-sections">
                <!-- Link to Home -->
                <li><a href="/" class="nav-home">Home</a></li>
<?php
$sections = array_filter(glob("$docsDir/*"), 'is_dir');
foreach ($sections as $section) {
    $sectionName = basename($section);
    echo "<li><a href='?section=" . urlencode($sectionName) . "'>" . htmlspecialchars($sectionName) . "</a></li>";
}
?>
            </ul>
        </nav>

        <!-- Right side: Search Bar -->
        <div class="header-right">
            <input type="text" class="search-bar" id="search" placeholder="Search...">
            <ul id="suggestions"></ul>
        </div>
    </header>
    <script>
    const searchInput = document.getElementById('search');
    const suggestionsList = document.getElementById('suggestions');

    // Get current section from the URL if available
    const urlParams = new URLSearchParams(window.location.search);
    const section = urlParams.get('section') || '';

    searchInput.addEventListener('input', async function () {
        const query = searchInput.value.trim();
        if (query.length === 0) {
            suggestionsList.innerHTML = '';
            return;
        }

        try {
            // Build the search query with the optional section parameter
            const searchUrl = `/modules/search.php?q=${encodeURIComponent(query)}${section ? `&section=${encodeURIComponent(section)}` : ''}`;
            const response = await fetch(searchUrl);
            const results = await response.text();

            // Parse and display suggestions
            suggestionsList.innerHTML = results.split('\n').filter(line => line).map(result => {
                const [filePath, title] = result.split('|').map(item => item.trim());

                // Extract section from the file path
                const fileUrlParts = filePath.split('/');
                const sectionName = fileUrlParts[2]; // Assuming section is the second directory

                return `
                    <li>
                        <a href="/?section=${encodeURIComponent(sectionName)}&file=${encodeURIComponent(filePath)}">${title || filePath}</a>
                    </li>
                `;
            }).join('');
        } catch (error) {
            console.error('Error fetching search results:', error);
        }
    });
    </script>
<?php
}
?>
