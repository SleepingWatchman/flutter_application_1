#!/bin/bash

# Скрипт для генерации отчета покрытия тестами

echo "🧪 Запуск тестов с измерением покрытия..."

# Очистить предыдущие отчеты
echo "🧹 Очистка предыдущих отчетов..."
rm -rf coverage/

# Запустить тесты с покрытием
echo "🚀 Выполнение тестов..."
flutter test --coverage

# Проверить, что файл покрытия создан
if [ ! -f "coverage/lcov.info" ]; then
    echo "❌ Ошибка: файл покрытия не был создан"
    exit 1
fi

echo "✅ Тесты выполнены успешно"

# Проверить наличие lcov
if ! command -v lcov &> /dev/null; then
    echo "⚠️  lcov не установлен. Устанавливаю..."
    
    # Определить операционную систему
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        sudo apt-get update && sudo apt-get install -y lcov
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        if command -v brew &> /dev/null; then
            brew install lcov
        else
            echo "❌ Homebrew не найден. Установите lcov вручную"
            exit 1
        fi
    elif [[ "$OSTYPE" == "msys" ]]; then
        echo "❌ Для Windows используйте WSL или установите lcov через package manager"
        exit 1
    else
        echo "❌ Неподдерживаемая операционная система"
        exit 1
    fi
fi

# Генерировать HTML отчет
echo "📊 Генерация HTML отчета..."
genhtml coverage/lcov.info -o coverage/html

# Проверить успешность генерации
if [ -d "coverage/html" ]; then
    echo "✅ HTML отчет создан в папке coverage/html/"
    echo "🌐 Откройте coverage/html/index.html в браузере для просмотра"
    
    # Попытаться открыть отчет автоматически
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if command -v xdg-open &> /dev/null; then
            xdg-open coverage/html/index.html
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        open coverage/html/index.html
    elif [[ "$OSTYPE" == "msys" ]]; then
        start coverage/html/index.html
    fi
else
    echo "❌ Ошибка генерации HTML отчета"
    exit 1
fi

# Показать краткую статистику
echo ""
echo "📈 Краткая статистика покрытия:"
lcov --summary coverage/lcov.info

echo ""
echo "🎉 Отчет готов!" 