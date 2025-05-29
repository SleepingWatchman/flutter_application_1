package models

import "time"

// NoteImage представляет изображение, прикрепленное к заметке.
type NoteImage struct {
	Id         int64     `json:"id,omitempty" db:"Id"`                  // Может отсутствовать для новых изображений в бэкапе
	NoteId     int64     `json:"note_id" db:"NoteId"`                   // ID заметки, к которой относится изображение
	ImagePath  string    `json:"-" db:"ImagePath"`                      // Путь к файлу на сервере (не приходит от клиента в бэкапе)
	FileName   string    `json:"file_name" db:"FileName"`               // Имя файла, которое клиент присылает и ожидает
	ImageData  string    `json:"image_data,omitempty" db:"-"`           // Base64 строка данных изображения (от клиента), не хранится в БД
	DatabaseId int64     `json:"database_id,omitempty" db:"DatabaseId"` // ID совместной БД, к которой относится NoteId
	CreatedAt  time.Time `json:"-" db:"CreatedAt"`                      // ИСПРАВЛЕНИЕ: убираю из JSON
	UpdatedAt  time.Time `json:"-" db:"UpdatedAt"`                      // ИСПРАВЛЕНИЕ: убираю из JSON
}
