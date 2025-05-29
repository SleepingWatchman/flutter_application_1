package controllers

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"strconv"

	"notes_server_go/data"
	"notes_server_go/middleware"
	"notes_server_go/models"

	"github.com/gorilla/mux" // Добавляем импорт gorilla/mux
)

// CreateSharedDatabaseHandler обрабатывает запросы на создание новой совместной базы данных.
// POST /api/collaboration/databases
func CreateSharedDatabaseHandler(w http.ResponseWriter, r *http.Request) {
	userID, ok := r.Context().Value(middleware.UserIDKey).(int64)
	if !ok {
		respondError(w, http.StatusUnauthorized, "Не удалось получить ID пользователя из токена.")
		return
	}

	var req struct {
		Name string `json:"name"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		respondError(w, http.StatusBadRequest, "Неверный формат запроса: "+err.Error())
		return
	}
	defer r.Body.Close()

	if req.Name == "" {
		respondError(w, http.StatusBadRequest, "Имя базы данных не может быть пустым.")
		return
	}

	db := &models.SharedDatabase{
		Name:        req.Name,
		OwnerUserId: userID,
	}

	sdbID, err := data.CreateSharedDatabase(db)
	if err != nil {
		log.Printf("Ошибка при создании совместной БД для пользователя %d: %v", userID, err)
		respondError(w, http.StatusInternalServerError, "Не удалось создать совместную базу данных: "+err.Error())
		return
	}
	db.Id = sdbID // Присваиваем ID созданной записи
	// Также нужно присвоить CreatedAt и UpdatedAt, которые устанавливаются в CreateSharedDatabase
	// Чтобы вернуть их в ответе, лучше получить созданную БД из data слоя.
	// Однако, для простоты, вернем то, что есть, плюс ID.
	// Правильнее было бы, чтобы CreateSharedDatabase возвращал *models.SharedDatabase

	createdDbInfo, err := data.GetSharedDatabaseByID(sdbID, userID) // Получаем созданную БД, чтобы вернуть актуальные данные
	if err != nil || createdDbInfo == nil {
		log.Printf("Ошибка при получении созданной совместной БД %d: %v", sdbID, err)
		// Если не удалось получить, возвращаем то, что есть, но это не идеально
		respondJSON(w, http.StatusCreated, db)
		return
	}

	respondJSON(w, http.StatusCreated, createdDbInfo)
}

// GetUserSharedDatabasesHandler обрабатывает запросы на получение списка совместных БД, доступных пользователю.
// GET /api/collaboration/databases
func GetUserSharedDatabasesHandler(w http.ResponseWriter, r *http.Request) {
	userID, ok := r.Context().Value(middleware.UserIDKey).(int64)
	if !ok {
		respondError(w, http.StatusUnauthorized, "Не удалось получить ID пользователя из токена.")
		return
	}

	dbs, err := data.GetSharedDatabasesForUser(userID)
	if err != nil {
		log.Printf("Ошибка при получении списка совместных БД для пользователя %d: %v", userID, err)
		respondError(w, http.StatusInternalServerError, "Не удалось получить список совместных баз данных: "+err.Error())
		return
	}

	if dbs == nil { // Если нет БД, возвращаем пустой массив, а не null
		dbs = []models.SharedDatabase{}
	}
	respondJSON(w, http.StatusOK, dbs)
}

// GetUserSharedDatabasesWithUsersHandler обрабатывает запросы на получение списка совместных БД с информацией о пользователях.
// GET /api/collaboration/databases/with-users
func GetUserSharedDatabasesWithUsersHandler(w http.ResponseWriter, r *http.Request) {
	userID, ok := r.Context().Value(middleware.UserIDKey).(int64)
	if !ok {
		respondError(w, http.StatusUnauthorized, "Не удалось получить ID пользователя из токена.")
		return
	}

	dbs, err := data.GetSharedDatabasesWithUsersForUser(userID)
	if err != nil {
		log.Printf("Ошибка при получении списка совместных БД с пользователями для пользователя %d: %v", userID, err)
		respondError(w, http.StatusInternalServerError, "Не удалось получить список совместных баз данных: "+err.Error())
		return
	}

	if dbs == nil { // Если нет БД, возвращаем пустой массив, а не null
		dbs = []data.SharedDatabaseWithUsers{}
	}
	respondJSON(w, http.StatusOK, dbs)
}

// GetSharedDatabaseInfoHandler обрабатывает запрос на получение информации о конкретной совместной БД.
// GET /api/collaboration/databases/{db_id}
func GetSharedDatabaseInfoHandler(w http.ResponseWriter, r *http.Request) { // Удаляем dbIDStr из аргументов
	vars := mux.Vars(r)
	dbIDStr := vars["db_id"] // Извлекаем db_id из пути

	userID, ok := r.Context().Value(middleware.UserIDKey).(int64)
	if !ok {
		respondError(w, http.StatusUnauthorized, "Не удалось получить ID пользователя из токена.")
		return
	}

	dbID, err := strconv.ParseInt(dbIDStr, 10, 64)
	if err != nil {
		respondError(w, http.StatusBadRequest, "Неверный формат ID базы данных.")
		return
	}

	// data.GetSharedDatabaseByID уже проверяет доступ пользователя к этой БД
	sdb, err := data.GetSharedDatabaseByID(dbID, userID)
	if err != nil {
		log.Printf("Ошибка при получении совместной БД %d для пользователя %d: %v", dbID, userID, err)
		respondError(w, http.StatusInternalServerError, "Ошибка сервера при получении информации о базе данных.")
		return
	}
	if sdb == nil { // Если GetSharedDatabaseByID вернул nil, nil - значит, нет доступа или не существует
		respondError(w, http.StatusNotFound, "Совместная база данных не найдена или доступ запрещен.")
		return
	}

	respondJSON(w, http.StatusOK, sdb)
}

// AddUserToSharedDatabaseHandler обрабатывает добавление пользователя в совместную БД.
// POST /api/collaboration/databases/{db_id}/users
func AddUserToSharedDatabaseHandler(w http.ResponseWriter, r *http.Request) { // Удаляем dbIDStr из аргументов
	vars := mux.Vars(r)
	dbIDStr := vars["db_id"] // Извлекаем db_id из пути

	currentUserID, ok := r.Context().Value(middleware.UserIDKey).(int64)
	if !ok {
		respondError(w, http.StatusUnauthorized, "Не удалось получить ID текущего пользователя из токена.")
		return
	}

	// Восстанавливаем преобразование dbIDStr в dbID
	dbID, err := strconv.ParseInt(dbIDStr, 10, 64)
	if err != nil {
		respondError(w, http.StatusBadRequest, "Неверный формат ID базы данных.")
		return
	}

	var req struct {
		UserID int64                         `json:"user_id"`
		Role   models.SharedDatabaseUserRole `json:"role"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		respondError(w, http.StatusBadRequest, "Неверный формат запроса: "+err.Error())
		return
	}
	defer r.Body.Close()

	if req.UserID == 0 || req.Role == "" {
		respondError(w, http.StatusBadRequest, "UserID и Role обязательны для заполнения.")
		return
	}

	if req.Role != models.RoleEditor && req.Role != models.RoleViewer {
		respondError(w, http.StatusBadRequest, "Недопустимая роль. Возможные роли: editor, viewer.")
		return
	}

	err = data.AddUserToSharedDatabase(dbID, req.UserID, req.Role, currentUserID)
	if err != nil {
		log.Printf("Ошибка при добавлении пользователя %d в БД %d (инициатор %d): %v", req.UserID, dbID, currentUserID, err)
		// Определяем тип ошибки для корректного HTTP статуса
		// (например, если БД не найдена, если текущий пользователь не владелец, если пользователь уже добавлен)
		// Это можно сделать более гранулярно, проверяя текст ошибки или возвращая типизированные ошибки из data слоя
		respondError(w, http.StatusInternalServerError, "Не удалось добавить пользователя в базу данных: "+err.Error())
		return
	}

	respondJSON(w, http.StatusCreated, map[string]string{"message": "Пользователь успешно добавлен в совместную базу данных."})
}

