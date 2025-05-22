package models

import "time"

// Folder представляет собой папку для заметок.
type Folder struct {
	ID         int64     `json:"id" db:"Id"`
	DatabaseID int64     `json:"database_id" db:"DatabaseId"`
	Name       string    `json:"name" db:"Name"`
	ParentID   *int64    `json:"parent_id,omitempty" db:"ParentId"`
	CreatedAt  time.Time `json:"created_at" db:"CreatedAt"`
	UpdatedAt  time.Time `json:"updated_at" db:"UpdatedAt"`
	Color      int       `json:"color" db:"Color"`
	IsExpanded bool      `json:"is_expanded" db:"IsExpanded"`
}
