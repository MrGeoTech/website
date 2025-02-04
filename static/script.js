const content = document.getElementById("content");
const terminal = document.getElementById("terminal");

const fetch_str = `
          __––___                    Name: Isaac George
       __/=======\\__                 Occupation: Student
      /=============\\                Organization: North Dakota State University
     {===============}               Age: 19
     {=/    ‾‾‾‾    \\}               Major: Computer Engineering
     ┌┤              ├┐              Interests: Programming, Server Administration,
     {|  <0>    <0>  |}                         VLSI, Computing History, Music
     {|      /       |}              Languages: C, Zig, Java/Kotlin, VHDL, Verilog
      {|     ¨       /               Github: https://github.com/MrGeoTech/
       \\_ \`~<≈≈>~\`  /\\               LinkedIn: https://www.linkedin.com/in/isaac-george-tech/
         \\_      __/ |\\__
        /|| \\___/  _/  | \\__
     /‾‾ | \\      /    /    ‾––_
_––‾‾    \\  ‾\\__/‾    /         ‾
`.replace("\n", "<br/>");
var current_content = fetch_str + `

Hint: Type "help" for all commands
`.replace("\n", "<br/>");
var current_input = "";
var current_path = "/";

document.addEventListener("DOMContentLoaded", () => {
    const logLines = [
        "Website kernel booting...",
        "[ OK ] CPU: Initializing processor...",
        "[ OK ] CPU: Detected 8 cores, enabling multi-threading...",
        "[ OK ] Memory: 16GB RAM detected, initializing...",
        "[ OK ] ACPI: Power management interface initialized.",
        "[ OK ] PCI: Scanning for devices...",
        "[ OK ] SATA: Initializing disk controllers...",
        "[ OK ] NVMe: SSD detected, mounting root filesystem...",
        "[ OK ] USB: Initializing controllers...",
        "[ OK ] USB: Device detected: Logitech Keyboard",
        "[ OK ] USB: Device detected: Logitech Mouse",
        "[ OK ] Network: Detecting available interfaces...",
        "[ OK ] Network: eth0 connected, IP address assigned.",
        "[ OK ] Audio: Initializing sound system...",
        "[ OK ] ALSA: Audio driver loaded successfully.",
        "[ OK ] GPU: Initializing graphics driver...",
        "[ OK ] GPU: VRAM detected, enabling acceleration...",
        "[ OK ] Filesystem: Checking disk integrity...",
        "[ OK ] Filesystem: No errors found.",
        "[ OK ] Security: Enabling AppArmor...",
        "[ OK ] Systemd: Initializing system services...",
        "[ OK ] SSH: Secure shell service starting...",
        "[ OK ] HTTP: Web server detected, binding to port 80...",
        "[ OK ] CRON: Scheduled tasks loaded.",
        "[ OK ] System Time: Synchronizing with NTP server...",
        "[ OK ] Swap: Enabling virtual memory...",
        "[ OK ] User Login: Waiting for authentication...",
        "Boot complete. <span style='font-weight: bold'>Welcome to my website!</span>"
    ];

    let index = 0;
    
    function addLine() {
        if (index < logLines.length) {
            const p = document.createElement("p");
            p.innerHTML = logLines[index];
            content.appendChild(p);

            index++;
            let delay = index === 1 ? 500 : Math.exp(Math.random() * 7) / 100;
            setTimeout(addLine, delay);
        } else {
            setTimeout(updateContent, 750);
        }
    }

    addLine();
});

function updateContent() {
    const html_content = current_content;
    content.innerHTML = "<p>" + html_content + "</p>"
    showCursor();
    terminal.scrollTop = terminal.scrollHeight;
}

function showCursor() {
    const html = `
        <p>${current_path} $ ${current_input}<span id="cursor"></span></p>
    `;
    content.innerHTML += html;
}

document.addEventListener("keydown", (event) => {
    if (event.key.length == 1) {
        current_input += event.key;
    } else if (event.key == "Backspace") {
        current_input = current_input.slice(0, -1);
    } else if (event.key == "Enter") {
        processCommand();
    }
    //updateSuggestion();
    updateContent();
});

