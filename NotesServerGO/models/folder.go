package models

import (
	"encoding/json"
	"time"
)

// BoolFromInt - custom type для обработки bool значений из JSON как чисел или булев
type BoolFromInt bool

// UnmarshalJSON реализует custom unmarshaling для BoolFromInt
func (b *BoolFromInt) UnmarshalJSON(data []byte) error {
	var value interface{}
	if err := json.Unmarshal(data, &value); err != nil {
		return err
	}

	switch v := value.(type) {
	case bool:
		*b = BoolFromInt(v)
	case float64:
		*b = BoolFromInt(v != 0)
	case int:
		*b = BoolFromInt(v != 0)
	case int64:
		*b = BoolFromInt(v != 0)
	case string:
		*b = BoolFromInt(v == "true" || v == "1")
	default:
		*b = false
	}

	return nil
}

// MarshalJSON реализует custom marshaling для BoolFromInt
func (b BoolFromInt) MarshalJSON() ([]byte, error) {
	return json.Marshal(bool(b))
}

// Folder представляет собой папку для заметок.
type Folder struct {
	ID         int64       `json:"id" db:"Id"`
	DatabaseID int64       `json:"database_id" db:"DatabaseId"`
	Name       string      `json:"name" db:"Name"`
	ParentID   *int64      `json:"parent_id,omitempty" db:"ParentId"`
	CreatedAt  time.Time   `json:"created_at" db:"CreatedAt"`
	UpdatedAt  time.Time   `json:"updated_at" db:"UpdatedAt"`
	Color      int         `json:"color" db:"Color"`
	IsExpanded BoolFromInt `json:"is_expanded" db:"IsExpanded"`
}
