# WordPress Malware Scanner per PowerShell
# Scansiona temi e plugin WordPress per identificare codice potenzialmente malevolo

param(
    [string]$Path = "."
)

# Colori per l'output
function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
}

# Pattern PHP pericolosi
$PhpPatterns = @{
    'eval\s*\(' = 'Esecuzione codice dinamico - potenziale backdoor'
    'base64_decode\s*\(\s*[''"][A-Za-z0-9+/=]{50,}' = 'Decodifica base64 di stringa lunga - possibile offuscamento'
    'gzinflate\s*\(\s*base64_decode' = 'Decompressione + base64 - offuscamento multiplo'
    'str_rot13\s*\(\s*base64_decode' = 'ROT13 + base64 - offuscamento multiplo'
    'preg_replace\s*\([^)]*[''"]/e[''"]' = 'preg_replace con /e - esecuzione codice'
    'assert\s*\(\s*\$' = 'Assert con variabile - possibile esecuzione codice'
    'create_function' = 'create_function deprecata - rischio esecuzione codice'
    '\$\{[''"]GLOBALS[''"]' = 'Accesso diretto a $GLOBALS - manipolazione scope'
    'call_user_func\s*\(\s*\$' = 'call_user_func con variabile - esecuzione dinamica'
    'system\s*\(\s*\$_(GET|POST|REQUEST|COOKIE)' = 'Esecuzione sistema con input utente non sanitizzato'
    'exec\s*\(\s*\$_(GET|POST|REQUEST|COOKIE)' = 'Esecuzione comando con input utente non sanitizzato'
    'shell_exec\s*\(\s*\$_(GET|POST|REQUEST|COOKIE)' = 'Shell exec con input utente non sanitizzato'
    'passthru\s*\(\s*\$_(GET|POST|REQUEST|COOKIE)' = 'Passthru con input utente non sanitizzato'
    'file_get_contents\s*\(\s*\$_(GET|POST|REQUEST)' = 'file_get_contents con input GET/POST - possibile LFI/RFI'
    'file_put_contents\s*\([^)]*\$_(GET|POST|REQUEST)' = 'file_put_contents con input utente - scrittura file arbitraria'
    'unserialize\s*\(\s*\$_(GET|POST|REQUEST|COOKIE)' = 'unserialize con input utente - object injection'
    'include\s*\(\s*\$_(GET|POST|REQUEST)' = 'include con input utente - file inclusion'
    'require\s*\(\s*\$_(GET|POST|REQUEST)' = 'require con input utente - file inclusion'
    '@\s*(eval|exec|system|shell_exec|passthru)' = 'Soppressione errori su funzioni pericolose'
    'error_reporting\s*\(\s*0\s*\)' = 'Disabilitazione errori - possibile occultamento'
    '\\x[0-9a-fA-F]{2}\\x[0-9a-fA-F]{2}\\x[0-9a-fA-F]{2}' = 'Stringa con encoding esadecimale - offuscamento'
    '(?:eval|assert|system)\s*\(\s*(?:gzinflate|gzuncompress|base64_decode)' = 'Esecuzione + decompressione/decodifica'
}

# Pattern JavaScript pericolosi
$JsPatterns = @{
    'eval\s*\(' = 'Esecuzione codice JavaScript dinamico'
    'Function\s*\(\s*[''"]' = 'Constructor Function - esecuzione codice dinamico'
    'setTimeout\s*\(\s*[''"][^''""]*(?:eval|Function)' = 'setTimeout con eval - esecuzione ritardata'
    'setInterval\s*\(\s*[''"][^''""]*(?:eval|Function)' = 'setInterval con eval - esecuzione ripetuta'
    'document\.write\s*\([^)]*(?:unescape|atob|fromCharCode)' = 'document.write con decodifica - injection'
    'innerHTML\s*=.*(?:atob|unescape|fromCharCode)' = 'innerHTML con decodifica - possibile XSS'
    '\.appendChild\s*\([^)]*script' = 'Append script dinamico al DOM'
    'createElement\s*\([''"]script[''"]' = 'Creazione dinamica tag script'
    'XMLHttpRequest.*\.open\s*\([^)]*(?:https?:)?//(?!.*(?:wordpress\.org|wp\.com))' = 'XMLHttpRequest a dominio esterno'
    'fetch\s*\([''"](?:https?:)?//(?!.*(?:wordpress\.org|wp\.com))' = 'Fetch API a dominio esterno sospetto'
    'atob\s*\(\s*[''"][A-Za-z0-9+/=]{50,}' = 'Decodifica base64 di stringa lunga'
    'String\.fromCharCode\s*\([^)]{50,}\)' = 'fromCharCode con molti caratteri - offuscamento'
    'unescape\s*\([''"]%[0-9a-fA-F]{2}' = 'Unescape con encoding - offuscamento'
    'location\s*=.*(?:atob|unescape|fromCharCode)' = 'Redirect con decodifica - possibile phishing'
    'document\.cookie\s*=.*(?:;|\+).*(?:domain|path)' = 'Manipolazione cookie con dominio/path'
    'new\s+Function\s*\(.*\$' = 'Constructor Function con contenuto sospetto'
    '\.insertAdjacentHTML\s*\([^)]*(?:atob|unescape)' = 'insertAdjacentHTML con decodifica'
    'postMessage\s*\([^)]*(?:https?:)?//' = 'postMessage a origine esterna'
}

