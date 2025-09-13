# InstaGraph Auto Deployment Script
# PowerShell script for Windows environment

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("docker", "direct", "dev")]
    [string]$Mode = "direct",
    
    [Parameter(Mandatory=$false)]
    [int]$Port = 8080,
    
    [Parameter(Mandatory=$false)]
    [ValidateSet("neo4j", "falkordb", "none")]
    [string]$Database = "none"
)

Write-Host "=== InstaGraph Deployment Script ===" -ForegroundColor Green
Write-Host "Mode: $Mode" -ForegroundColor Yellow
Write-Host "Port: $Port" -ForegroundColor Yellow
Write-Host "Database: $Database" -ForegroundColor Yellow
Write-Host ""

# Check .env file
if (-not (Test-Path ".env")) {
    Write-Host "No .env file found, creating..." -ForegroundColor Yellow
    if (Test-Path ".env.example") {
        Copy-Item ".env.example" ".env"
        Write-Host "Please edit .env file to configure environment variables (especially OPENAI_API_KEY)" -ForegroundColor Red
        Write-Host "Run this script again after configuration" -ForegroundColor Red
        exit 1
    } else {
        Write-Host "No .env.example file found" -ForegroundColor Red
        exit 1
    }
}

# Check environment variables
$envContent = Get-Content ".env" -Raw
if ($envContent -notmatch "OPENAI_API_KEY=.+") {
    Write-Host "Warning: OPENAI_API_KEY not configured or empty" -ForegroundColor Red
    Write-Host "Please edit .env file to configure API key" -ForegroundColor Red
    exit 1
}

switch ($Mode) {
    "docker" {
        Write-Host "Deploying with Docker mode..." -ForegroundColor Yellow
        
        # Check Docker installation
        if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
            Write-Host "Error: Docker not installed or not in PATH" -ForegroundColor Red
            exit 1
        }
        
        # Check Docker Compose availability
        if (-not (Get-Command docker-compose -ErrorAction SilentlyContinue)) {
            Write-Host "Error: Docker Compose not installed or not in PATH" -ForegroundColor Red
            exit 1
        }
        
        # Build and start container
        Write-Host "Building Docker image..." -ForegroundColor Blue
        docker build -t instagraph .
        
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Error: Docker image build failed" -ForegroundColor Red
            exit 1
        }
        
        Write-Host "Starting Docker container..." -ForegroundColor Blue
        docker run -d --name instagraph-container -p "${Port}:8080" --env-file .env instagraph
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Docker container started successfully, port: $Port" -ForegroundColor Green
        } else {
            Write-Host "Error: Docker container startup failed" -ForegroundColor Red
            exit 1
        }
    }
    
    "dev" {
        Write-Host "Deploying with development mode..." -ForegroundColor Yellow
        
        # Check Docker Compose availability
        if (-not (Get-Command docker-compose -ErrorAction SilentlyContinue)) {
            Write-Host "Error: Docker Compose not installed or not in PATH" -ForegroundColor Red
            exit 1
        }
        
        # Use development environment configuration
        $composeFile = "docker\docker-compose-dev.yml"
        if (-not (Test-Path $composeFile)) {
            Write-Host "Error: Development environment config file not found: $composeFile" -ForegroundColor Red
            exit 1
        }
        
        Write-Host "Starting development environment..." -ForegroundColor Blue
        docker-compose -f $composeFile --env-file .env up -d
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Development environment started successfully, port: $Port" -ForegroundColor Green
        } else {
            Write-Host "Error: Development environment startup failed" -ForegroundColor Red
            exit 1
        }
    }
    
    "direct" {
        Write-Host "Deploying with direct mode..." -ForegroundColor Yellow
        
        # Check Python installation
        if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
            Write-Host "Error: Python not installed or not in PATH" -ForegroundColor Red
            exit 1
        }
        
        # Install dependencies
        Write-Host "Installing Python dependencies..." -ForegroundColor Blue
        python -m pip install -r requirements.txt
        
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Error: Dependencies installation failed" -ForegroundColor Red
            exit 1
        }
        
        # Start application
        Write-Host "Starting InstaGraph service..." -ForegroundColor Blue
        $args = @("main.py", "--port", $Port)
        if ($Database -ne "auto") {
            $args += @("--graph", $Database)
        }
        
        Start-Process -FilePath "python" -ArgumentList $args -NoNewWindow
        
        Write-Host "InstaGraph service started, port: $Port" -ForegroundColor Green
        Write-Host "Access URL: http://localhost:$Port" -ForegroundColor Cyan
    }
    
    default {
        Write-Host "Error: Unsupported deployment mode '$Mode'" -ForegroundColor Red
        Write-Host "Supported modes: docker, dev, direct" -ForegroundColor Yellow
        exit 1
    }
}

Write-Host "Deployment completed!" -ForegroundColor Green