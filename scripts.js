// Apply the saved theme on page load
document.addEventListener("DOMContentLoaded", () => {
    const savedTheme = localStorage.getItem("theme") || "mocha";
    const body = document.body;
    body.classList.remove("mocha", "latte"); // Clear existing theme classes
    body.classList.add(savedTheme); // Apply saved theme
    const themeToggle = document.getElementById("theme-toggle");
    if (themeToggle) {
        themeToggle.checked = savedTheme === "mocha";
    }
});

// Update the theme and save the preference
document.getElementById("theme-toggle").addEventListener("change", function () {
    const newTheme = this.checked ? "mocha" : "latte";
    const body = document.body;
    body.classList.remove("mocha", "latte"); // Clear existing theme classes
    body.classList.add(newTheme); // Apply the new theme
    localStorage.setItem("theme", newTheme);
});

const collapsible = document.getElementById('collapsible');
const tab = document.getElementById('sidebar-tab');

if (collapsible.classList.contains('collapsed')) {
    tab.innerHTML = '→'; // Open arrow
} else {
    tab.innerHTML = '←'; // Close arrow
}

document.getElementById('sidebar-tab').addEventListener('click', function () {
    // Toggle the 'collapsed' class on the sidebar
    collapsible.classList.toggle('collapsed');

    // Update the tab content based on the sidebar's state
    if (collapsible.classList.contains('collapsed')) {
        tab.innerHTML = '→'; // Open arrow
    } else {
        tab.innerHTML = '←'; // Close arrow
    }
});

// Enable throbbers when loading content
document.body.addEventListener('htmx:beforeRequest', function() {
    document.getElementById('throbber').style.display = 'block';
});

document.body.addEventListener('htmx:afterRequest', function() {
    document.getElementById('throbber').style.display = 'none';
});
