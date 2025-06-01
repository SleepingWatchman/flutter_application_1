package models

import "time"

// SharedDatabase представляет собой совместную базу данных.
type SharedDatabase struct {
	Id          int64     `json:"id" db:"Id"`
	Name        string    `json:"name" db:"Name"`
	OwnerUserId int64     `json:"owner_user_id" db:"OwnerUserId"` // Связь с Users.Id
	CreatedAt   time.Time `json:"created_at" db:"CreatedAt"`
	UpdatedAt   time.Time `json:"updated_at" db:"UpdatedAt"`
	Version     string    `json:"version" db:"Version"`
	IsActive    bool      `json:"is_active" db:"IsActive"`
	LastSync    time.Time `json:"last_sync" db:"LastSync"`
}

// SharedDatabaseUserRole определяет роль пользователя в совместной базе данных.
type SharedDatabaseUserRole string

const (
	RoleOwner        SharedDatabaseUserRole = "owner"
	RoleCollaborator SharedDatabaseUserRole = "collaborator"
	// RoleEditor и RoleViewer удалены - теперь все участники имеют одинаковые права (collaborator)
	// Эти роли могут встречаться в старых данных и автоматически конвертируются в collaborator
)

// SharedDatabaseUser представляет связь пользователя с совместной базой данных и его роль.
type SharedDatabaseUser struct {
	SharedDatabaseId int64                  `json:"shared_database_id" db:"SharedDatabaseId"` // Связь с SharedDatabases.Id
	UserId           int64                  `json:"user_id" db:"UserId"`                      // Связь с Users.Id
	Role             SharedDatabaseUserRole `json:"role" db:"Role"`
	JoinedAt         time.Time              `json:"joined_at" db:"JoinedAt"`
}

// SharedDatabaseInvitation представляет приглашение в совместную базу данных
type SharedDatabaseInvitation struct {
	Id               int64                  `json:"id" db:"Id"`
	SharedDatabaseId int64                  `json:"shared_database_id" db:"SharedDatabaseId"`
	InviterUserId    int64                  `json:"inviter_user_id" db:"InviterUserId"`
	InviteeEmail     string                 `json:"invitee_email" db:"InviteeEmail"`
	Role             SharedDatabaseUserRole `json:"role" db:"Role"`
	Status           string                 `json:"status" db:"Status"` // pending, accepted, declined
	CreatedAt        time.Time              `json:"created_at" db:"CreatedAt"`
	ExpiresAt        time.Time              `json:"expires_at" db:"ExpiresAt"`
}

// SyncChange представляет изменение для синхронизации
type SyncChange struct {
	Id         int64     `json:"id" db:"Id"`
	DatabaseId int64     `json:"database_id" db:"DatabaseId"`
	EntityType string    `json:"entity_type" db:"EntityType"` // note, folder, schedule_entry, etc.
	EntityId   int64     `json:"entity_id" db:"EntityId"`
	Operation  string    `json:"operation" db:"Operation"` // create, update, delete
	Data       string    `json:"data" db:"Data"`           // JSON данные
	UserId     int64     `json:"user_id" db:"UserId"`
	CreatedAt  time.Time `json:"created_at" db:"CreatedAt"`
	Version    string    `json:"version" db:"Version"`
}

// EnhancedSharedDatabaseWithUsers расширенная структура с пользователями и метаданными
type EnhancedSharedDatabaseWithUsers struct {
	SharedDatabase
	Users          []SharedDatabaseUserWithDetails `json:"users"`
	PendingChanges int                             `json:"pending_changes"`
	IsOnline       bool                            `json:"is_online"`
	LastSyncTime   *time.Time                      `json:"last_sync_time"`
	Metadata       map[string]interface{}          `json:"metadata"`
}

// SharedDatabaseUserWithDetails пользователь с полными данными
type SharedDatabaseUserWithDetails struct {
	SharedDatabaseUser
	Email       string  `json:"email" db:"Email"`
	DisplayName *string `json:"display_name" db:"DisplayName"`
	PhotoURL    *string `json:"photo_url" db:"PhotoURL"`
}