function processCommand() {
    // Add current command to content
    current_content += "<p>" + current_path + " $ " + current_input + "</p>";

    // Execute command
    const split = current_input.trim().match(/\b\w+\b/g);
    if (split.length < 1) return;

    switch (split[0]) {
        case "help":
            if (split.length == 1) {
                current_content += "<p>" + help_page + "</p>";
            } else {
                if (split[1] == "help")
                    current_content += "<p>" + help_page_help + "</p>";
                else if (split[1] == "cd")
                    current_content += "<p>" + help_page_cd + "</p>";
                else if (split[1] == "ls")
                    current_content += "<p>" + help_page_ls + "</p>";
                else if (split[1] == "vi")
                    current_content += "<p>" + help_page_vi + "</p>";
                else
                    current_content += "<p>Help page for " + 
                        split[1] + 
                        " does not exist! Try either \"help\", \"cd\", \"ls\", or \"vi\".</p>";
            }
            break;
        case "clear":
            current_content = "";
            break;
        case "fetch":
            current_content += "<p>" + fetch_str + "</p>";
            break;
        case "cd":
            if (split.length < 2) break;

            try {
                const response = await fetch(
                    "/cd?path=" + encodeURIComponent(current_location + current_input), 
                    {
                        method: "GET",
                        headers: { "Content-Type": "text/plain" }
                    }
                );

                if (response.ok)
                    current_location = await response.body;
                else
                    current_content += "<p>" + await response.body + "</p>";
            } catch (error) {
                console.error("Error:", error);
                current_content += "<p>An error occured while trying to execute '" + current_input + "'!</p>";
            }
            break;
        case "ls":
            const location = (split.length < 2) ? "." else split[1];

            try {
                const response = await fetch(
                    "/ls?path=" + 
                        encodeURIComponent(current_location) + 
                        "&location=" + 
                        encodeURIComponent(location), 
                    {
                        method: "GET",
                        headers: { "Content-Type": "text/plain" }
                    }
                );

                if (response.ok)
                    current_location = await response.body;
                else
                    current_content += "<p>" + await response.body + "</p>";
            } catch (error) {
                console.error("Error:", error);
                current_content += "<p>An error occured while trying to execute '" + current_input + "'!</p>";
            }
            break;
        case "vi":
            break;
        default:
            current_content += "<p>" + current_input + ": command not found</p>";
    }
    
    current_input = "";
}

const help_page = `
Available commands:
- help           : Shows all available commands
- help [command] : Shows the command's manual page (includes examples)
- clear          : Clears the terminal history
- fetch          : Shows the information shown on a website refresh
- cd [directory] : Changes the current location to the specified directory (folder)
- ls             : Lists all files and directories in the current directory
- vi [file]      : Opens a file to be read (read-only)
`.replace("\n", "<br/>");

const help_page_help = `
DESCRIPTION
        help - a command to instruct how to use other commands

USAGES
        help
        help [command]

EXAMPLES
        If you are unfamiliar with navigating on a command line, you
        might want to open up the help page for the "cd" command.
        
        To do so, simply enter "help cd" to view the "cd" commands help page.
`.replace("\n", "<br/>");

const help_page_clear = `
DESCRIPTION
        clear - clear the terminal screen

USAGES
        clear
`;

const help_page_fetch = `
DESCRIPTION
        fetch - displays an ascii art image of myself and information about myself

USAGES
        fetch
`;

const help_page_cd = `
DESCRIPTION
        cd - change the working directory

USAGES
        cd [directory]

EXAMPLES
        Assume you are at the location "/dir1" but you want to go into the
        directory "/dir2/subdir/". To do this, simply use the command
        "cd ../dir2/subdir".

        There are two special directories, "." and "..", which reference
        the current directory and the parent directory respectively.
`.replace("\n", "<br/>");

const help_page_ls = `
DESCRIPTION
        ls - list directory contents

USAGE
        ls
        ls [directory]

EXAMPLES
        To find a subdirectory or file, you can simply use the "ls" command.
        To find a subdirectory or file in another directory, use the
        "ls [directory]" command.
`.replace("\n", "<br/>");

const help_page_vi = `
DESCRIPTION
        vi - opens a file for viewing

USAGE
        vi [file]

EXAMPLES
        To view the file "file.txt", you can use "vi file.txt".

        Note: Unlike true vi, this is a read-only version that will open
        files in a formatted way.
`.replace("\n", "<br/>");
