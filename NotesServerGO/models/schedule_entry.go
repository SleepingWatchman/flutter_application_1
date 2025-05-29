package models

import "time"

// ScheduleEntry представляет запись в расписании.
type ScheduleEntry struct {
	Id                int64   `json:"id" db:"Id"`
	Time              string  `json:"time" db:"Time"` // "HH:mm"
	Date              string  `json:"date" db:"Date"` // "yyyy-MM-dd"
	Note              *string `json:"note,omitempty" db:"Note"`
	DynamicFieldsJson *string `json:"dynamic_fields_json,omitempty" db:"DynamicFieldsJson"`
	RecurrenceJson    *string `json:"recurrence_json,omitempty" db:"RecurrenceJson"` // Клиент присылает это поле
	DatabaseId        int64   `json:"database_id" db:"DatabaseId"`                   // На клиенте String?, здесь int64
	// OwnerUserId    int64     `json:"owner_user_id,omitempty" db:"OwnerUserId"` // Убрано, т.к. нет в клиентской модели ScheduleEntry
	CreatedAt time.Time `json:"-" db:"CreatedAt"`
	UpdatedAt time.Time `json:"-" db:"UpdatedAt"`
}

// RecurrenceType определяет тип повторения для пунктов расписания.
// Эти константы соответствуют RecurrenceType enum из Flutter-приложения.
// Используется для информации, на сервере хранится как часть RecurrenceJson.
// const (
// 	RecurrenceTypeNone    = 0
// 	RecurrenceTypeDaily   = 1
// 	RecurrenceTypeWeekly  = 2
// 	RecurrenceTypeMonthly = 3
// 	RecurrenceTypeYearly  = 4
// )

// Recurrence (вспомогательная структура, если понадобится на сервере для десериализации RecurrenceJson).
// На данный момент сервер просто хранит и передает RecurrenceJson как строку.
// type Recurrence struct {
// 	Type      int     `json:"type"` // Соответствует RecurrenceType* константам
// 	Interval  *int    `json:"interval,omitempty"`
// 	EndDate   *string `json:"endDate,omitempty"` // "yyyy-MM-ddTHH:mm:ssZ" (ISO8601) или просто "yyyy-MM-dd"
// 	Count     *int    `json:"count,omitempty"`
// }
