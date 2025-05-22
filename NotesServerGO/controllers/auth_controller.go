package controllers

import (
	"encoding/json"
	"log"
	"net/http"
	"strings"

	"notes_server_go/auth"
	"notes_server_go/data"
	"notes_server_go/models"
)

// RegisterHandler обрабатывает запросы на регистрацию новых пользователей.
// Ожидает POST-запрос с JSON-телом, содержащим username, email и password.
// Пример URL: POST /auth/register
func RegisterHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		respondError(w, http.StatusMethodNotAllowed, "Метод не разрешен. Используйте POST.")
		return
	}

	var req models.RegisterRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		respondError(w, http.StatusBadRequest, "Неверный формат запроса: "+err.Error())
		return
	}
	defer r.Body.Close()

	// Валидация входных данных
	if strings.TrimSpace(req.Email) == "" || strings.TrimSpace(req.Password) == "" || strings.TrimSpace(req.DisplayName) == "" {
		respondError(w, http.StatusBadRequest, "Email, пароль и отображаемое имя не могут быть пустыми.")
		return
	}
	// TODO: Добавить более строгую валидацию Email и пароля (длина, сложность и т.д.)

	// Проверка, существует ли пользователь с таким email
	existingUser, err := data.GetUserByEmail(req.Email)
	if err != nil {
		log.Printf("Ошибка при проверке email %s: %v", req.Email, err)
		respondError(w, http.StatusInternalServerError, "Ошибка сервера при проверке email.")
		return
	}
	if existingUser != nil {
		respondError(w, http.StatusConflict, "Пользователь с таким email уже существует.")
		return
	}

	// Создание нового пользователя
	user := &models.User{
		Email:        req.Email,
		PasswordHash: req.Password, // В CreateUser пароль будет хеширован
		DisplayName:  req.DisplayName,
		Username:     req.Email, // Пока используем Email как Username для совместимости с текущей структурой токена, можно будет изменить
		// PhotoUrl остается пустым по умолчанию
	}

	userID, err := data.CreateUser(user) // Предполагается, что CreateUser теперь принимает *models.User и обрабатывает DisplayName
	if err != nil {
		log.Printf("Ошибка при создании пользователя %s: %v", req.Email, err)
		respondError(w, http.StatusInternalServerError, "Не удалось создать пользователя: "+err.Error())
		return
	}
	user.ID = userID // Присваиваем ID созданному пользователю

	// Генерация JWT токена
	// В C# версии токен генерируется на основе User.Id. В Go текущая auth.GenerateToken принимает userID и username.
	// Для一致性 (consistency), лучше передавать ID. Username в токене может быть DisplayName или Email.
	// Пока оставим user.Username (который сейчас равен Email) для GenerateToken.
	tokenString, _, err := auth.GenerateToken(user.ID, user.Username)
	if err != nil {
		log.Printf("Ошибка при генерации токена для пользователя %s: %v", user.Email, err)
		respondError(w, http.StatusInternalServerError, "Пользователь создан, но не удалось сгенерировать токен доступа.")
		return
	}

	// Формирование ответа
	authResponse := models.AuthResponse{
		Token: tokenString,
		User: models.UserPublicInfo{
			ID:          user.ID,
			Email:       user.Email,
			DisplayName: user.DisplayName,
			PhotoUrl:    user.PhotoUrl, // Будет пустым, если не задан при создании
		},
	}
	respondJSON(w, http.StatusCreated, authResponse)
}

