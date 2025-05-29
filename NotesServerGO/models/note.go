package models

import (
	"encoding/json"
	"time"
)

// Note представляет собой заметку в системе.
type Note struct {
	// DatabaseEntity // Пока уберем, если DatabaseID будет явным полем
	ID           int64     `json:"id" db:"Id"`
	DatabaseID   int64     `json:"database_id" db:"DatabaseId"`
	Title        string    `json:"title" db:"Title"`
	Content      *string   `json:"content,omitempty" db:"Content"`
	FolderID     *int64    `json:"folder_id,omitempty" db:"FolderId"` // omitempty, если папки нет
	CreatedAt    time.Time `json:"-" db:"CreatedAt"`
	UpdatedAt    time.Time `json:"-" db:"UpdatedAt"`
	ImagesJson   string    `json:"images,omitempty" db:"ImagesJson"`
	MetadataJson string    `json:"metadata,omitempty" db:"MetadataJson"`
	ContentJson  *string   `json:"content_json,omitempty" db:"ContentJson"`

	Images   []string          `json:"-" db:"-"`
	Metadata map[string]string `json:"-" db:"-"`
	Folder   *Folder           `json:"folder,omitempty" db:"-"`
}

// UpdateJsonProperties сериализует Images и Metadata в JSON строки.
func (n *Note) UpdateJsonProperties() error {
	imgBytes, err := json.Marshal(n.Images)
	if err != nil {
		return err
	}
	n.ImagesJson = string(imgBytes)

	metaBytes, err := json.Marshal(n.Metadata)
	if err != nil {
		return err
	}
	n.MetadataJson = string(metaBytes)
	return nil
}

// LoadJsonProperties десериализует ImagesJson и MetadataJson в соответствующие поля.
func (n *Note) LoadJsonProperties() error {
	if n.ImagesJson == "" {
		n.ImagesJson = "[]"
	}
	if err := json.Unmarshal([]byte(n.ImagesJson), &n.Images); err != nil {
		n.Images = []string{}
	}

	if n.MetadataJson == "" {
		n.MetadataJson = "{}"
	}
	if err := json.Unmarshal([]byte(n.MetadataJson), &n.Metadata); err != nil {
		n.Metadata = make(map[string]string)
	}
	return nil
}

// NullableString представляет строку, которая может быть NULL в базе данных.
// Это может быть полезно, если мы решим использовать sql.NullString вместо *string.
// type NullableString sql.NullString

// Scan реализует интерфейс sql.Scanner для NullableString.
// func (ns *NullableString) Scan(value interface{}) error {
// 	return (*sql.NullString)(ns).Scan(value)
// }

// Value реализует интерфейс driver.Valuer для NullableString.
// func (ns NullableString) Value() (driver.Value, error) {
// 	return sql.NullString(ns).Value()
// }

// Определения Folder и DatabaseEntity удалены, т.к. вызвали ошибку переопределения