# Array per memorizzare i risultati
$Results = @()

Write-ColorOutput "`n=== WordPress Malware Scanner ===" "Cyan"
Write-ColorOutput "Scansione in corso...`n" "Yellow"

# Trova tutti i file PHP e JS ricorsivamente
# NOTA: -Include ha un bug in PowerShell, usiamo Where-Object invece
Write-ColorOutput "Ricerca file PHP e JS..." "Yellow"

$AllFiles = Get-ChildItem -Path $Path -Recurse -Force -File -ErrorAction SilentlyContinue
$Files = $AllFiles | Where-Object { 
    ($_.Extension -eq ".php" -or $_.Extension -eq ".js") -and
    $_.FullName -notmatch '(node_modules|\.git|vendor)'
}

$TotalFiles = $Files.Count
$CurrentFile = 0

Write-ColorOutput "Trovati $TotalFiles file da analizzare..." "Green"

foreach ($File in $Files) {
    $CurrentFile++
    
    # Mostra progresso
    if ($CurrentFile % 10 -eq 0) {
        Write-Progress -Activity "Scansione malware" -Status "File $CurrentFile di $TotalFiles" -PercentComplete (($CurrentFile / $TotalFiles) * 100)
    }
    
    $FileExt = $File.Extension.ToLower()
    $Content = Get-Content -Path $File.FullName -Raw -ErrorAction SilentlyContinue
    
    if (-not $Content) { continue }
    
    # Seleziona i pattern appropriati
    $Patterns = @{}
    if ($FileExt -eq ".php") {
        $Patterns = $PhpPatterns
    } elseif ($FileExt -eq ".js") {
        $Patterns = $JsPatterns
    }
    
    # Cerca ogni pattern
    foreach ($Pattern in $Patterns.Keys) {
        $Matches = [regex]::Matches($Content, $Pattern, [System.Text.RegularExpressions.RegexOptions]::Multiline)
        
        foreach ($Match in $Matches) {
            # Calcola linea e colonna
            $LineNumber = ($Content.Substring(0, $Match.Index) -split "`n").Count
            $LastNewLine = $Content.Substring(0, $Match.Index).LastIndexOf("`n")
            $ColNumber = $Match.Index - $LastNewLine
            
            $Results += [PSCustomObject]@{
                FileName = $File.Name
                Position = "L${LineNumber}:C${ColNumber}"
                Reason = $Patterns[$Pattern]
                Path = $File.FullName | Resolve-Path -Relative
            }
        }
    }
}

Write-Progress -Activity "Scansione malware" -Completed

Write-ColorOutput "`nFile scansionati: $TotalFiles`n" "Green"

# Mostra risultati
if ($Results.Count -gt 0) {
    Write-ColorOutput "⚠ POTENZIALI MINACCE RILEVATE ⚠`n" "Red"
    
    # Formatta come tabella
    $Results | Format-Table -Property FileName, Position, Reason, Path -Wrap -AutoSize
    
    Write-ColorOutput "`nTotale minacce rilevate: $($Results.Count)`n" "Yellow"
    
    # Chiedi se salvare il report
    $Save = Read-Host "Vuoi salvare il report in formato Markdown? (s/n)"
    
    if ($Save -eq "s" -or $Save -eq "S") {
        $Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $ReportFile = "wp_security_scan_$Timestamp.md"
        
        $ReportContent = @"
# WordPress Security Scan Report

**Data scansione:** $(Get-Date -Format "dd/MM/yyyy HH:mm:ss")
**File scansionati:** $TotalFiles
**Minacce rilevate:** $($Results.Count)

---

## Dettagli Minacce

| Nome File | Posizione | Motivo | Percorso |
|-----------|-----------|--------|----------|
"@
        
        foreach ($Result in $Results) {
            $ReportContent += "`n| $($Result.FileName) | $($Result.Position) | $($Result.Reason) | ``$($Result.Path)`` |"
        }
        
        $ReportContent += @"

---

## Note

- Questo report identifica **potenziali** minacce che richiedono verifica manuale
- Non tutti i pattern rilevati sono necessariamente malevoli
- Verificare il contesto d'uso di ogni funzione segnalata
- Consultare la documentazione ufficiale di WordPress per le best practices
"@
        
        $ReportContent | Out-File -FilePath $ReportFile -Encoding UTF8
        Write-ColorOutput "✓ Report salvato in: $ReportFile" "Green"
    } else {
        Write-ColorOutput "Report non salvato." "Yellow"
    }
} else {
    Write-ColorOutput "✓ Nessuna minaccia rilevata!" "Green"
}

Write-ColorOutput "`nScansione completata.`n" "Cyan"