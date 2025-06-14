package data

import (
	"database/sql"
	"fmt"
	"time"

	"notes_server_go/models"

	"golang.org/x/crypto/bcrypt"
)

// HashPassword генерирует хеш bcrypt для пароля.
func HashPassword(password string) (string, error) {
	bytes, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	return string(bytes), err
}

// CheckPasswordHash сравнивает пароль с хешем.
func CheckPasswordHash(password, hash string) bool {
	err := bcrypt.CompareHashAndPassword([]byte(hash), []byte(password))
	return err == nil
}

// CreateUser создает нового пользователя в базе данных.
func CreateUser(user *models.User) (int64, error) {
	hashedPassword, err := HashPassword(user.PasswordHash) // В модели PasswordHash это исходный пароль
	if err != nil {
		return 0, fmt.Errorf("failed to hash password: %w", err)
	}

	now := time.Now()
	// Добавляем Username в запрос, так как оно требуется в схеме базы данных
	query := `INSERT INTO Users (Username, Email, DisplayName, PhotoUrl, PasswordHash, CreatedAt, UpdatedAt)
	          VALUES (?, ?, ?, ?, ?, ?, ?)`
	result, err := AuthDB.Exec(query, user.Username, user.Email, user.DisplayName, user.PhotoUrl, hashedPassword, now, now)
	if err != nil {
		return 0, fmt.Errorf("failed to insert user: %w", err)
	}

	id, err := result.LastInsertId()
	if err != nil {
		return 0, fmt.Errorf("failed to get last insert ID for user: %w", err)
	}
	return id, nil
}

// GetUserByUsername извлекает пользователя по имени пользователя.
// ВНИМАНИЕ: Эта функция не будет работать корректно, так как колонки Username нет в БД.
// Оставлена для совместимости, если где-то вызывается, но вернет nil или ошибку.
func GetUserByUsername(username string) (*models.User, error) {
	user := &models.User{}
	// Запрос оставлен как есть, но он не найдет колонку Username
	query := `SELECT Id, Email, DisplayName, PhotoUrl, PasswordHash, CreatedAt, UpdatedAt
	          FROM Users WHERE Email = ?` // Запрос изменен на поиск по Email, так как Username нет
	err := AuthDB.Get(user, query, username) // Технически ищет по email, если username это email
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, nil // Пользователь не найден
		}
		// Ошибка будет "no such column: Username" если запрос был бы SELECT Username...
		// или просто не найдет пользователя если username не email
		return nil, fmt.Errorf("failed to get user by username (actually email) %s: %w", username, err)
	}
	user.Username = user.Email // Устанавливаем Username из Email
	return user, nil
}

// GetUserByEmail извлекает пользователя по email.
func GetUserByEmail(email string) (*models.User, error) {
	user := &models.User{}
	// Добавляем Username в SELECT
	query := `SELECT Id, Username, Email, DisplayName, PhotoUrl, PasswordHash, CreatedAt, UpdatedAt
	          FROM Users WHERE Email = ?`
	err := AuthDB.Get(user, query, email)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, nil // Пользователь не найден
		}
		return nil, fmt.Errorf("failed to get user by email %s: %w", email, err)
	}
	return user, nil
}

// GetUserByID извлекает пользователя по ID.
func GetUserByID(id int64) (*models.User, error) {
	user := &models.User{}
	// Добавляем Username в SELECT
	query := `SELECT Id, Username, Email, DisplayName, PhotoUrl, PasswordHash, CreatedAt, UpdatedAt
              FROM Users WHERE Id = ?`
	err := AuthDB.Get(user, query, id)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, nil // Пользователь не найден
		}
		return nil, fmt.Errorf("failed to get user by ID %d: %w", id, err)
	}
	return user, nil
}

// UpdateUserProfile обновляет displayName и photoUrl пользователя.
// Поле Username не обновляется, так как его нет в БД.
func UpdateUserProfile(userID int64, displayName string, photoUrl string) error {
	now := time.Now()
	query := `UPDATE Users SET DisplayName = ?, PhotoUrl = ?, UpdatedAt = ? 
	          WHERE Id = ?`
	result, err := AuthDB.Exec(query, displayName, photoUrl, now, userID)
	if err != nil {
		return fmt.Errorf("failed to update user profile for ID %d: %w", userID, err)
	}

	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return fmt.Errorf("failed to get rows affected for user profile update ID %d: %w", userID, err)
	}

	if rowsAffected == 0 {
		return fmt.Errorf("no user found with ID %d to update profile", userID)
	}

	return nil
}
