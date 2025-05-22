package models

import "time"

// SharedDatabase представляет собой совместную базу данных.
type SharedDatabase struct {
	Id          int64     `json:"id" db:"Id"`
	Name        string    `json:"name" db:"Name"`
	OwnerUserId int64     `json:"owner_user_id" db:"OwnerUserId"` // Связь с Users.Id
	CreatedAt   time.Time `json:"created_at" db:"CreatedAt"`
	UpdatedAt   time.Time `json:"updated_at" db:"UpdatedAt"`
}

// SharedDatabaseUserRole определяет роль пользователя в совместной базе данных.
type SharedDatabaseUserRole string

const (
	RoleOwner  SharedDatabaseUserRole = "owner"
	RoleEditor SharedDatabaseUserRole = "editor"
	RoleViewer SharedDatabaseUserRole = "viewer"
)

// SharedDatabaseUser представляет связь пользователя с совместной базой данных и его роль.
type SharedDatabaseUser struct {
	SharedDatabaseId int64                  `json:"shared_database_id" db:"SharedDatabaseId"` // Связь с SharedDatabases.Id
	UserId           int64                  `json:"user_id" db:"UserId"`                      // Связь с Users.Id
	Role             SharedDatabaseUserRole `json:"role" db:"Role"`
	JoinedAt         time.Time              `json:"joined_at" db:"JoinedAt"`
}
