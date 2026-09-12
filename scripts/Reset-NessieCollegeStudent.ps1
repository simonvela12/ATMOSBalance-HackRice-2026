[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $true)]
    [string]$CustomerID,

    [string]$ApiKey = $env:NESSIE_API_KEY,

    [switch]$ResetExisting
)

$ErrorActionPreference = 'Stop'
$baseURL = 'https://api.nessieisreal.com'

if ([string]::IsNullOrWhiteSpace($ApiKey)) {
    throw 'Set NESSIE_API_KEY or pass -ApiKey.'
}

function Invoke-Nessie {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('GET', 'POST', 'PUT', 'DELETE')][string]$Method,
        [Parameter(Mandatory = $true)][string]$Path,
        [object]$Body
    )

    $uri = "$baseURL/$Path`?key=$([Uri]::EscapeDataString($ApiKey))"
    $arguments = @{
        Method      = $Method
        Uri         = $uri
        ContentType = 'application/json'
    }
    if ($null -ne $Body) {
        $arguments.Body = $Body | ConvertTo-Json -Depth 8 -Compress
    }
    Invoke-RestMethod @arguments
}

function Get-CreatedObject {
    param([object]$Response)
    if ($null -ne $Response.objectCreated) { return $Response.objectCreated }
    return $Response
}

$existing = @(Invoke-Nessie -Method GET -Path "customers/$CustomerID/accounts")
if ($ResetExisting) {
    foreach ($account in $existing) {
        $accountID = $account._id
        if ($PSCmdlet.ShouldProcess("Nessie account $accountID", 'Delete account and its transaction history')) {
            $null = Invoke-Nessie -Method DELETE -Path "accounts/$accountID"
        }
    }
} elseif ($existing.Count -gt 0) {
    throw "Customer already has $($existing.Count) account(s). Re-run with -ResetExisting to replace them."
}

$remaining = @(Invoke-Nessie -Method GET -Path "customers/$CustomerID/accounts")
if ($remaining.Count -gt 0) {
    throw "Reset did not complete: $($remaining.Count) Nessie account(s) still exist."
}

$accountNumber = -join (1..16 | ForEach-Object { Get-Random -Minimum 0 -Maximum 10 })
$accountResponse = Invoke-Nessie -Method POST -Path "customers/$CustomerID/accounts" -Body @{
    type           = 'Checking'
    nickname       = 'College Checking'
    rewards        = 0
    balance        = 2350.00
    account_number = $accountNumber
}
$account = Get-CreatedObject $accountResponse
$accountID = if ($account._id) { $account._id } else { $account.id }
if ([string]::IsNullOrWhiteSpace($accountID)) { throw 'Nessie did not return the new account ID.' }

$today = [DateTime]::UtcNow.Date
$monthStarts = @(
    $today.AddMonths(-2).AddDays(-($today.Day - 1)),
    $today.AddMonths(-1).AddDays(-($today.Day - 1)),
    $today.AddDays(-($today.Day - 1))
)

$merchants = @{
    rent      = '9acb2d3a-e74a-4cf1-94c3-7170151696be'
    groceries = '0f3cdce7-4dab-43e5-870d-54d3a9d68d09'
    coffee    = 'b967468a-263a-4163-8c4d-e22f29acab48'
    meals     = '23952dad-b64e-49b0-9b7d-be47703b8516'
    phone     = 'a858d02b-36a0-4d3a-867d-f03d15d3338b'
    utility   = '921ebfde-cc5b-4043-992e-bcefaf4b652b'
    gym       = '1125dc05-86dc-4768-b5fa-23590e767f17'
    streaming = '813e8045-bacc-422e-8314-511e3a28389f'
    laundry   = 'ddeed6e8-571a-4811-b81f-b543f73c080a'
    rideshare = 'e80d8969-0c38-4257-9209-b540ebeb5dfa'
    books     = '12872741-c041-474e-9dc9-2d7fc1644d28'
}

$purchases = [System.Collections.Generic.List[object]]::new()
$deposits = [System.Collections.Generic.List[object]]::new()
$transfers = [System.Collections.Generic.List[object]]::new()

