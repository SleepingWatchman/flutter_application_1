# Развертывание Notes Server на DockHost

## ✅ Готово к развертыванию!

Ваш Notes Server успешно собран и протестирован. Образ `notes-server-go` готов к развертыванию.

## 🚀 Быстрое развертывание на DockHost

### 1. Подготовка файлов
Убедитесь, что у вас есть:
- ✅ `Dockerfile` - оптимизирован для DockHost
- ✅ `docker-compose.yml` - конфигурация для развертывания
- ✅ Образ `notes-server-go` (уже собран)

### 2. Создание проекта на DockHost
1. Зайдите на [DockHost](https://my.dockhost.ru/project)
2. Создайте новый проект типа "Docker Compose"
3. Назовите проект: `notes-server`

### 3. Загрузка кода
**Вариант A: Git (рекомендуется)**
```bash
git init
git add .
git commit -m "Deploy to DockHost"
git remote add origin <your-repo-url>
git push -u origin main
```
Затем в DockHost: Git Repository → URL вашего репо

**Вариант B: Прямая загрузка**
Загрузите все файлы из папки `NotesServerGO` в DockHost

### 4. Запуск
1. Нажмите "Deploy" в DockHost
2. Дождитесь завершения сборки
3. Проверьте статус: "Running" ✅

### 5. Получение URL
Ваш сервер будет доступен по адресу:
`https://your-project-name.dockhost.ru`

## 🔧 Проверка работы

После развертывания проверьте:
```bash
# Основная страница
curl https://your-project-name.dockhost.ru/

# Статус сервера
curl https://your-project-name.dockhost.ru/api/Service/status
```

## 📱 Обновление Flutter приложения

Измените URL в вашем Flutter приложении:
```dart
// В lib/services/auth_service.dart
static const String baseUrl = 'https://your-project-name.dockhost.ru';
```

## 📋 Доступные API endpoints

### Открытые маршруты:
- `GET /` - основная страница
- `GET /api/Service/status` - статус сервера
- `POST /api/auth/register` - регистрация
- `POST /api/auth/login` - вход
- `GET /uploads/*` - статические файлы

### Защищенные маршруты (требуют JWT):
- `PUT /api/auth/profile` - обновление профиля
- `GET /api/collaboration/databases` - список совместных баз
- `POST /api/collaboration/databases` - создание совместной базы
- `GET /api/backup/personal/download` - скачивание резервной копии
- `POST /api/backup/personal/upload` - загрузка резервной копии

## 🔄 Обновление

### Через Git:
```bash
git add .
git commit -m "Update server"
git push
```
DockHost автоматически пересоберет и перезапустит сервер.

### Через файлы:
Загрузите обновленные файлы в DockHost и нажмите "Deploy".

## 📊 Мониторинг

В панели управления DockHost:
- **Logs** - просмотр логов сервера
- **Monitoring** - использование ресурсов
- **Status** - статус контейнера

## 🛠️ Устранение неполадок

| Проблема | Решение |
|----------|---------|
| Не собирается | Проверьте логи сборки в DockHost |
| Не запускается | Проверьте логи контейнера |
| Домен не работает | Подождите 5-10 минут |
| SSL не работает | Автоматически через 5-10 минут |

## 📞 Поддержка

Если возникли проблемы:
1. Проверьте логи в панели управления DockHost
2. Убедитесь, что все файлы загружены корректно
3. Проверьте конфигурацию docker-compose.yml

---

**Успешного развертывания!** 🚀

Ваш Notes Server готов к работе на DockHost! 