// UpdateUserRoleHandler обновляет роль пользователя в совместной БД.
// PUT /api/collaboration/databases/{db_id}/users/{user_id_to_manage}
func UpdateUserRoleHandler(w http.ResponseWriter, r *http.Request) { // Удаляем dbIDStr и userIDToManageStr из аргументов
	vars := mux.Vars(r)
	dbIDStr := vars["db_id"]                       // Извлекаем db_id из пути
	userIDToManageStr := vars["user_id_to_manage"] // Извлекаем user_id_to_manage из пути

	currentUserID, ok := r.Context().Value(middleware.UserIDKey).(int64)
	if !ok {
		respondError(w, http.StatusUnauthorized, "Не удалось получить ID текущего пользователя из токена.")
		return
	}

	dbID, err := strconv.ParseInt(dbIDStr, 10, 64)
	if err != nil {
		respondError(w, http.StatusBadRequest, "Неверный формат ID базы данных.")
		return
	}

	userIDToManage, err := strconv.ParseInt(userIDToManageStr, 10, 64)
	if err != nil {
		respondError(w, http.StatusBadRequest, "Неверный формат ID управляемого пользователя.")
		return
	}

	var req struct {
		Role models.SharedDatabaseUserRole `json:"role"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		respondError(w, http.StatusBadRequest, "Неверный формат запроса: "+err.Error())
		return
	}
	defer r.Body.Close()

	if req.Role == "" {
		respondError(w, http.StatusBadRequest, "Поле Role обязательно для заполнения.")
		return
	}

	if req.Role != models.RoleEditor && req.Role != models.RoleViewer {
		respondError(w, http.StatusBadRequest, "Недопустимая роль. Возможные роли: editor, viewer.")
		return
	}

	err = data.UpdateUserRoleInSharedDatabase(dbID, userIDToManage, req.Role, currentUserID)
	if err != nil {
		log.Printf("Ошибка при обновлении роли пользователя %d в БД %d (инициатор %d): %v", userIDToManage, dbID, currentUserID, err)
		respondError(w, http.StatusInternalServerError, "Не удалось обновить роль пользователя: "+err.Error())
		return
	}

	respondJSON(w, http.StatusOK, map[string]string{"message": "Роль пользователя успешно обновлена."})
}

// RemoveUserFromSharedDatabaseHandler удаляет пользователя из совместной БД.
// DELETE /api/collaboration/databases/{db_id}/users/{user_id_to_manage}
func RemoveUserFromSharedDatabaseHandler(w http.ResponseWriter, r *http.Request) { // Удаляем dbIDStr и userIDToManageStr из аргументов
	vars := mux.Vars(r)
	dbIDStr := vars["db_id"]                       // Извлекаем db_id из пути
	userIDToManageStr := vars["user_id_to_manage"] // Извлекаем user_id_to_manage из пути

	currentUserID, ok := r.Context().Value(middleware.UserIDKey).(int64)
	if !ok {
		respondError(w, http.StatusUnauthorized, "Не удалось получить ID текущего пользователя из токена.")
		return
	}

	dbID, err := strconv.ParseInt(dbIDStr, 10, 64)
	if err != nil {
		respondError(w, http.StatusBadRequest, "Неверный формат ID базы данных.")
		return
	}

	userIDToManage, err := strconv.ParseInt(userIDToManageStr, 10, 64)
	if err != nil {
		respondError(w, http.StatusBadRequest, "Неверный формат ID управляемого пользователя.")
		return
	}

	err = data.RemoveUserFromSharedDatabase(dbID, userIDToManage, currentUserID)
	if err != nil {
		log.Printf("Ошибка при удалении пользователя %d из БД %d (инициатор %d): %v", userIDToManage, dbID, currentUserID, err)
		respondError(w, http.StatusInternalServerError, "Не удалось удалить пользователя из базы данных: "+err.Error())
		return
	}

	respondJSON(w, http.StatusOK, map[string]string{"message": "Пользователь успешно удален из совместной базы данных."})
}

// DeleteSharedDatabaseHandler удаляет совместную БД.
// DELETE /api/collaboration/databases/{db_id}
func DeleteSharedDatabaseHandler(w http.ResponseWriter, r *http.Request) { // Удаляем dbIDStr из аргументов
	vars := mux.Vars(r)
	dbIDStr := vars["db_id"] // Извлекаем db_id из пути

	currentUserID, ok := r.Context().Value(middleware.UserIDKey).(int64)
	if !ok {
		respondError(w, http.StatusUnauthorized, "Не удалось получить ID текущего пользователя из токена.")
		return
	}

	dbID, err := strconv.ParseInt(dbIDStr, 10, 64)
	if err != nil {
		respondError(w, http.StatusBadRequest, "Неверный формат ID базы данных.")
		return
	}

	err = data.DeleteSharedDatabase(dbID, currentUserID)
	if err != nil {
		log.Printf("Ошибка при удалении совместной БД %d (инициатор %d): %v", dbID, currentUserID, err)
		respondError(w, http.StatusInternalServerError, "Не удалось удалить совместную базу данных: "+err.Error())
		return
	}

	respondJSON(w, http.StatusOK, map[string]string{"message": "Совместная база данных успешно удалена."})
}

// LeaveSharedDatabaseHandler обрабатывает выход пользователя из совместной базы данных
func LeaveSharedDatabaseHandler(w http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)
	dbIDStr := vars["db_id"]
	dbID, err := strconv.ParseInt(dbIDStr, 10, 64)
	if err != nil {
		respondError(w, http.StatusBadRequest, "Неверный формат ID базы данных: "+err.Error())
		return
	}

	userID, ok := r.Context().Value(middleware.UserIDKey).(int64)
	if !ok {
		respondError(w, http.StatusUnauthorized, "Не удалось получить ID пользователя из токена.")
		return
	}

	err = data.LeaveSharedDatabase(dbID, userID)
	if err != nil {
		// Проверяем конкретные ошибки, чтобы вернуть правильный статус
		if err.Error() == fmt.Sprintf("база данных с ID %d не найдена", dbID) {
			respondError(w, http.StatusNotFound, err.Error())
		} else if err.Error() == "владелец не может покинуть совместную базу данных. Удалите базу данных или передайте права владения." {
			respondError(w, http.StatusForbidden, err.Error())
		} else {
			log.Printf("Ошибка при выходе пользователя %d из БД %d: %v", userID, dbID, err)
			respondError(w, http.StatusInternalServerError, "Ошибка сервера при выходе из базы данных: "+err.Error())
		}
		return
	}

	// Возвращаем 204 No Content для совместимости с клиентом
	w.WriteHeader(http.StatusNoContent)
}

// ImportSharedDatabaseHandler обрабатывает импорт совместной базы данных
func ImportSharedDatabaseHandler(w http.ResponseWriter, r *http.Request) {
	userID, ok := r.Context().Value(middleware.UserIDKey).(int64)
	if !ok {
		respondError(w, http.StatusUnauthorized, "Не удалось получить ID пользователя из токена.")
		return
	}

	var req struct {
		DatabaseID string `json:"databaseId"` // Убедимся, что тэг json правильный
	}

	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		respondError(w, http.StatusBadRequest, "Неверный формат запроса: "+err.Error())
		return
	}
	defer r.Body.Close()

	if req.DatabaseID == "" {
		respondError(w, http.StatusBadRequest, "databaseId не может быть пустым.")
		return
	}

	dbInfo, err := data.ImportSharedDatabase(req.DatabaseID, userID)
	if err != nil {
		log.Printf("Ошибка при импорте/создании совместной БД '%s' для пользователя %d: %v", req.DatabaseID, userID, err)
		respondError(w, http.StatusInternalServerError, "Ошибка сервера при импорте базы данных: "+err.Error())
		return
	}

	respondJSON(w, http.StatusOK, dbInfo) // Клиент ожидает 200 OK и саму базу данных
}

// ExportSharedDatabaseHandler обрабатывает экспорт совместной базы данных
func ExportSharedDatabaseHandler(w http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)
	dbIDStr := vars["db_id"]
	dbID, err := strconv.ParseInt(dbIDStr, 10, 64)
	if err != nil {
		respondError(w, http.StatusBadRequest, "Неверный формат ID базы данных: "+err.Error())
		return
	}

	userID, ok := r.Context().Value(middleware.UserIDKey).(int64)
	if !ok {
		respondError(w, http.StatusUnauthorized, "Не удалось получить ID пользователя из токена.")
		return
	}

	backupData, err := data.ExportSharedDatabase(dbID, userID)
	if err != nil {
		// Обработка ошибок доступа или других ошибок от data слоя
		log.Printf("Ошибка при экспорте БД %d для пользователя %d: %v", dbID, userID, err)
		if err.Error() == fmt.Sprintf("пользователь %d не имеет доступа к БД %d", userID, dbID) { // Пример проверки ошибки
			respondError(w, http.StatusForbidden, err.Error())
		} else {
			respondError(w, http.StatusInternalServerError, "Ошибка сервера при экспорте базы данных: "+err.Error())
		}
		return
	}

	respondJSON(w, http.StatusOK, backupData)
}

// GetDatabaseDataHandler обрабатывает получение данных совместной базы данных
// Этот эндпоинт по сути делает то же самое, что и Export, возвращая все данные БД.
func GetDatabaseDataHandler(w http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)
	dbIDStr := vars["databaseId"] // Обратите внимание, что в main.go здесь databaseId, а не db_id
	dbID, err := strconv.ParseInt(dbIDStr, 10, 64)
	if err != nil {
		respondError(w, http.StatusBadRequest, "Неверный формат ID базы данных: "+err.Error())
		return
	}

	userID, ok := r.Context().Value(middleware.UserIDKey).(int64)
	if !ok {
		respondError(w, http.StatusUnauthorized, "Не удалось получить ID пользователя из токена.")
		return
	}

	// Используем ту же функцию, что и для экспорта
	backupData, err := data.ExportSharedDatabase(dbID, userID)
	if err != nil {
		log.Printf("Ошибка при получении данных БД %d для пользователя %d: %v", dbID, userID, err)
		if err.Error() == fmt.Sprintf("пользователь %d не имеет доступа к БД %d", userID, dbID) {
			respondError(w, http.StatusForbidden, err.Error())
		} else {
			respondError(w, http.StatusInternalServerError, "Ошибка сервера при получении данных базы данных: "+err.Error())
		}
		return
	}

	respondJSON(w, http.StatusOK, backupData)
}

// BackupDatabaseDataHandler обрабатывает сохранение резервной копии данных совместной базы данных
func BackupDatabaseDataHandler(w http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)
	dbIDStr := vars["databaseId"] // Убедитесь, что это имя параметра совпадает с определением в main.go
	dbID, err := strconv.ParseInt(dbIDStr, 10, 64)
	if err != nil {
		respondError(w, http.StatusBadRequest, "Неверный формат ID базы данных: "+err.Error())
		return
	}

	userID, ok := r.Context().Value(middleware.UserIDKey).(int64)
	if !ok {
		respondError(w, http.StatusUnauthorized, "Не удалось получить ID пользователя из токена.")
		return
	}

	var backupData models.BackupData
	if err := json.NewDecoder(r.Body).Decode(&backupData); err != nil {
		respondError(w, http.StatusBadRequest, "Неверный формат данных бэкапа: "+err.Error())
		return
	}
	defer r.Body.Close()

	err = data.RestoreSharedDatabaseFromBackup(dbID, userID, &backupData)
	if err != nil {
		log.Printf("Ошибка при восстановлении БД %d из бэкапа для пользователя %d: %v", dbID, userID, err)
		// Здесь можно добавить более гранулярную обработку ошибок от data слоя
		// например, если пользователь не имеет прав на запись
		// или если формат данных не соответствует ожиданиям.
		// Для примера, проверяем на общую ошибку прав доступа:
		if err.Error() == fmt.Sprintf("пользователь %d не имеет прав на запись в БД %d", userID, dbID) {
			respondError(w, http.StatusForbidden, err.Error())
		} else {
			respondError(w, http.StatusInternalServerError, "Ошибка сервера при восстановлении базы данных из бэкапа: "+err.Error())
		}
		return
	}

	respondJSON(w, http.StatusOK, map[string]string{"message": "База данных успешно восстановлена из бэкапа."})
}
