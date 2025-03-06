<#
    Author: Al-rimi
    Version: 2.1.0
    Requirements:
    - JDK installed and `JAVA_HOME` set.
    - Apache Tomcat installed and `CATALINA_HOME` set.
    - Maven installed and available in `PATH`.
    - Google Chrome installed for browser automation.
#>

param (
    [ValidateSet("start", "stop", "clean", "deploy", "help")]
    [string]$Action,

    [ValidateSet("dev", "mvn")]
    [string]$SubAction
)

function HELP {
    $ScriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
    Write-Host @"
=============================================================
             $ScriptName - Deployment Script Help
=============================================================
Usage:
$ScriptName <action> [<subaction>]

Actions:
stop      - Gracefully stops the Tomcat service if running.
            Ensures no abrupt service termination.

clean     - Cleans the Tomcat deployment directory.
            Removes temporary files and cached data to ensure a fresh deployment.

start     - Starts the Tomcat service.
            Ensures the service is up and running after cleaning or deploying.

deploy    - Deploys the latest application version to the Tomcat server.
            Copies necessary files and prepares the environment.
            Requires a subaction:
              dev - Copies files directly from the development folder.
              mvn - Builds the project with Maven and deploys the generated WAR file.

help      - Displays this help message with detailed descriptions.

=============================================================
Examples:
$ScriptName stop        # Gracefully stops Tomcat service
$ScriptName clean       # Cleans the Tomcat deployment
$ScriptName deploy dev  # Deploys the application using development folder
$ScriptName deploy mvn  # Deploys the application using Maven build
$ScriptName help        # Shows this help message
=============================================================
"@
}

function INFO {
    Write-Host "[" -NoNewline
    Write-Host "INFO" -ForegroundColor Blue -NoNewline
    Write-Host "] $args"
}

function ERRORLOG {
    Write-Host "[" -NoNewline
    Write-Host "ERROR" -ForegroundColor Red -NoNewline
    Write-Host "] $args"
}

function DONE {
    Write-Host "[" -NoNewline
    Write-Host "DONE" -ForegroundColor Green -NoNewline
    Write-Host "] $args" -NoNewline
}

$TOMCAT_HOME = [System.Environment]::GetEnvironmentVariable("CATALINA_HOME", "Machine")

if (-not $TOMCAT_HOME) {
    ERRORLOG "CATALINA_HOME environment variable is not set. Exiting."
    exit 1
}

$PROJECT_DIR = Get-Location
$APP_NAME = (Get-Item $PROJECT_DIR).Name
$TARGET_DIR = "$TOMCAT_HOME\webapps\$APP_NAME"

function cleanOldDeployments {
    if (Test-Path "$TOMCAT_HOME\webapps\$APP_NAME.war") {
        Remove-Item -Path "$TOMCAT_HOME\webapps\$APP_NAME.war" -Force -ErrorAction SilentlyContinue
        INFO "Old WAR deployment removed"
    }
    if (Test-Path "$TOMCAT_HOME\webapps\$APP_NAME") {
        Remove-Item -Path "$TOMCAT_HOME\webapps\$APP_NAME" -Recurse -Force -ErrorAction SilentlyContinue
    } else {
        INFO "No previous deployment found"
    }
}

