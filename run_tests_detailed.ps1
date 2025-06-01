# PowerShell скрипт для детального анализа результатов тестирования
# Запуск: .\run_tests_detailed.ps1

param(
    [switch]$SkipCoverage,
    [string]$TestPath = "",
    [switch]$Verbose
)

Write-Host "🧪 Запуск детального анализа тестов Flutter" -ForegroundColor Cyan
Write-Host "=" * 60 -ForegroundColor Gray

# Проверка, что мы в корневой папке проекта
if (!(Test-Path "pubspec.yaml")) {
    Write-Host "❌ Ошибка: pubspec.yaml не найден. Запустите скрипт из корневой папки проекта." -ForegroundColor Red
    exit 1
}

# Очистка предыдущих результатов
Write-Host "🧹 Очистка предыдущих отчетов..." -ForegroundColor Yellow
if (Test-Path "coverage") {
    Remove-Item -Recurse -Force "coverage"
}
if (Test-Path "test_results.json") {
    Remove-Item -Force "test_results.json"
}

# Определение команды тестирования
$testCommand = "flutter test"
if ($TestPath) {
    $testCommand += " $TestPath"
}
if (!$SkipCoverage) {
    $testCommand += " --coverage"
}
$testCommand += " --reporter=json --machine"

Write-Host "🚀 Выполнение тестов..." -ForegroundColor Green
Write-Host "Команда: $testCommand" -ForegroundColor Gray

# Запуск тестов с JSON выводом
$testOutput = ""
$testExitCode = 0

try {
    $testOutput = Invoke-Expression $testCommand 2>&1
    $testExitCode = $LASTEXITCODE
} catch {
    Write-Host "❌ Ошибка выполнения тестов: $_" -ForegroundColor Red
    exit 1
}

# Сохранение результатов в файл для анализа
$testOutput | Out-File -FilePath "test_results.json" -Encoding UTF8

Write-Host "`n📊 Анализ результатов тестирования..." -ForegroundColor Cyan

# Парсинг результатов
$passedTests = @()
$failedTests = @()
$skippedTests = @()
$totalTests = 0

# Парсинг JSON вывода
$testOutput -split "`n" | ForEach-Object {
    $line = $_.Trim()
    if ($line -match '^\{.*\}$') {
        try {
            $testResult = $line | ConvertFrom-Json
            
            if ($testResult.type -eq "testStart") {
                $totalTests++
            }
            elseif ($testResult.type -eq "testDone") {
                $testName = $testResult.test.name
                $groupName = $testResult.test.groupIDs -join " > "
                if ($groupName) { 
                    $fullTestName = "$groupName > $testName" 
                } else { 
                    $fullTestName = $testName 
                }
                
                if ($testResult.result -eq "success") {
                    $passedTests += @{
                        Name = $fullTestName
                        Time = $testResult.time
                    }
                }
                elseif ($testResult.result -eq "failure" -or $testResult.result -eq "error") {
                    $failedTests += @{
                        Name = $fullTestName
                        Error = $testResult.error
                        StackTrace = $testResult.stackTrace
                    }
                }
                elseif ($testResult.result -eq "skip") {
                    $skippedTests += @{
                        Name = $fullTestName
                        Reason = $testResult.skipReason
                    }
                }
            }
        }
        catch {
            # Игнорируем строки, которые не являются валидным JSON
        }
    }
}

# Вывод сводной информации
Write-Host "`n" + "=" * 60 -ForegroundColor Gray
Write-Host "📈 СВОДНЫЙ ОТЧЕТ ПО ТЕСТИРОВАНИЮ" -ForegroundColor Cyan -BackgroundColor DarkBlue
Write-Host "=" * 60 -ForegroundColor Gray

$passedCount = $passedTests.Count
$failedCount = $failedTests.Count
$skippedCount = $skippedTests.Count
$totalCount = $passedCount + $failedCount + $skippedCount

Write-Host "`n📊 Общая статистика:" -ForegroundColor White
Write-Host "   Всего тестов: $totalCount" -ForegroundColor Gray
Write-Host "   ✅ Прошли: $passedCount" -ForegroundColor Green
Write-Host "   ❌ Не прошли: $failedCount" -ForegroundColor Red
Write-Host "   ⏭️ Пропущено: $skippedCount" -ForegroundColor Yellow

if ($totalCount -gt 0) {
    $successRate = [math]::Round(($passedCount / $totalCount) * 100, 2)
    Write-Host "   📈 Процент успеха: $successRate%" -ForegroundColor $(if ($successRate -ge 80) { "Green" } elseif ($successRate -ge 60) { "Yellow" } else { "Red" })
}

# Детальный список прошедших тестов
if ($passedTests.Count -gt 0) {
    Write-Host "`n✅ ПРОШЕДШИЕ ТЕСТЫ ($($passedTests.Count)):" -ForegroundColor Green
    $passedTests | Sort-Object Name | ForEach-Object {
        if ($_.Time) { 
            $timeMs = " ($($_.Time)ms)" 
        } else { 
            $timeMs = "" 
        }
        Write-Host "   ✓ $($_.Name)$timeMs" -ForegroundColor DarkGreen
    }
}

# Детальный список неудачных тестов
if ($failedTests.Count -gt 0) {
    Write-Host "`n❌ НЕУДАЧНЫЕ ТЕСТЫ ($($failedTests.Count)):" -ForegroundColor Red
    $failedTests | ForEach-Object {
        Write-Host "   ✗ $($_.Name)" -ForegroundColor DarkRed
        if ($_.Error) {
            Write-Host "     Ошибка: $($_.Error)" -ForegroundColor Red
        }
        if ($Verbose -and $_.StackTrace) {
            Write-Host "     Stack trace: $($_.StackTrace)" -ForegroundColor DarkRed
        }
    }
}

