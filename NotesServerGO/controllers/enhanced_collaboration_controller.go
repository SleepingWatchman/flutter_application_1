package controllers

import (
	"encoding/json"
	"log"
	"net/http"
	"strconv"

	"notes_server_go/data"
	"notes_server_go/middleware"
	"notes_server_go/models"

	"github.com/gorilla/mux"
)

// GetDatabaseUsersHandler получает список пользователей в совместной базе данных
// GET /api/collaboration/databases/{db_id}/users
func GetDatabaseUsersHandler(w http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)
	dbIDStr := vars["db_id"]

	currentUserID, ok := r.Context().Value(middleware.UserIDKey).(int64)
	if !ok {
		respondError(w, http.StatusUnauthorized, "Не удалось получить ID пользователя из токена.")
		return
	}

	dbID, err := strconv.ParseInt(dbIDStr, 10, 64)
	if err != nil {
		respondError(w, http.StatusBadRequest, "Неверный формат ID базы данных.")
		return
	}

	// Проверяем доступ пользователя к базе данных
	role, err := data.GetUserRoleInSharedDatabase(dbID, currentUserID)
	if err != nil {
		log.Printf("Ошибка при проверке роли пользователя %d в БД %d: %v", currentUserID, dbID, err)
		respondError(w, http.StatusInternalServerError, "Ошибка сервера при проверке доступа к БД.")
		return
	}
	if role == nil {
		respondError(w, http.StatusForbidden, "Доступ к указанной совместной базе данных запрещен.")
		return
	}

	users, err := data.GetUsersInSharedDatabaseWithDetails(dbID)
	if err != nil {
		log.Printf("Ошибка при получении пользователей БД %d: %v", dbID, err)
		respondError(w, http.StatusInternalServerError, "Ошибка при получении списка пользователей.")
		return
	}

	respondJSON(w, http.StatusOK, users)
}