function tomcat {
    param (
        [ValidateSet("start", "stop", "reload")]
        [string]$Action
    )

    $javaExecutable = "$env:JAVA_HOME\bin\java.exe"
    if (-not (Test-Path $javaExecutable)) {
        ERRORLOG "JAVA_HOME is not set correctly. Exiting."
        exit 1
    }

    $tomcatRunning = (netstat -ano | Select-String "0.0.0.0:8080").Count -gt 0

    if ($tomcatRunning) {
        if ($Action -eq "start") {
            INFO "Tomcat is already running"
            return
        } 
        if ($Action -eq "reload") {
            $creds = New-Object System.Management.Automation.PSCredential("admin", (ConvertTo-SecureString "admin" -AsPlainText -Force))
            Invoke-WebRequest -Uri "http://localhost:8080/manager/text/reload?path=/$APP_NAME" -Method Get -Credential $creds | Out-Null        
            INFO "Tomcat reloaded"
            return
        }
    } else {
        if ($Action -eq "stop") {
            INFO "Tomcat is not running"
            return
        }
        if ($Action -eq "reload") {
            INFO "Tomcat is not running"
            $Action = "start"
        }
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
        -RedirectStandardERROR $logErr `

    if ($Action -eq "start") {
        INFO "Tomcat started successfully"
    }
    elseif ($Action -eq "stop") {
        INFO "Tomcat stopped successfully"
    }
}

function deploy{
    param (
        [ValidateSet("dev", "mvn")]
        [string]$Type
    )

    cleanOldDeployments
    
    if ($Type -eq "dev") {
        if (-not (Test-Path "$PROJECT_DIR\src\main\webapp")) {
            ERRORLOG "Project structure not found."
            exit 1
        }
    
        New-Item -ItemType Directory -Path $TARGET_DIR | Out-Null
        New-Item -ItemType Directory -Path "$TARGET_DIR\WEB-INF\classes" | Out-Null
    
        INFO "Copying JSP and static files..."
        Copy-Item "$PROJECT_DIR\src\main\webapp\*" -Destination $TARGET_DIR -Recurse -Force
    
        if (Test-Path "$PROJECT_DIR\WEB-INF\classes") {
            INFO "Copying compiled classes..."
            Copy-Item "$PROJECT_DIR\WEB-INF\classes\*" -Destination "$TARGET_DIR\WEB-INF\classes" -Recurse -Force
        }
    
        INFO "Deployment completed successfully."
    } elseif ($Type -eq "mvn") {
        if (-not (Test-Path "$PROJECT_DIR\pom.xml")) {
            exit 1
        }
        
        $process = Start-Process -FilePath "mvn" -ArgumentList "clean package" -PassThru -Wait -NoNewWindow
        
        if ($process.ExitCode -ne 0) {
            ERRORLOG "Maven build failed. Exiting."
            if ($tomcatRunning) {
                Tomcat -Action stop
            } else {
                INFO "Tomcat is not running"
            }
            exit 1
        }

        $WAR_FILE = Get-ChildItem -Path "$PROJECT_DIR\target" -Filter "*.war" | Select-Object -First 1 -ExpandProperty FullName
        Copy-Item -Path $WAR_FILE -Destination "$TOMCAT_HOME\webapps\"
    }

    tomcat -Action reload
    runBrowser

    DONE "Access your application at: "
    Write-Host "http://localhost:8080/$APP_NAME" -ForegroundColor Cyan   
}

function runBrowser {
    $appUrl = "http://localhost:8080/$APP_NAME/"
    $debugUrl = "http://localhost:9222/json"
    
    try {
        $sessions = Invoke-RestMethod -Uri $debugUrl -Method Get
        $target = $sessions | Where-Object { $_.url -like "*$appUrl*" } | Select-Object -First 1

        if ($target) {
            $wsUrl = $target.webSocketDebuggerUrl

            if ($wsUrl) {
                
                $webSocket = New-Object System.Net.WebSockets.ClientWebSocket
                $uri = New-Object Uri($wsUrl)

                $connectTask = $webSocket.ConnectAsync($uri, [System.Threading.CancellationToken]::None)
                $connectTask.Wait()

                if ($webSocket.State -eq [System.Net.WebSockets.WebSocketState]::Open) {                    
                    $reloadCommand = @{
                        id     = 1
                        method = "Page.reload"
                        params = @{}
                    } | ConvertTo-Json -Compress
                    $sendTask = $webSocket.SendAsync([System.Text.Encoding]::UTF8.GetBytes($reloadCommand), [System.Net.WebSockets.WebSocketMessageType]::Text, $true, [System.Threading.CancellationToken]::None)
                    $sendTask.Wait()

                    $focusCommand = @{
                        id     = 2
                        method = "Target.activateTarget"
                        params = @{
                            targetId = $target.id
                        }
                    } | ConvertTo-Json -Compress
                    $focusSendTask = $webSocket.SendAsync([System.Text.Encoding]::UTF8.GetBytes($focusCommand), [System.Net.WebSockets.WebSocketMessageType]::Text, $true, [System.Threading.CancellationToken]::None)
                    $focusSendTask.Wait()
                    INFO "Browser reloaded."

                } else {
                    ERRORLOG "Failed to connect to WebSocket."
                }

            } else {
                ERRORLOG "No WebSocket URL found!"
            }
        } else {
            INFO "No matching Chrome session, opening a new one..."
            Start-Process "chrome" "--remote-debugging-port=9222 $appUrl"
        }
    } catch {
        INFO "Window not found, opening a new one..."
        Start-Process "chrome" "--remote-debugging-port=9222 $appUrl"
    }
}

switch ($Action) {
    "start" {
        tomcat -Action start
        break
    }
    "stop" {
        tomcat -Action stop
        break
    }
    "clean" {
        cleanOldDeployments
        break
    }
    "deploy" {
        switch ($SubAction) {
            "dev" {
                deploy -Type dev
                break
            }
            "mvn" {
                deploy -Type mvn
                break
            }
            default {
                ERRORLOG "Invalid subaction $SubAction. Use 'dev' or 'mvn'."
                exit 1
            }
        }
        break
    }
    "help" {
        HELP
        break
    }
    default {
        ERRORLOG "Invalid action $Action. Use 'start', 'stop', 'clean', 'deploy', or 'help'."
        exit 1
    }          
}
