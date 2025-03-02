<#
.SYNOPSIS
    Automates the lifecycle of building, deploying, and managing a JSP web application on Apache Tomcat.

.DESCRIPTION
    This PowerShell script streamlines the development workflow by performing the following tasks:
    - Validates environment variables for JDK and Tomcat.
    - Builds the project using Maven to generate a WAR file.
    - Deploys the WAR file to the Tomcat `webapps` directory.
    - Starts or stops the Tomcat server.
    - Reloads the web application without restarting Tomcat.
    - Automatically opens or refreshes the application in Google Chrome.

.PARAMETER action
    Specifies the operation to perform. Acceptable values:
    - start    : Starts the Tomcat server.
    - stop     : Stops the Tomcat server.
    - deploy   : Deploys the WAR file to Tomcat.
    - clean    : Cleans previous deployments.
    - auto     : Automates the entire build, deploy, and reload process.
    - help     : Displays this help message.

.EXAMPLE
    .\deploy-webapp.ps1 auto
    Automates the entire lifecycle: builds, deploys, reloads, and opens the application in Google Chrome.

.EXAMPLE
    .\deploy-webapp.ps1 start
    Starts the Tomcat server.

.EXAMPLE
    .\deploy-webapp.ps1 stop
    Stops the Tomcat server.

.NOTES
    Author: Al-rimi
    Version: 1.1
    Requirements:
    - JDK installed and `JAVA_HOME` set.
    - Apache Tomcat installed and `CATALINA_HOME` set.
    - Maven installed and available in `PATH`.
    - Google Chrome installed for browser automation.

#>

param (
    [Parameter(Mandatory=$false)]
    [ValidateSet("start", "stop", "deploy", "clean", "auto", "help")]
    [string]$action
)

$javaExecutable = "$env:JAVA_HOME\bin\java.exe"

if (-not (Test-Path $javaExecutable)) {
    Write-Host "[ERROR] JAVA_HOME is not set correctly. Exiting." -ForegroundColor Red
    exit 1
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

function INFO {
    Write-Host "[" -NoNewline
    Write-Host "INFO" -ForegroundColor Blue -NoNewline
    Write-Host "] $args"
}

function Tomcat {
    param (
        [ValidateSet("start", "stop")]
        [string]$Action
    )

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

    if ($Action -eq "start") {
        INFO "Tomcat started successfully"
    }
    elseif ($Action -eq "stop") {
        INFO "Tomcat stopped successfully"
    }
}

function War {
    param (
        [ValidateSet("remove", "deploy")]
        [string]$Action
    )

    $PROJECT_DIR = Get-Location
    if (-not (Test-Path "$PROJECT_DIR\pom.xml")) {
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
    } else {
        INFO "No previous deployment found"
    }
    
    if (Test-Path "$TOMCAT_HOME\webapps\$APP_NAME.war") {
        Remove-Item -Path "$TOMCAT_HOME\webapps\$APP_NAME.war" -Force -ErrorAction SilentlyContinue
        INFO "Old WAR deployment removed"
    } else {
        INFO "No previous WAR deployment found"
    }
    
    if ($Action -eq "deploy") {
        Copy-Item -Path $WAR_FILE -Destination "$TOMCAT_HOME\webapps\"
        INFO "New WAR file deployed"    
    }
}

function Mvn {
    param (
        [ValidateSet("package")]
        [string]$clean
    )
    $PROJECT_DIR = Get-Location
    if (-not (Test-Path "$PROJECT_DIR\pom.xml")) {
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
}

switch ($action) {
    "stop" {
        INFO "Stopping Tomcat"
        if ($tomcatRunning) {
            Tomcat -Action stop
        }  else {
            INFO "Tomcat is not running"
        }   
        break
    }
    "clean" {
        INFO "Cleaning Tomcat"
        War -Action remove
        break
    }
    "start" {
        INFO "Starting Tomcat"
        if ($tomcatRunning) {
            INFO "Tomcat is already running"
        }  else {
            Tomcat -Action start
        }           
        break
    }
    "deploy" {
        INFO "Deploying the application to Tomcat"
        War -Action deploy
        break
    }
    "auto" {
        INFO "Automating the deployment process"
        Mvn -clean package
        War -Action deploy

        $PROJECT_DIR = Get-Location
        if (-not (Test-Path "$PROJECT_DIR\pom.xml")) {
            exit 1
        }

        $WAR_FILE = Get-ChildItem -Path "$PROJECT_DIR\target" -Filter "*.war" | Select-Object -First 1 -ExpandProperty FullName
        $APP_NAME = [System.IO.Path]::GetFileNameWithoutExtension($WAR_FILE)
        
        if ($tomcatRunning) {
        INFO "Tomcat is already running, reloading"
        $creds = New-Object System.Management.Automation.PSCredential("admin", (ConvertTo-SecureString "admin" -AsPlainText -Force))
        Invoke-WebRequest -Uri "http://localhost:8080/manager/text/reload?path=/$APP_NAME" -Method Get -Credential $creds -AllowUnencryptedAuthentication | Out-Null        
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
        break
    }
"help" {
    $ScriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
    Write-Host @"
=============================================================
                 $ScriptName - Deployment Script Help
=============================================================
Usage:
    $ScriptName <action>

Actions:
    stop      - Gracefully stops the Tomcat service if running.
                Ensures no abrupt service termination.

    clean     - Cleans the Tomcat deployment directory.
                Removes temporary files and cached data to ensure a fresh deployment.

    start     - Starts the Tomcat service.
                Ensures the service is up and running after cleaning or deploying.

    deploy    - Deploys the latest application version to the Tomcat server.
                Copies necessary files and prepares the environment.

    auto      - Automates the entire deployment process.
                Stops the service, cleans the deployment directory, deploys the application, and restarts the service automatically.

    help      - Displays this help message with detailed descriptions.

=============================================================
Examples:
    $ScriptName auto   # Automates the deployment process
    $ScriptName clean  # Cleans the Tomcat deployment
    $ScriptName help   # Shows this help message
=============================================================
"@
        break
    }
    default {
        Write-Host "[ERROR] Invalid action. Use 'help' to see available actions." -ForegroundColor Red
        exit 1
    }          
}
