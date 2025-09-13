# InstaGraph Deployment Verification Script
# PowerShell script for Windows environment

param(
    [Parameter(Mandatory=$false)]
    [string]$BaseUrl = "http://localhost:8080",
    
    [Parameter(Mandatory=$false)]
    [int]$Timeout = 60
)

Write-Host "=== InstaGraph Deployment Verification ===" -ForegroundColor Green
Write-Host "Base URL: $BaseUrl" -ForegroundColor Yellow
Write-Host "Timeout: $Timeout seconds" -ForegroundColor Yellow
Write-Host ""

# Test results
$testResults = @{
    "HealthCheck" = $false
    "HomePage" = $false
    "ApiEndpoint" = $false
    "GraphData" = $false
    "GraphHistory" = $false
    "Graphviz" = $false
}

# Function to test HTTP endpoint
function Test-Endpoint {
    param(
        [string]$Url,
        [string]$Method = "GET",
        [hashtable]$Headers = @{},
        [string]$Body = $null
    )
    
    try {
        $params = @{
            Uri = $Url
            Method = $Method
            TimeoutSec = 10
            UseBasicParsing = $true
        }
        
        if ($Headers.Count -gt 0) {
            $params.Headers = $Headers
        }
        
        if ($Body -and $Method -ne "GET") {
            $params.Body = $Body
        }
        
        $response = Invoke-WebRequest @params
        return @{
            Success = $true
            StatusCode = $response.StatusCode
            Content = $response.Content
        }
    } catch {
        return @{
            Success = $false
            Error = $_.Exception.Message
        }
    }
}

# Function to wait for service startup
function Wait-ForService {
    param([string]$Url, [int]$MaxWait)
    
    Write-Host "Waiting for service to start..." -ForegroundColor Yellow
    $elapsed = 0
    
    while ($elapsed -lt $MaxWait) {
        try {
            $response = Invoke-WebRequest -Uri $Url -TimeoutSec 5 -ErrorAction Stop
            Write-Host "Service is ready!" -ForegroundColor Green
            return $true
        } catch {
            Start-Sleep -Seconds 2
            $elapsed += 2
            Write-Host "Waiting... ($elapsed/$MaxWait seconds)" -ForegroundColor Gray
        }
    }
    
    Write-Host "Service did not start within $MaxWait seconds" -ForegroundColor Red
    return $false
}

# Wait for service to be ready
if (-not (Wait-ForService "$BaseUrl/health" $Timeout)) {
    Write-Host "Service is not responding. Exiting..." -ForegroundColor Red
    exit 1
}

Write-Host "Starting verification tests..." -ForegroundColor Blue
Write-Host ""

# Test 1: Health Check
Write-Host "1. Testing health check endpoint..." -ForegroundColor Cyan
$healthResult = Test-Endpoint "$BaseUrl/health"
if ($healthResult.Success) {
    Write-Host "   ✓ Health check passed (Status: $($healthResult.StatusCode))" -ForegroundColor Green
    $testResults.HealthCheck = $true
    
    # Parse health check response
    try {
        $healthData = $healthResult.Content | ConvertFrom-Json
        Write-Host "   Service Status: $($healthData.status)" -ForegroundColor Gray
        Write-Host "   Version: $($healthData.version)" -ForegroundColor Gray
    } catch {
        Write-Host "   Could not parse health check response" -ForegroundColor Yellow
    }
} else {
    Write-Host "   ✗ Health check failed: $($healthResult.Error)" -ForegroundColor Red
}

# Test 2: Home Page
Write-Host "2. Testing home page..." -ForegroundColor Cyan
$homeResult = Test-Endpoint $BaseUrl
if ($homeResult.Success) {
    Write-Host "   ✓ Home page accessible (Status: $($homeResult.StatusCode))" -ForegroundColor Green
    $testResults.HomePage = $true
} else {
    Write-Host "   ✗ Home page failed: $($homeResult.Error)" -ForegroundColor Red
}

