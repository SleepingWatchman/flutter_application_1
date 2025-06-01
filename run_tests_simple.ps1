# Упрощенный PowerShell скрипт для анализа тестов Flutter
param(
    [switch]$SkipCoverage,
    [string]$TestPath = ""
)

Write-Host "===============================================" -ForegroundColor Cyan
Write-Host "     Flutter Tests - Детальный анализ        " -ForegroundColor White
Write-Host "===============================================" -ForegroundColor Cyan

# Проверка корневой папки
if (!(Test-Path "pubspec.yaml")) {
    Write-Host "ОШИБКА: pubspec.yaml не найден. Запустите из корневой папки проекта." -ForegroundColor Red
    exit 1
}

# Очистка старых результатов
Write-Host "Очистка предыдущих результатов..." -ForegroundColor Yellow
if (Test-Path "coverage") { Remove-Item -Recurse -Force "coverage" }
if (Test-Path "test_results.txt") { Remove-Item -Force "test_results.txt" }

# Формирование команды
$cmd = "flutter test"
if ($TestPath) { $cmd += " $TestPath" }
if (!$SkipCoverage) { $cmd += " --coverage" }

Write-Host "Выполнение тестов..." -ForegroundColor Green
Write-Host "Команда: $cmd" -ForegroundColor Gray

# Запуск тестов и сохранение вывода
$output = & cmd /c "$cmd 2>&1"
$exitCode = $LASTEXITCODE
$output | Out-File -FilePath "test_results.txt" -Encoding UTF8

Write-Host "`n===============================================" -ForegroundColor Cyan
Write-Host "              РЕЗУЛЬТАТЫ ТЕСТИРОВАНИЯ         " -ForegroundColor White
Write-Host "===============================================" -ForegroundColor Cyan

# Анализ результатов
$outputText = $output -join "`n"
$passedCount = 0
$failedCount = 0
$skippedCount = 0

# Подсчет результатов из вывода
if ($outputText -match "\+(\d+) -(\d+):") {
    $passedCount = [int]$matches[1]
    $failedCount = [int]$matches[2]
}

$totalCount = $passedCount + $failedCount

Write-Host "`nОБЩАЯ СТАТИСТИКА:" -ForegroundColor White
Write-Host "  Всего тестов: $totalCount" -ForegroundColor Gray
Write-Host "  Прошли: $passedCount" -ForegroundColor Green
Write-Host "  Не прошли: $failedCount" -ForegroundColor Red

if ($totalCount -gt 0) {
    $successRate = [math]::Round(($passedCount / $totalCount) * 100, 1)
    $color = if ($successRate -ge 80) { "Green" } elseif ($successRate -ge 60) { "Yellow" } else { "Red" }
    Write-Host "  Процент успеха: $successRate%" -ForegroundColor $color
}

# Вывод неудачных тестов
if ($failedCount -gt 0) {
    Write-Host "`nНЕУДАЧНЫЕ ТЕСТЫ:" -ForegroundColor Red
    $output | ForEach-Object {
        if ($_ -match "EXCEPTION CAUGHT" -or $_ -match "Test failed" -or $_ -match "\[E\]") {
            Write-Host "  $($_)" -ForegroundColor DarkRed
        }
    }
}

# Анализ покрытия кода
if (!$SkipCoverage -and (Test-Path "coverage/lcov.info")) {
    Write-Host "`nАНАЛИЗ ПОКРЫТИЯ КОДА:" -ForegroundColor Cyan
    
    try {
        $lcovContent = Get-Content "coverage/lcov.info" -Raw
        $totalLines = 0
        $hitLines = 0
        
        # Простой подсчет покрытия
        $lcovContent -split "end_of_record" | ForEach-Object {
            if ($_ -match "LF:(\d+)") { $totalLines += [int]$matches[1] }
            if ($_ -match "LH:(\d+)") { $hitLines += [int]$matches[1] }
        }
        
        if ($totalLines -gt 0) {
            $coverage = [math]::Round(($hitLines / $totalLines) * 100, 2)
            $coverageColor = if ($coverage -ge 80) { "Green" } elseif ($coverage -ge 60) { "Yellow" } else { "Red" }
            
            Write-Host "  Общее покрытие: $coverage%" -ForegroundColor $coverageColor
            Write-Host "  Всего строк: $totalLines" -ForegroundColor Gray
            Write-Host "  Покрыто строк: $hitLines" -ForegroundColor Gray
        }
    }
    catch {
        Write-Host "  Не удалось проанализировать покрытие: $_" -ForegroundColor Yellow
    }
}

# Заключение
Write-Host "`n===============================================" -ForegroundColor Cyan
if ($failedCount -eq 0) {
    Write-Host "       ВСЕ ТЕСТЫ ПРОШЛИ УСПЕШНО!             " -ForegroundColor Green
} else {
    Write-Host "     ЕСТЬ НЕУДАЧНЫЕ ТЕСТЫ - ТРЕБУЕТ ВНИМАНИЯ " -ForegroundColor Red
}
Write-Host "===============================================" -ForegroundColor Cyan

Write-Host "`nРЕКОМЕНДАЦИИ:" -ForegroundColor Yellow
if ($failedCount -gt 0) {
    Write-Host "  • Исправьте неудачные тесты" -ForegroundColor Red
}
if (!$SkipCoverage) {
    Write-Host "  • Стремитесь к покрытию выше 80%" -ForegroundColor Yellow
}
Write-Host "  • Регулярно запускайте тесты при разработке" -ForegroundColor Green

Write-Host "`nДОПОЛНИТЕЛЬНЫЕ ФАЙЛЫ:" -ForegroundColor Gray
Write-Host "  • test_results.txt - полный вывод тестов" -ForegroundColor Gray
if (!$SkipCoverage -and (Test-Path "coverage/lcov.info")) {
    Write-Host "  • coverage/lcov.info - данные покрытия" -ForegroundColor Gray
}

Write-Host "`nАнализ завершен!" -ForegroundColor Cyan
exit $exitCode 