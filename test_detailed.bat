@echo off
title Flutter Tests - Detailed Analysis

echo.
echo ===========================================================
echo  Flutter Tests - Детальный анализ тестирования
echo ===========================================================
echo.

REM Проверка наличия PowerShell
where powershell >nul 2>nul
if %errorlevel% neq 0 (
    echo [ERROR] PowerShell не найден в системе
    echo Установите PowerShell или запустите run_tests_detailed.ps1 вручную
    pause
    exit /b 1
)

REM Проверка наличия pubspec.yaml
if not exist "pubspec.yaml" (
    echo [ERROR] pubspec.yaml не найден
    echo Запустите скрипт из корневой папки Flutter проекта
    pause
    exit /b 1
)

echo [INFO] Запуск детального анализа тестов...
echo.

REM Установка политики выполнения PowerShell (временно)
powershell -Command "Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force"

REM Запуск PowerShell скрипта
powershell -ExecutionPolicy Bypass -File "run_tests_detailed.ps1" %*

REM Сохранение кода выхода
set exit_code=%errorlevel%

echo.
echo ===========================================================
if %exit_code% equ 0 (
    echo  Анализ завершен успешно
) else (
    echo  Анализ завершен с ошибками (код: %exit_code%^)
)
echo ===========================================================

pause
exit /b %exit_code% 