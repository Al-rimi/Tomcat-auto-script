# This PowerShell script automates the lifecycle of building, deploying, and managing a jsp web application on Apache Tomcat.
# It is designed to streamline the development workflow by combining several critical tasks into a single automated process.
# 
# Prerequisites:
# - Ensure that JDK is installed and the JAVA_HOME environment variable is correctly set.
# - Apache Tomcat must be installed, with the CATALINA_HOME environment variable configured.
# - Maven must be installed and added to the system's PATH.
# - Google Chrome is required for automatic application opening and refreshing.
# 
# Features:
# 1. Validates environment variables for Java and Tomcat, ensuring proper configurations.
# 2. Compiles the project using Maven to generate a deployable WAR file.
# 3. Automatically deploys the generated WAR file to the Tomcat webapps directory.
# 4. Manages Tomcat's lifecycle by starting or stopping the service as needed.
# 5. Reloads the application without requiring a full server restart if Tomcat is already running.
# 6. Launches or refreshes the application in Google Chrome, providing a seamless user experience.
# 
# Author: Al-rimi
# Version: 1.0

function INFO {
    Write-Host "[" -NoNewline
    Write-Host "INFO" -ForegroundColor Blue -NoNewline
    Write-Host "] $args"
}

function Tomcat {
    param (
        [ValidateSet("start", "stop")] # Restrict to only "start" or "stop"
        [string]$Action
    )

    $javaExecutable = "$env:JAVA_HOME\bin\java.exe"

    if (-not (Test-Path $javaExecutable)) {
        Write-Host "[ERROR] JAVA_HOME is not set correctly. Exiting." -ForegroundColor Red
        exit 1
    }

    $classpath = "$TOMCAT_HOME\bin\bootstrap.jar;$TOMCAT_HOME\bin\tomcat-juli.jar"
    $mainClass = "org.apache.catalina.startup.Bootstrap"
    $catalinaOpts = "-Dcatalina.base=$TOMCAT_HOME -Dcatalina.home=$TOMCAT_HOME -Djava.io.tmpdir=$TOMCAT_HOME\temp"

    $logOut = "$TOMCAT_HOME\logs\catalina.out"
    $logErr = "$TOMCAT_HOME\logs\catalina.err"

    Start-Process -FilePath $javaExecutable `
        -ArgumentList "-cp", $classpath, $catalinaOpts, $mainClass, $Action `
        -NoNewWindow `
        -RedirectStandardOutput $logOut `
        -RedirectStandardError $logErr `
        -Wait

    if ($Action -eq "start") {
        INFO "Tomcat started successfully"
    }
    elseif ($Action -eq "stop") {
        INFO "Tomcat stopped successfully"
    }
}

$TOMCAT_HOME = [System.Environment]::GetEnvironmentVariable("CATALINA_HOME", "Machine")

$tomcatRunning = Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like "*catalina*" }

if (-not $TOMCAT_HOME) {
    Write-Host "[ERROR] CATALINA_HOME environment variable is not set. Exiting." -ForegroundColor Red
    if ($tomcatRunning) {
        Tomcat -Action stop
    } else {
        INFO "Tomcat is not running"
    }
    exit 1
}

$PROJECT_DIR = Get-Location
if (-not (Test-Path "$PROJECT_DIR\pom.xml")) {
    exit 1
}

$javaExecutable = "$env:JAVA_HOME\bin\java.exe"

if (-not (Test-Path $javaExecutable)) {
    Write-Host "[ERROR] JAVA_HOME is not set correctly. Exiting." -ForegroundColor Red
    exit 1
}

$process = Start-Process -FilePath "mvn" -ArgumentList "clean package" -PassThru -Wait -NoNewWindow

if ($process.ExitCode -ne 0) {
    Write-Host "[ERROR] Maven build failed. Exiting." -ForegroundColor Red | Out-Null
    if ($tomcatRunning) {
        Tomcat -Action stop
    } else {
        INFO "Tomcat is not running"
    }
    exit 1
}

$WAR_FILE = Get-ChildItem -Path "$PROJECT_DIR\target" -Filter "*.war" | Select-Object -First 1 -ExpandProperty FullName
$APP_NAME = [System.IO.Path]::GetFileNameWithoutExtension($WAR_FILE)

if (-not $WAR_FILE) {
    Write-Host "$ERROR No WAR file found. Closing Tomcat..." -ForegroundColor Red
    if ($tomcatRunning) {
        Tomcat -Action stop
    } else {
        INFO "Tomcat is not running"
    }
    exit 1
}

INFO "WAR file found: $APP_NAME.war"

if (Test-Path "$TOMCAT_HOME\webapps\$APP_NAME") {
    Remove-Item -Path "$TOMCAT_HOME\webapps\$APP_NAME" -Recurse -Force -ErrorAction SilentlyContinue
}

if (Test-Path "$TOMCAT_HOME\webapps\$APP_NAME.war") {
    Remove-Item -Path "$TOMCAT_HOME\webapps\$APP_NAME.war" -Force -ErrorAction SilentlyContinue
    INFO "Old WAR deployment removed"
}

Copy-Item -Path $WAR_FILE -Destination "$TOMCAT_HOME\webapps\"
INFO "New WAR file deployed"

if ($tomcatRunning) {
    $creds = New-Object System.Management.Automation.PSCredential("admin", (ConvertTo-SecureString "admin" -AsPlainText -Force))
    Invoke-WebRequest -Uri "http://localhost:8080/manager/text/reload?path=/$APP_NAME" -Method Get -Credential $creds | Out-Null
    INFO "Tomcat reloaded"
}  else {
    Tomcat -Action start
}

Write-Host "[" -NoNewline
Write-Host "DONE" -ForegroundColor Green -NoNewline
Write-Host "] Access your application at: " -NoNewline
Write-Host "http://localhost:8080/$APP_NAME" -ForegroundColor Cyan

$chromeProcesses = Get-Process -Name "chrome" -ErrorAction SilentlyContinue

if ($chromeProcesses) {
    $chromeOpened = $false
    foreach ($process in $chromeProcesses) {
        $chromeTitle = $process.MainWindowTitle
        if ($chromeTitle -like "*$APP_NAME*") {
            $chromeOpened = $true
            [System.Windows.Forms.SendKeys]::SendWait("^{F5}") # Ctrl+F5 for hard refresh
            INFO "Google Chrome reloaded"
            break
        }
    }

    if (-not $chromeOpened) {
        INFO "Opening Google Chrome"
        Start-Process "chrome" "http://localhost:8080/$APP_NAME"
    }
} else {
    INFO "Opening Google Chrome"
    Start-Process "chrome" "http://localhost:8080/$APP_NAME"
}