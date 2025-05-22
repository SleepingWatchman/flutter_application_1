package models

// DatabaseEntity является базовой структурой для сущностей, связанных с определенной базой данных.
type DatabaseEntity struct {
	DatabaseID int `json:"database_id" db:"database_id"`
} 