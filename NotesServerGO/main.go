package main

import (
	"fmt"
	"log"
	"net/http"

	"notes_server_go/controllers" // Импортируем пакет controllers
	"notes_server_go/data"        // Импортируем наш пакет data
	"notes_server_go/middleware"  // Импортируем пакет middleware

	"github.com/gorilla/mux" // Добавляем импорт gorilla/mux
)

func main() {
	// Инициализация базы данных
	if err := data.InitDB(); err != nil { // Убран аргумент, InitDB теперь без параметров
		log.Fatalf("Failed to initialize database: %v", err)
	}

	// Создаем новый маршрутизатор gorilla/mux
	router := mux.NewRouter()

	// Маршруты аутентификации (открытые)
	// Клиент ожидает /api/auth/...
	authRouter := router.PathPrefix("/api/auth").Subrouter()
	authRouter.HandleFunc("/register", controllers.RegisterHandler).Methods(http.MethodPost)
	authRouter.HandleFunc("/login", controllers.LoginHandler).Methods(http.MethodPost)

	// Создаем подмаршрутизатор для /api, к которому будет применяться JWTMiddleware
	apiRouter := router.PathPrefix("/api").Subrouter()
	apiRouter.Use(middleware.JWTMiddleware) // Применяем middleware ко всем маршрутам /api

	// Защищенный маршрут для обновления профиля пользователя
	// Клиент ожидает /api/auth/profile.
	// Ранее он был на authRouter без JWT.
	// authRouter.HandleFunc("/profile", controllers.UpdateProfileHandler).Methods(http.MethodPut) // Старая регистрация
	apiRouter.HandleFunc("/auth/profile", controllers.UpdateProfileHandler).Methods(http.MethodPut) // Новая регистрация с JWT

	// Защищенные маршруты для заметок
	// GET /api/notes - получить все заметки, POST /api/notes - создать заметку
	// apiRouter.HandleFunc("/notes", controllers.NotesCollectionHandler).Methods(http.MethodGet, http.MethodPost)
	// GET /api/note?id=X - получить заметку, PUT /api/note?id=X - обновить, DELETE /api/note?id=X - удалить
	// gorilla/mux также обрабатывает query parameters, так что существующие ?id=X продолжат работать
	// apiRouter.HandleFunc("/note", controllers.NoteItemHandler).Methods(http.MethodGet, http.MethodPut, http.MethodDelete)

	// Защищенные маршруты для папок
	// GET /api/folders - получить все папки, POST /api/folders - создать папку
	// apiRouter.HandleFunc("/folders", controllers.FoldersCollectionHandler).Methods(http.MethodGet, http.MethodPost)
	// GET /api/folder?id=X - получить папку, PUT /api/folder?id=X - обновить, DELETE /api/folder?id=X - удалить
	// apiRouter.HandleFunc("/folder", controllers.FolderItemHandler).Methods(http.MethodGet, http.MethodPut, http.MethodDelete)

	// Маршруты для управления совместными базами данных
	// Клиент ожидает /api/CollaborativeDatabase/databases/...
	// Старый: collabRouter := apiRouter.PathPrefix("/collaboration/databases").Subrouter()
	collabRouter := apiRouter.PathPrefix("/collaboration/databases").Subrouter()
	collabRouter.HandleFunc("", controllers.CreateSharedDatabaseHandler).Methods(http.MethodPost)
	collabRouter.HandleFunc("", controllers.GetUserSharedDatabasesHandler).Methods(http.MethodGet)
	collabRouter.HandleFunc("/with-users", controllers.GetUserSharedDatabasesWithUsersHandler).Methods(http.MethodGet)
	collabRouter.HandleFunc("/{db_id:[0-9]+}", controllers.GetSharedDatabaseInfoHandler).Methods(http.MethodGet)
	collabRouter.HandleFunc("/{db_id:[0-9]+}", controllers.DeleteSharedDatabaseHandler).Methods(http.MethodDelete)

	// Расширенные маршруты для управления пользователями
	collabRouter.HandleFunc("/{db_id:[0-9]+}/users", controllers.GetDatabaseUsersHandler).Methods(http.MethodGet)
	collabRouter.HandleFunc("/{db_id:[0-9]+}/users", controllers.AddUserToSharedDatabaseHandler).Methods(http.MethodPost)
	collabRouter.HandleFunc("/{db_id:[0-9]+}/users/{user_id_to_manage:[0-9]+}", controllers.UpdateUserRoleHandler).Methods(http.MethodPut)
	collabRouter.HandleFunc("/{db_id:[0-9]+}/users/{user_id_to_manage:[0-9]+}", controllers.RemoveUserFromSharedDatabaseHandler).Methods(http.MethodDelete)

	// Маршруты для приглашений и ролей
	collabRouter.HandleFunc("/{db_id:[0-9]+}/invite", controllers.InviteUserHandler).Methods(http.MethodPost)
	collabRouter.HandleFunc("/{db_id:[0-9]+}/my-role", controllers.GetCurrentUserRoleHandler).Methods(http.MethodGet)
	collabRouter.HandleFunc("/{db_id:[0-9]+}/permissions", controllers.CheckPermissionsHandler).Methods(http.MethodGet)

	// Маршруты для синхронизации
	collabRouter.HandleFunc("/{db_id:[0-9]+}/version", controllers.GetDatabaseVersionHandler).Methods(http.MethodGet)
	collabRouter.HandleFunc("/{db_id:[0-9]+}/changes", controllers.GetDatabaseChangesHandler).Methods(http.MethodGet)

	// Новые маршруты для управления совместными БД
	collabRouter.HandleFunc("/{db_id:[0-9]+}/leave", controllers.LeaveSharedDatabaseHandler).Methods(http.MethodPost)  // Новый обработчик
	collabRouter.HandleFunc("/{db_id:[0-9]+}/export", controllers.ExportSharedDatabaseHandler).Methods(http.MethodGet) // Новый обработчик

	// Маршруты для приглашений
	invitationRouter := apiRouter.PathPrefix("/collaboration/invitations").Subrouter()
	invitationRouter.HandleFunc("", controllers.GetPendingInvitationsHandler).Methods(http.MethodGet)
	invitationRouter.HandleFunc("/{invitation_id:[0-9]+}/accept", controllers.AcceptInvitationHandler).Methods(http.MethodPost)
	invitationRouter.HandleFunc("/{invitation_id:[0-9]+}/decline", controllers.DeclineInvitationHandler).Methods(http.MethodPost)

	// Новый маршрут для синхронизации, совместимый с текущим Flutter клиентом
	// Клиент ожидает /api/sync/{database_id}
	syncRouter := apiRouter.PathPrefix("/sync").Subrouter()
	syncRouter.HandleFunc("/{database_id:[0-9]+}", controllers.SyncSharedDatabaseHandler).Methods(http.MethodPost)

	// Маршрут для синхронизации через collaboration (альтернативный)
	collabSyncRouter := apiRouter.PathPrefix("/collaboration/sync").Subrouter()
	collabSyncRouter.HandleFunc("/{database_id:[0-9]+}", controllers.SyncSharedDatabaseHandler).Methods(http.MethodPost)

	// Маршруты для бэкапа личной БД пользователя
	// Клиент ожидает /api/UserBackup/...
	// Старый: backupRouter := apiRouter.PathPrefix("/backup/personal").Subrouter()
	backupRouter := apiRouter.PathPrefix("/backup/personal").Subrouter()
	backupRouter.HandleFunc("/upload", controllers.UploadPersonalBackupHandler).Methods(http.MethodPost)
	// Клиент вызывает /download для получения последнего бэкапа.
	// Если DownloadPersonalBackupHandler уже возвращает последний, то /download/latest можно убрать
	// или оставить для явного указания.
	// Пока оставим оба, предполагая, что DownloadPersonalBackupHandler может обработать "/latest" или просто вернуть последний по умолчанию.
	backupRouter.HandleFunc("/download/latest", controllers.DownloadPersonalBackupHandler).Methods(http.MethodGet)
	backupRouter.HandleFunc("/download", controllers.DownloadPersonalBackupHandler).Methods(http.MethodGet)

	// Маршруты для прямой загрузки/сохранения данных совместной БД (экспорт/импорт)
	// Эти маршруты также должны быть защищены JWT, поэтому используем apiRouter
	dataRouter := apiRouter.PathPrefix("/collaboration/data").Subrouter()
	dataRouter.HandleFunc("/{databaseId:[0-9]+}", controllers.GetDatabaseDataHandler).Methods(http.MethodGet)
	dataRouter.HandleFunc("/{databaseId:[0-9]+}/backup", controllers.BackupDatabaseDataHandler).Methods(http.MethodPost)
	dataRouter.HandleFunc("/import", controllers.ImportSharedDatabaseHandler).Methods(http.MethodPost)

	// Маршрут для проверки состояния сервера (открытый, без JWT)
	// Клиент ожидает /api/Service/status
	router.HandleFunc("/api/Service/status", controllers.HealthCheck).Methods(http.MethodGet)

	// Маршрут для загрузки файлов (например, фото профиля)
	// Этот маршрут также должен быть защищен JWT
	fileRouter := apiRouter.PathPrefix("/file").Subrouter()
	fileRouter.HandleFunc("/upload", controllers.UploadFileHandler).Methods(http.MethodPost)

	// Настройка отдачи статических файлов из директории /uploads
	// Этот маршрут НЕ должен быть защищен JWT, чтобы файлы были доступны по прямой ссылке.
	// Он должен быть зарегистрирован на основном router, а не на apiRouter.
	router.PathPrefix("/uploads/").Handler(http.StripPrefix("/uploads/", http.FileServer(http.Dir("./uploads"))))

	// Базовый обработчик для проверки работы сервера
	router.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintf(w, "Привет! Сервер NotesServerGO запущен. Используется gorilla/mux.")
	}).Methods(http.MethodGet)

	log.Println("Запуск сервера на порту :8080")
	// Используем наш gorilla/mux router
	if err := http.ListenAndServe(":8080", router); err != nil {
		log.Fatal(err)
	}
}