// InviteUserHandler приглашает пользователя в совместную базу данных
// POST /api/collaboration/databases/{db_id}/invite
func InviteUserHandler(w http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)
	dbIDStr := vars["db_id"]

	currentUserID, ok := r.Context().Value(middleware.UserIDKey).(int64)
	if !ok {
		respondError(w, http.StatusUnauthorized, "Не удалось получить ID пользователя из токена.")
		return
	}

	dbID, err := strconv.ParseInt(dbIDStr, 10, 64)
	if err != nil {
		respondError(w, http.StatusBadRequest, "Неверный формат ID базы данных.")
		return
	}

	var req struct {
		Email string                        `json:"email"`
		Role  models.SharedDatabaseUserRole `json:"role"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		respondError(w, http.StatusBadRequest, "Неверный формат запроса: "+err.Error())
		return
	}
	defer r.Body.Close()

	if req.Email == "" || req.Role == "" {
		respondError(w, http.StatusBadRequest, "Email и Role обязательны для заполнения.")
		return
	}

	// Проверяем права на приглашение
	role, err := data.GetUserRoleInSharedDatabase(dbID, currentUserID)
	if err != nil || role == nil || *role != models.RoleOwner {
		respondError(w, http.StatusForbidden, "Только владелец может приглашать пользователей.")
		return
	}

	err = data.CreateInvitation(dbID, currentUserID, req.Email, req.Role)
	if err != nil {
		log.Printf("Ошибка при создании приглашения для %s в БД %d: %v", req.Email, dbID, err)
		respondError(w, http.StatusInternalServerError, "Не удалось создать приглашение: "+err.Error())
		return
	}

	respondJSON(w, http.StatusCreated, map[string]string{"message": "Приглашение отправлено"})
}

// GetCurrentUserRoleHandler получает роль текущего пользователя в базе данных
// GET /api/collaboration/databases/{db_id}/my-role
func GetCurrentUserRoleHandler(w http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)
	dbIDStr := vars["db_id"]

	currentUserID, ok := r.Context().Value(middleware.UserIDKey).(int64)
	if !ok {
		respondError(w, http.StatusUnauthorized, "Не удалось получить ID пользователя из токена.")
		return
	}

	dbID, err := strconv.ParseInt(dbIDStr, 10, 64)
	if err != nil {
		respondError(w, http.StatusBadRequest, "Неверный формат ID базы данных.")
		return
	}

	role, err := data.GetUserRoleInSharedDatabase(dbID, currentUserID)
	if err != nil {
		log.Printf("Ошибка при получении роли пользователя %d в БД %d: %v", currentUserID, dbID, err)
		respondError(w, http.StatusInternalServerError, "Ошибка сервера.")
		return
	}

	if role == nil {
		respondError(w, http.StatusNotFound, "Пользователь не найден в базе данных.")
		return
	}

	respondJSON(w, http.StatusOK, map[string]interface{}{
		"role": *role,
	})
}

// CheckPermissionsHandler проверяет права доступа пользователя
// GET /api/collaboration/databases/{db_id}/permissions
func CheckPermissionsHandler(w http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)
	dbIDStr := vars["db_id"]

	currentUserID, ok := r.Context().Value(middleware.UserIDKey).(int64)
	if !ok {
		respondError(w, http.StatusUnauthorized, "Не удалось получить ID пользователя из токена.")
		return
	}

	dbID, err := strconv.ParseInt(dbIDStr, 10, 64)
	if err != nil {
		respondError(w, http.StatusBadRequest, "Неверный формат ID базы данных.")
		return
	}

	role, err := data.GetUserRoleInSharedDatabase(dbID, currentUserID)
	if err != nil {
		log.Printf("Ошибка при получении роли пользователя %d в БД %d: %v", currentUserID, dbID, err)
		respondError(w, http.StatusInternalServerError, "Ошибка сервера.")
		return
	}

	permissions := map[string]bool{
		"can_edit":         false,
		"can_delete":       false,
		"can_manage_users": false,
		"can_invite_users": false,
		"can_leave":        false,
	}

	if role != nil {
		switch *role {
		case models.RoleOwner:
			permissions["can_edit"] = true
			permissions["can_delete"] = true
			permissions["can_manage_users"] = true
			permissions["can_invite_users"] = true
			permissions["can_leave"] = false // Владелец не может покинуть базу
		case models.RoleCollaborator, models.RoleEditor:
			permissions["can_edit"] = true
			permissions["can_delete"] = false
			permissions["can_manage_users"] = false
			permissions["can_invite_users"] = false
			permissions["can_leave"] = true
		case models.RoleViewer:
			permissions["can_edit"] = false
			permissions["can_delete"] = false
			permissions["can_manage_users"] = false
			permissions["can_invite_users"] = false
			permissions["can_leave"] = true
		}
	}

	respondJSON(w, http.StatusOK, permissions)
}

// GetPendingInvitationsHandler получает приглашения для текущего пользователя
// GET /api/collaboration/invitations/pending
func GetPendingInvitationsHandler(w http.ResponseWriter, r *http.Request) {
	currentUserID, ok := r.Context().Value(middleware.UserIDKey).(int64)
	if !ok {
		respondError(w, http.StatusUnauthorized, "Не удалось получить ID пользователя из токена.")
		return
	}

	// Получаем email текущего пользователя
	user, err := data.GetUserByID(currentUserID)
	if err != nil {
		log.Printf("Ошибка при получении пользователя %d: %v", currentUserID, err)
		respondError(w, http.StatusInternalServerError, "Ошибка сервера.")
		return
	}

	invitations, err := data.GetPendingInvitations(user.Email)
	if err != nil {
		log.Printf("Ошибка при получении приглашений для %s: %v", user.Email, err)
		respondError(w, http.StatusInternalServerError, "Ошибка при получении приглашений.")
		return
	}

	// Если приглашений нет, возвращаем пустой массив вместо null
	if invitations == nil {
		invitations = []models.SharedDatabaseInvitation{}
	}

	respondJSON(w, http.StatusOK, invitations)
}

// AcceptInvitationHandler принимает приглашение
// POST /api/collaboration/invitations/{invitation_id}/accept
func AcceptInvitationHandler(w http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)
	invitationIDStr := vars["invitation_id"]

	currentUserID, ok := r.Context().Value(middleware.UserIDKey).(int64)
	if !ok {
		respondError(w, http.StatusUnauthorized, "Не удалось получить ID пользователя из токена.")
		return
	}

	invitationID, err := strconv.ParseInt(invitationIDStr, 10, 64)
	if err != nil {
		respondError(w, http.StatusBadRequest, "Неверный формат ID приглашения.")
		return
	}

	err = data.AcceptInvitation(invitationID, currentUserID)
	if err != nil {
		log.Printf("Ошибка при принятии приглашения %d пользователем %d: %v", invitationID, currentUserID, err)
		respondError(w, http.StatusInternalServerError, "Не удалось принять приглашение: "+err.Error())
		return
	}

	respondJSON(w, http.StatusOK, map[string]string{"message": "Приглашение принято"})
}

// DeclineInvitationHandler отклоняет приглашение
// POST /api/collaboration/invitations/{invitation_id}/decline
func DeclineInvitationHandler(w http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)
	invitationIDStr := vars["invitation_id"]

	currentUserID, ok := r.Context().Value(middleware.UserIDKey).(int64)
	if !ok {
		respondError(w, http.StatusUnauthorized, "Не удалось получить ID пользователя из токена.")
		return
	}

	invitationID, err := strconv.ParseInt(invitationIDStr, 10, 64)
	if err != nil {
		respondError(w, http.StatusBadRequest, "Неверный формат ID приглашения.")
		return
	}

	err = data.DeclineInvitation(invitationID, currentUserID)
	if err != nil {
		log.Printf("Ошибка при отклонении приглашения %d пользователем %d: %v", invitationID, currentUserID, err)
		respondError(w, http.StatusInternalServerError, "Не удалось отклонить приглашение: "+err.Error())
		return
	}

	respondJSON(w, http.StatusOK, map[string]string{"message": "Приглашение отклонено"})
}

// GetDatabaseVersionHandler получает версию базы данных для синхронизации
// GET /api/collaboration/databases/{db_id}/version
func GetDatabaseVersionHandler(w http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)
	dbIDStr := vars["db_id"]

	currentUserID, ok := r.Context().Value(middleware.UserIDKey).(int64)
	if !ok {
		respondError(w, http.StatusUnauthorized, "Не удалось получить ID пользователя из токена.")
		return
	}

	dbID, err := strconv.ParseInt(dbIDStr, 10, 64)
	if err != nil {
		respondError(w, http.StatusBadRequest, "Неверный формат ID базы данных.")
		return
	}

	// Проверяем доступ
	role, err := data.GetUserRoleInSharedDatabase(dbID, currentUserID)
	if err != nil || role == nil {
		respondError(w, http.StatusForbidden, "Доступ запрещен.")
		return
	}

	version, err := data.GetDatabaseVersion(dbID)
	if err != nil {
		log.Printf("Ошибка при получении версии БД %d: %v", dbID, err)
		respondError(w, http.StatusInternalServerError, "Ошибка получения версии.")
		return
	}

	respondJSON(w, http.StatusOK, map[string]interface{}{
		"version": version,
	})
}

// GetDatabaseChangesHandler получает изменения с определенной версии
// GET /api/collaboration/databases/{db_id}/changes?since_version=X
func GetDatabaseChangesHandler(w http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)
	dbIDStr := vars["db_id"]
	sinceVersion := r.URL.Query().Get("since_version")

	currentUserID, ok := r.Context().Value(middleware.UserIDKey).(int64)
	if !ok {
		respondError(w, http.StatusUnauthorized, "Не удалось получить ID пользователя из токена.")
		return
	}

	dbID, err := strconv.ParseInt(dbIDStr, 10, 64)
	if err != nil {
		respondError(w, http.StatusBadRequest, "Неверный формат ID базы данных.")
		return
	}

	// Проверяем доступ
	role, err := data.GetUserRoleInSharedDatabase(dbID, currentUserID)
	if err != nil || role == nil {
		respondError(w, http.StatusForbidden, "Доступ запрещен.")
		return
	}

	changes, err := data.GetDatabaseChanges(dbID, sinceVersion)
	if err != nil {
		log.Printf("Ошибка при получении изменений БД %d с версии %s: %v", dbID, sinceVersion, err)
		respondError(w, http.StatusInternalServerError, "Ошибка получения изменений.")
		return
	}

	respondJSON(w, http.StatusOK, map[string]interface{}{
		"changes": changes,
	})
}