for ($monthIndex = 0; $monthIndex -lt $monthStarts.Count; $monthIndex++) {
    $start = $monthStarts[$monthIndex]
    $deposits.Add(@{ date = $start.AddDays(4); amount = 620.00; description = 'Campus library paycheck' })
    $deposits.Add(@{ date = $start.AddDays(18); amount = 620.00; description = 'Campus library paycheck' })
    $deposits.Add(@{ date = $start.AddDays(9); amount = 175.00; description = 'Family support' })

    $purchases.Add(@{ merchant = 'rent'; date = $start.AddDays(1); amount = 725.00; description = 'Student apartment rent' })
    $purchases.Add(@{ merchant = 'phone'; date = $start.AddDays(6); amount = 42.00; description = 'Student mobile plan' })
    $purchases.Add(@{ merchant = 'utility'; date = $start.AddDays(11); amount = 58.00 + (4 * $monthIndex); description = 'Shared apartment utilities' })
    $purchases.Add(@{ merchant = 'gym'; date = $start.AddDays(13); amount = 24.00; description = 'Campus recreation membership' })
    $purchases.Add(@{ merchant = 'streaming'; date = $start.AddDays(20); amount = 9.99; description = 'Student streaming plan' })

    foreach ($week in 0..3) {
        $purchases.Add(@{ merchant = 'groceries'; date = $start.AddDays(3 + (7 * $week)); amount = 43.25 + (2.15 * (($week + $monthIndex) % 3)); description = 'Weekly groceries' })
        $purchases.Add(@{ merchant = 'coffee'; date = $start.AddDays(5 + (7 * $week)); amount = 5.40 + (0.75 * ($week % 2)); description = 'Coffee between classes' })
        $purchases.Add(@{ merchant = 'meals'; date = $start.AddDays(7 + (7 * $week)); amount = 13.50 + (1.25 * (($week + 1) % 3)); description = 'Campus meal' })
    }
    $purchases.Add(@{ merchant = 'laundry'; date = $start.AddDays(15); amount = 8.50; description = 'Laundry' })
    $purchases.Add(@{ merchant = 'rideshare'; date = $start.AddDays(23); amount = 18.75 + (2 * $monthIndex); description = 'Weekend rideshare' })
}

$purchases.Add(@{ merchant = 'books'; date = $monthStarts[0].AddDays(2); amount = 186.40; description = 'Textbooks and lab materials' })
$transfers.Add(@{ date = $monthStarts[0].AddDays(26); amount = 35.00; description = 'Club dues transfer' })
$transfers.Add(@{ date = $monthStarts[1].AddDays(26); amount = 20.00; description = 'Roommate reimbursement transfer' })

$createdPurchases = 0
$createdDeposits = 0
$createdTransfers = 0

foreach ($item in $deposits) {
    if ($item.date -gt $today) { continue }
    $null = Invoke-Nessie -Method POST -Path "accounts/$accountID/deposits" -Body @{
        medium          = 'balance'
        transaction_date = $item.date.ToString('yyyy-MM-dd')
        amount          = [decimal]$item.amount
        status          = 'completed'
        description     = "$($item.description) [COLLEGE-3M]"
    }
    $createdDeposits++
}

foreach ($item in $purchases) {
    if ($item.date -gt $today) { continue }
    $merchantID = $merchants[$item.merchant]
    $null = Invoke-Nessie -Method POST -Path "merchants/$merchantID/accounts/$accountID/purchases" -Body @{
        medium        = 'balance'
        purchase_date = $item.date.ToString('yyyy-MM-dd')
        amount        = [decimal]$item.amount
        status        = 'completed'
        description   = "$($item.description) [COLLEGE-3M]"
    }
    $createdPurchases++
}

foreach ($item in $transfers) {
    if ($item.date -gt $today) { continue }
    $null = Invoke-Nessie -Method POST -Path "accounts/$accountID/transfers" -Body @{
        transaction_date = $item.date.ToString('yyyy-MM-dd')
        amount            = [decimal]$item.amount
        status            = 'completed'
        description       = "$($item.description) [COLLEGE-3M]"
    }
    $createdTransfers++
}

[pscustomobject]@{
    customerID       = $CustomerID
    accountID        = $accountID
    balance          = 2350.00
    purchasesCreated = $createdPurchases
    depositsCreated  = $createdDeposits
    transfersCreated = $createdTransfers
    totalCreated     = $createdPurchases + $createdDeposits + $createdTransfers
} | ConvertTo-Json -Depth 3
