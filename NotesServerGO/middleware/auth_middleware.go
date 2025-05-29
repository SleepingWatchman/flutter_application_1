package middleware

import (
	"context"
	"log"
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
		log.Printf("JWTMiddleware: получен запрос %s %s от %s", r.Method, r.URL.Path, r.RemoteAddr)

		authHeader := r.Header.Get("Authorization")
		if authHeader == "" {
			log.Printf("JWTMiddleware: ОШИБКА - отсутствует заголовок Authorization для %s %s", r.Method, r.URL.Path)
			http.Error(w, "Отсутствует заголовок Authorization", http.StatusUnauthorized)
			return
		}

		parts := strings.Split(authHeader, " ")
		if len(parts) != 2 || strings.ToLower(parts[0]) != "bearer" {
			log.Printf("JWTMiddleware: ОШИБКА - неверный формат заголовка Authorization для %s %s: %s", r.Method, r.URL.Path, authHeader)
			http.Error(w, "Неверный формат заголовка Authorization (ожидается Bearer {token})", http.StatusUnauthorized)
			return
		}

		tokenString := parts[1]
		claims, err := auth.ValidateToken(tokenString)
		if err != nil {
			log.Printf("JWTMiddleware: ОШИБКА - невалидный токен для %s %s: %v", r.Method, r.URL.Path, err)
			http.Error(w, "Невалидный токен: "+err.Error(), http.StatusUnauthorized)
			return
		}

		log.Printf("JWTMiddleware: успешная аутентификация пользователя %d (%s) для %s %s", claims.UserID, claims.Username, r.Method, r.URL.Path)

		// Добавляем информацию из токена в контекст запроса
		ctx := context.WithValue(r.Context(), UserIDKey, claims.UserID)
		ctx = context.WithValue(ctx, UsernameKey, claims.Username)

		next.ServeHTTP(w, r.WithContext(ctx))
	})
}
