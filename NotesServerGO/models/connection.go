package models

import "time"

// Connection представляет связь между двумя заметками.
type Connection struct {
	Id              int64     `json:"id" db:"Id"`
	FromNoteId      int64     `json:"from_note_id" db:"FromNoteId"` // ID заметки-источника
	ToNoteId        int64     `json:"to_note_id" db:"ToNoteId"`     // ID заметки-цели
	Name            string    `json:"name" db:"Name"`
	ConnectionColor int       `json:"connection_color" db:"ConnectionColor"` // ARGB int
	DatabaseId      int64     `json:"database_id" db:"DatabaseId"`
	CreatedAt       time.Time `json:"-" db:"CreatedAt"`
	UpdatedAt       time.Time `json:"-" db:"UpdatedAt"`
}
