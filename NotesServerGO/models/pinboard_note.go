package models

import "time"

// PinboardNote представляет заметку на доске.
type PinboardNote struct {
	Id              int64     `json:"id" db:"Id"`
	Title           string    `json:"title" db:"Title"`
	Content         string    `json:"content" db:"Content"`
	PositionX       float64   `json:"position_x" db:"PositionX"`
	PositionY       float64   `json:"position_y" db:"PositionY"`
	Width           float64   `json:"width" db:"Width"`
	Height          float64   `json:"height" db:"Height"`
	BackgroundColor int       `json:"background_color" db:"BackgroundColor"` // ARGB int
	IconCodePoint   int       `json:"icon" db:"IconCodePoint"`               // Храним CodePoint иконки из Flutter (map['icon'])
	DatabaseId      int64     `json:"database_id" db:"DatabaseId"`
	CreatedAt       time.Time `json:"-" db:"CreatedAt"`
	UpdatedAt       time.Time `json:"-" db:"UpdatedAt"`
}
