package models

// User представляет пользователя системы.
type User struct {
	ID           int64   `json:"id" db:"Id"`
	Username     string  `json:"username"`
	Email        string  `json:"email" db:"Email"`
	DisplayName  string  `json:"display_name" db:"DisplayName"`
	PhotoUrl     string  `json:"photo_url" db:"PhotoUrl"`
	PasswordHash string  `json:"password,omitempty" db:"PasswordHash"`
	CreatedAt    *string `json:"created_at,omitempty" db:"CreatedAt"`
	UpdatedAt    *string `json:"updated_at,omitempty" db:"UpdatedAt"`
	Token        string  `json:"token,omitempty"`
}
