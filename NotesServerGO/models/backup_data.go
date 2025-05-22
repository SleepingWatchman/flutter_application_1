package models

import "time"

// BackupData представляет полную резервную копию данных одной базы.
// Эта структура используется для передачи данных между клиентом и сервером.
// Важно, чтобы поля JSON соответствовали тому, что ожидает клиент.
type BackupData struct {
	Folders         []Folder        `json:"folders"`
	Notes           []Note          `json:"notes"`
	ScheduleEntries []ScheduleEntry `json:"scheduleEntries"`
	PinboardNotes   []PinboardNote  `json:"pinboardNotes"`
	Connections     []Connection    `json:"connections"`
	NoteImages      []NoteImage     `json:"images"` // Изменено с "note_images" на "images" для соответствия клиенту
	DatabaseId      string          `json:"databaseId,omitempty"`
	UserId          string          `json:"userId,omitempty"` // Может использоваться для идентификации владельца бэкапа
	LastModified    time.Time       `json:"lastModified"`
	CreatedAt       time.Time       `json:"createdAt"`
}
