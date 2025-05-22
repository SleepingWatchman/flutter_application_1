package auth

import (
	"fmt"
	"time"

	"github.com/golang-jwt/jwt/v4"
)

// jwtKey должен быть защищенным и, в идеале, загружаться из конфигурации.
// Для примера используем простую строку.
var jwtKey = []byte("your_very_secret_and_secure_key_replace_it_!@#$%^")

// Claims структура для JWT, включающая стандартные и пользовательские поля.
type Claims struct {
	UserID   int64  `json:"user_id"`
	Username string `json:"username"`
	jwt.RegisteredClaims
}

// GenerateToken создает новый JWT для пользователя.
func GenerateToken(userID int64, username string) (string, time.Time, error) {
	// Токен будет действителен, например, 24 часа
	expirationTime := time.Now().Add(24 * time.Hour)

	claims := &Claims{
		UserID:   userID,
		Username: username,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(expirationTime),
			Issuer:    "notes_server_go", // Можно добавить имя вашего приложения
		},
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	tokenString, err := token.SignedString(jwtKey)
	if err != nil {
		return "", time.Time{}, fmt.Errorf("could not sign token: %w", err)
	}

	return tokenString, expirationTime, nil
}

// ValidateToken проверяет JWT и возвращает claims, если токен валиден.
func ValidateToken(tokenString string) (*Claims, error) {
	claims := &Claims{}

	token, err := jwt.ParseWithClaims(tokenString, claims, func(token *jwt.Token) (interface{}, error) {
		if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("unexpected signing method: %v", token.Header["alg"])
		}
		return jwtKey, nil
	})

	if err != nil {
		if ve, ok := err.(*jwt.ValidationError); ok {
			if ve.Errors&jwt.ValidationErrorMalformed != 0 {
				return nil, fmt.Errorf("token is malformed")
			} else if ve.Errors&(jwt.ValidationErrorExpired|jwt.ValidationErrorNotValidYet) != 0 {
				// Token is either expired or not active yet
				return nil, fmt.Errorf("token is expired or not active yet")
			} else {
				return nil, fmt.Errorf("couldn't handle this token: %w", err)
			}
		} else {
			return nil, fmt.Errorf("couldn't handle this token: %w", err)
		}
	}

	if !token.Valid {
		return nil, fmt.Errorf("token is invalid")
	}

	return claims, nil
}
