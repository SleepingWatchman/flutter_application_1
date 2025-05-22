package middleware

import (
	"context"
	"net/http"
	"notes_server_go/auth"
	"strings"
)

// UserIDKey - ключ для хранения ID пользователя в контексте запроса.
const UserIDKey = "userID"

// UsernameKey - ключ для хранения имени пользователя в контексте запроса.
const UsernameKey = "username"

// JWTMiddleware проверяет наличие и валидность JWT в заголовке Authorization.
// Если токен валиден, ID пользователя и имя пользователя добавляются в контекст запроса.
func JWTMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		authHeader := r.Header.Get("Authorization")
		if authHeader == "" {
			http.Error(w, "Отсутствует заголовок Authorization", http.StatusUnauthorized)
			return
		}

		parts := strings.Split(authHeader, " ")
		if len(parts) != 2 || strings.ToLower(parts[0]) != "bearer" {
			http.Error(w, "Неверный формат заголовка Authorization (ожидается Bearer {token})", http.StatusUnauthorized)
			return
		}

		tokenString := parts[1]
		claims, err := auth.ValidateToken(tokenString)
		if err != nil {
			http.Error(w, "Невалидный токен: "+err.Error(), http.StatusUnauthorized)
			return
		}

		// Добавляем информацию из токена в контекст запроса
		ctx := context.WithValue(r.Context(), UserIDKey, claims.UserID)
		ctx = context.WithValue(ctx, UsernameKey, claims.Username)

		next.ServeHTTP(w, r.WithContext(ctx))
	})
}