# Test 3: API Endpoint (POST request)
Write-Host "3. Testing API endpoint..." -ForegroundColor Cyan
$apiHeaders = @{
    "Content-Type" = "application/json"
}
$apiBody = @{
    "user_input" = "Test knowledge graph generation"
} | ConvertTo-Json

$apiResult = Test-Endpoint "$BaseUrl/get_response_data" "POST" $apiHeaders $apiBody
if ($apiResult.Success) {
    Write-Host "   ✓ API endpoint accessible (Status: $($apiResult.StatusCode))" -ForegroundColor Green
    $testResults.ApiEndpoint = $true
} else {
    Write-Host "   ✗ API endpoint failed: $($apiResult.Error)" -ForegroundColor Red
    Write-Host "   Note: This might be expected if OPENAI_API_KEY is not configured" -ForegroundColor Yellow
}

# Test 4: Graph Data Endpoint
Write-Host "4. Testing graph data endpoint..." -ForegroundColor Cyan
$graphHeaders = @{
    "Content-Type" = "application/json"
}
$graphBody = '{}'
$graphResult = Test-Endpoint "$BaseUrl/get_graph_data" "POST" $graphHeaders $graphBody
if ($graphResult.Success) {
    Write-Host "   ✓ Graph data endpoint accessible (Status: $($graphResult.StatusCode))" -ForegroundColor Green
    $testResults.GraphData = $true
} else {
    Write-Host "   ✗ Graph data endpoint failed: $($graphResult.Error)" -ForegroundColor Red
}

# Test 5: Graph History Endpoint
Write-Host "5. Testing graph history endpoint..." -ForegroundColor Cyan
$historyResult = Test-Endpoint "$BaseUrl/get_graph_history"
if ($historyResult.Success) {
    Write-Host "   ✓ Graph history endpoint accessible (Status: $($historyResult.StatusCode))" -ForegroundColor Green
    $testResults.GraphHistory = $true
} else {
    Write-Host "   ✗ Graph history endpoint failed: $($historyResult.Error)" -ForegroundColor Red
}

# Test 6: Graphviz Endpoint
Write-Host "6. Testing Graphviz endpoint..." -ForegroundColor Cyan
$graphvizHeaders = @{
    "Content-Type" = "application/json"
}
$graphvizBody = '{}'
$graphvizResult = Test-Endpoint "$BaseUrl/graphviz" "POST" $graphvizHeaders $graphvizBody
if ($graphvizResult.Success) {
    Write-Host "   ✓ Graphviz endpoint accessible (Status: $($graphvizResult.StatusCode))" -ForegroundColor Green
    $testResults.Graphviz = $true
} else {
    Write-Host "   ✗ Graphviz endpoint failed: $($graphvizResult.Error)" -ForegroundColor Red
}

# Summary
Write-Host ""
Write-Host "=== Test Results Summary ===" -ForegroundColor Green
$passedTests = ($testResults.Values | Where-Object { $_ -eq $true }).Count
$totalTests = $testResults.Count

foreach ($test in $testResults.GetEnumerator()) {
    $status = if ($test.Value) { "✓ PASS" } else { "✗ FAIL" }
    $color = if ($test.Value) { "Green" } else { "Red" }
    Write-Host "$($test.Key): $status" -ForegroundColor $color
}

Write-Host ""
Write-Host "Overall: $passedTests/$totalTests tests passed" -ForegroundColor $(if ($passedTests -eq $totalTests) { "Green" } else { "Yellow" })

if ($passedTests -eq $totalTests) {
    Write-Host "🎉 All tests passed! InstaGraph is working correctly." -ForegroundColor Green
    exit 0
} elseif ($passedTests -ge ($totalTests * 0.5)) {
    Write-Host "⚠️  Some tests failed, but core functionality appears to work." -ForegroundColor Yellow
    exit 0
} else {
    Write-Host "❌ Multiple tests failed. Please check the deployment." -ForegroundColor Red
    exit 1
}