// LoginHandler обрабатывает запросы на вход пользователей.
// Ожидает POST-запрос с JSON-телом, содержащим username (или email) и password.
// Пример URL: POST /auth/login
func LoginHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		respondError(w, http.StatusMethodNotAllowed, "Метод не разрешен. Используйте POST.")
		return
	}

	var req models.LoginRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		respondError(w, http.StatusBadRequest, "Неверный формат запроса: "+err.Error())
		return
	}
	defer r.Body.Close()

	if strings.TrimSpace(req.Email) == "" || strings.TrimSpace(req.Password) == "" {
		respondError(w, http.StatusBadRequest, "Email и пароль не могут быть пустыми.")
		return
	}

	// Попытка найти пользователя по email
	user, err := data.GetUserByEmail(req.Email) // Изменено с GetUserByUsername
	if err != nil {
		log.Printf("Ошибка при поиске пользователя по email %s: %v", req.Email, err)
		respondError(w, http.StatusInternalServerError, "Ошибка сервера при поиске пользователя.")
		return
	}

	if user == nil {
		respondError(w, http.StatusUnauthorized, "Неверный email или пароль.") // Сообщение изменено
		return
	}

	if !data.CheckPasswordHash(req.Password, user.PasswordHash) {
		respondError(w, http.StatusUnauthorized, "Неверный email или пароль.") // Сообщение изменено
		return
	}

	// Генерация JWT токена
	// Используем user.ID и user.Username (который может быть Email или DisplayName в зависимости от настройки user.Username в RegisterHandler)
	tokenString, _, err := auth.GenerateToken(user.ID, user.Username)
	if err != nil {
		log.Printf("Ошибка при генерации токена для пользователя %s: %v", user.Email, err)
		respondError(w, http.StatusInternalServerError, "Не удалось сгенерировать токен доступа.")
		return
	}

	// Формирование ответа
	authResponse := models.AuthResponse{
		Token: tokenString,
		User: models.UserPublicInfo{
			ID:          user.ID,
			Email:       user.Email,
			DisplayName: user.DisplayName,
			PhotoUrl:    user.PhotoUrl,
		},
	}
	respondJSON(w, http.StatusOK, authResponse)
}

// UpdateProfileHandler обрабатывает запросы на обновление профиля пользователя.
// Ожидает PUT-запрос с JSON-телом, содержащим displayName и/или photoUrl.
// Пример URL: PUT /api/auth/profile (требует авторизации)
func UpdateProfileHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPut {
		respondError(w, http.StatusMethodNotAllowed, "Метод не разрешен. Используйте PUT.")
		return
	}

	// Получаем userID из контекста, установленного JWTMiddleware
	userIDCtx := r.Context().Value("userID")
	if userIDCtx == nil {
		respondError(w, http.StatusUnauthorized, "Пользователь не авторизован (отсутствует userID в контексте).")
		return
	}

	userID, ok := userIDCtx.(int64)
	if !ok || userID == 0 {
		respondError(w, http.StatusUnauthorized, "Неверный формат userID в контексте.")
		return
	}

	var req models.UpdateProfileRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		respondError(w, http.StatusBadRequest, "Неверный формат запроса: "+err.Error())
		return
	}
	defer r.Body.Close()

	// Валидация: хотя бы одно поле должно быть для обновления.
	// В C# версии не было явной проверки, но обычно ожидается, что хотя бы одно поле передается.
	// Здесь можно добавить проверку, если DisplayName и PhotoUrl оба пустые (или nil, если бы они были указателями)
	// но пока оставим как есть, пусть сервис данных решает, что делать с пустыми значениями.

	// Обновляем профиль пользователя в базе данных
	// Предполагаем, что data.UpdateUserProfile будет создан и будет обновлять только переданные поля.
	err := data.UpdateUserProfile(userID, req.DisplayName, req.PhotoUrl)
	if err != nil {
		log.Printf("Ошибка при обновлении профиля пользователя %d: %v", userID, err)
		// Здесь можно уточнить тип ошибки, например, если пользователь не найден (хотя это маловероятно, если токен валиден)
		respondError(w, http.StatusInternalServerError, "Не удалось обновить профиль пользователя: "+err.Error())
		return
	}

	// Получаем обновленные данные пользователя
	updatedUser, err := data.GetUserByID(userID) // Исправлено GetUserById на GetUserByID
	if err != nil {
		log.Printf("Ошибка при получении обновленного пользователя %d: %v", userID, err)
		respondError(w, http.StatusInternalServerError, "Не удалось получить обновленные данные пользователя.")
		return
	}
	if updatedUser == nil {
		respondError(w, http.StatusNotFound, "Обновленный пользователь не найден.") // Маловероятно
		return
	}

	// Формирование ответа с обновленными данными пользователя
	userPublicInfo := models.UserPublicInfo{
		ID:          updatedUser.ID,
		Email:       updatedUser.Email,
		DisplayName: updatedUser.DisplayName,
		PhotoUrl:    updatedUser.PhotoUrl,
	}

	respondJSON(w, http.StatusOK, userPublicInfo) // Возвращаем только UserPublicInfo, как в C#
}