# Список пропущенных тестов
if ($skippedTests.Count -gt 0) {
    Write-Host "`n⏭️ ПРОПУЩЕННЫЕ ТЕСТЫ ($($skippedTests.Count)):" -ForegroundColor Yellow
    $skippedTests | ForEach-Object {
        Write-Host "   ⏭ $($_.Name)" -ForegroundColor DarkYellow
        if ($_.Reason) {
            Write-Host "     Причина: $($_.Reason)" -ForegroundColor Yellow
        }
    }
}

# Анализ покрытия кода
if (!$SkipCoverage -and (Test-Path "coverage/lcov.info")) {
    Write-Host "`n📊 АНАЛИЗ ПОКРЫТИЯ КОДА:" -ForegroundColor Cyan
    
    try {
        $lcovContent = Get-Content "coverage/lcov.info" -Raw
        
        # Парсинг LCOV для получения статистики
        $sourceFiles = @()
        $lcovContent -split "end_of_record" | ForEach-Object {
            $record = $_.Trim()
            if ($record -match "SF:(.+)" -and $record -match "LF:(\d+)" -and $record -match "LH:(\d+)") {
                $file = $matches[1] -replace ".*[\\/]lib[\\/]", "lib/"
                $totalLines = [int]$matches[2]
                $hitLines = [int]$matches[3]
                $coverage = if ($totalLines -gt 0) { [math]::Round(($hitLines / $totalLines) * 100, 1) } else { 0 }
                
                $sourceFiles += @{
                    File = $file
                    Total = $totalLines
                    Hit = $hitLines
                    Coverage = $coverage
                }
            }
        }
        
        if ($sourceFiles.Count -gt 0) {
            $totalAllLines = ($sourceFiles | Measure-Object -Property Total -Sum).Sum
            $totalHitLines = ($sourceFiles | Measure-Object -Property Hit -Sum).Sum
            $overallCoverage = if ($totalAllLines -gt 0) { [math]::Round(($totalHitLines / $totalAllLines) * 100, 2) } else { 0 }
            
            Write-Host "   📈 Общее покрытие: $overallCoverage%" -ForegroundColor $(if ($overallCoverage -ge 80) { "Green" } elseif ($overallCoverage -ge 60) { "Yellow" } else { "Red" })
            Write-Host "   📝 Всего строк: $totalAllLines" -ForegroundColor Gray
            Write-Host "   ✅ Покрыто строк: $totalHitLines" -ForegroundColor Gray
            
            # Топ файлов с низким покрытием
            $lowCoverageFiles = $sourceFiles | Where-Object { $_.Coverage -lt 70 -and $_.Total -gt 5 } | Sort-Object Coverage | Select-Object -First 5
            if ($lowCoverageFiles.Count -gt 0) {
                Write-Host "`n⚠️ Файлы с низким покрытием:" -ForegroundColor Yellow
                $lowCoverageFiles | ForEach-Object {
                    Write-Host "   $($_.Coverage)% - $($_.File) ($($_.Hit)/$($_.Total))" -ForegroundColor Red
                }
            }
            
            # Топ файлов с высоким покрытием
            $highCoverageFiles = $sourceFiles | Where-Object { $_.Coverage -ge 90 } | Sort-Object Coverage -Descending | Select-Object -First 5
            if ($highCoverageFiles.Count -gt 0) {
                Write-Host "`n🏆 Файлы с отличным покрытием:" -ForegroundColor Green
                $highCoverageFiles | ForEach-Object {
                    Write-Host "   $($_.Coverage)% - $($_.File) ($($_.Hit)/$($_.Total))" -ForegroundColor DarkGreen
                }
            }
        }
    }
    catch {
        Write-Host "   ⚠️ Не удалось проанализировать покрытие: $_" -ForegroundColor Yellow
    }
}

# Заключение
Write-Host "`n" + "=" * 60 -ForegroundColor Gray
if ($failedCount -eq 0) {
    Write-Host "🎉 ВСЕ ТЕСТЫ ПРОШЛИ УСПЕШНО!" -ForegroundColor Green -BackgroundColor DarkGreen
} elseif ($failedCount -le 3) {
    Write-Host "⚠️ ЕСТЬ НЕСКОЛЬКО НЕУДАЧНЫХ ТЕСТОВ" -ForegroundColor Yellow -BackgroundColor DarkYellow
} else {
    Write-Host "❌ МНОГО НЕУДАЧНЫХ ТЕСТОВ - ТРЕБУЕТ ВНИМАНИЯ" -ForegroundColor Red -BackgroundColor DarkRed
}

Write-Host "`n💡 Рекомендации:" -ForegroundColor Cyan
if ($failedCount -gt 0) {
    Write-Host "   • Исправьте неудачные тесты перед продолжением разработки" -ForegroundColor Yellow
}
if (!$SkipCoverage -and $overallCoverage -lt 70) {
    Write-Host "   • Добавьте больше тестов для увеличения покрытия" -ForegroundColor Yellow
}
if ($passedCount -gt 0 -and $failedCount -eq 0) {
    Write-Host "   • Отличная работа! Продолжайте поддерживать качество тестов" -ForegroundColor Green
}

Write-Host "`n📁 Дополнительные файлы:" -ForegroundColor Gray
Write-Host "   • test_results.json - детальные результаты в JSON формате" -ForegroundColor Gray
if (!$SkipCoverage -and (Test-Path "coverage/lcov.info")) {
    Write-Host "   • coverage/lcov.info - данные покрытия для генерации HTML отчета" -ForegroundColor Gray
}

Write-Host "`n✨ Анализ завершен!" -ForegroundColor Cyan

# Возврат кода выхода
exit $testExitCode 