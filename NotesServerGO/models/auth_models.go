package models

// RegisterRequest представляет данные для регистрации нового пользователя.
type RegisterRequest struct {
	Email       string `json:"email"`
	Password    string `json:"password"`
	DisplayName string `json:"displayName"`
}

// LoginRequest представляет данные для входа пользователя.
type LoginRequest struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

// UserPublicInfo представляет публичные данные пользователя, возвращаемые API.
type UserPublicInfo struct {
	ID          int64  `json:"id"`
	Email       string `json:"email"`
	DisplayName string `json:"displayName"`
	PhotoUrl    string `json:"photoUrl"`
}

// AuthResponse представляет ответ сервера после успешной аутентификации.
type AuthResponse struct {
	Token string         `json:"token"`
	User  UserPublicInfo `json:"user"`
}

// UpdateProfileRequest представляет данные для обновления профиля пользователя.
type UpdateProfileRequest struct {
	DisplayName string `json:"displayName"`
	PhotoUrl    string `json:"photoUrl"`
}
