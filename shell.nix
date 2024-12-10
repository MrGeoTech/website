with import <nixpkgs> {};

let
    # Directories for your project
    rootDir   = toString ./.;                  # Root directory where your PHP files are located
    configDir = toString ./config;             # Directory for Apache configuration and logs

    # Apache Configuration
    apacheConf = pkgs.writeText "httpd.conf" ''
        ServerName localhost
        ServerRoot "${configDir}"
        
        LoadModule mpm_event_module ${pkgs.apacheHttpd}/modules/mod_mpm_event.so
        LoadModule dir_module ${pkgs.apacheHttpd}/modules/mod_dir.so
        LoadModule log_config_module ${pkgs.apacheHttpd}/modules/mod_log_config.so
        LoadModule authz_core_module ${pkgs.apacheHttpd}/modules/mod_authz_core.so
        LoadModule unixd_module ${pkgs.apacheHttpd}/modules/mod_unixd.so
        LoadModule proxy_module ${pkgs.apacheHttpd}/modules/mod_proxy.so
        LoadModule proxy_fcgi_module ${pkgs.apacheHttpd}/modules/mod_proxy_fcgi.so
        
        Listen 8080
        DocumentRoot "${rootDir}"
        
        <Directory "${rootDir}">
            AllowOverride None
            Require all granted
        </Directory>
        
        DirectoryIndex index.php
        
        <FilesMatch \.php$>
            SetHandler "proxy:unix:${configDir}/php-fpm.sock|fcgi://localhost:9000/"
        </FilesMatch>
        
        ErrorLog "${configDir}/logs/error.log"
        CustomLog "${configDir}/logs/access.log" combined
    '';

    phpFpmConf = pkgs.writeText "php-fpm.conf" ''
        [global]
        pid = ${configDir}/php-fpm.pid
        error_log = ${configDir}/logs/php-fpm-error.log

        [www]
        listen = ${configDir}/php-fpm.sock
        listen.mode = 0660
        pm = dynamic
        pm.max_children = 5
        pm.start_servers = 2
        pm.min_spare_servers = 1
        pm.max_spare_servers = 3
        pm.process_idle_timeout = 10s
        pm.max_requests = 500
    '';
in stdenv.mkDerivation rec {
    name = "apache-php-test-env";
    version = "0.1.0";

    # Build dependencies
    buildInputs = [ pkgs.apacheHttpd pkgs.php pkgs.pandoc ];

    # Runtime configuration
    shellHook = ''
        mkdir -p ${configDir}/logs
        export PHP_FPM_CONF=${phpFpmConf}

        # Start PHP-FPM
        php-fpm --fpm-config ${phpFpmConf} --daemonize
    
        # Start Apache
        httpd -f ${apacheConf} -D FOREGROUND

        # Exit out of the shell when apache stops
    '';
}

