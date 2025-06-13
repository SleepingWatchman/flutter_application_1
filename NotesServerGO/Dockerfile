# Оптимизированный Dockerfile для DockHost
# Используем стабильные версии образов

# Этап сборки
FROM golang:1.24.3-alpine AS builder

# Устанавливаем необходимые пакеты для сборки
RUN apk add --no-cache git gcc musl-dev sqlite-dev

# Устанавливаем рабочую директорию
WORKDIR /app

# Копируем файлы зависимостей
COPY go.mod go.sum ./

# Загружаем зависимости
RUN go mod download

# Копируем исходный код
COPY . .

# Собираем приложение
RUN CGO_ENABLED=1 GOOS=linux go build -a -installsuffix cgo -o main .

# Финальный этап - минимальный образ
FROM alpine:3.18

# Устанавливаем необходимые пакеты для runtime
RUN apk --no-cache add ca-certificates sqlite

# Создаем пользователя для безопасности
RUN addgroup -g 1001 -S appgroup && \
    adduser -u 1001 -S appuser -G appgroup

# Устанавливаем рабочую директорию
WORKDIR /app

# Копируем исполняемый файл из builder этапа
COPY --from=builder /app/main .

# Копируем необходимые директории
COPY --from=builder /app/uploads ./uploads
COPY --from=builder /app/user_backups ./user_backups

# Создаем директории для данных
RUN mkdir -p /app/data

# Изменяем владельца файлов
RUN chown -R appuser:appgroup /app

# Переключаемся на непривилегированного пользователя
USER appuser

# Открываем порт (DockHost автоматически определит порт)
EXPOSE 8080

# Переменные окружения для DockHost
ENV PORT=8080
ENV HOST=0.0.0.0

# Запускаем приложение
CMD ["./main"] 