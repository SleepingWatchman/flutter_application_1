package data

import (
	"database/sql"
	"fmt"
	"log"
	"time"

	"notes_server_go/models"

	"github.com/jmoiron/sqlx"
)

// CreateScheduleEntry создает новую запись расписания в указанной совместной БД.
// Поле entry.DatabaseId должно быть установлено.
// Возвращает ID созданной записи.
func CreateScheduleEntry(entry *models.ScheduleEntry) (int64, error) {
	now := time.Now()
	entry.CreatedAt = now
	entry.UpdatedAt = now

	query := `INSERT INTO ScheduleEntries (DatabaseId, Time, Date, Note, DynamicFieldsJson, RecurrenceJson, CreatedAt, UpdatedAt)
	          VALUES (:DatabaseId, :Time, :Date, :Note, :DynamicFieldsJson, :RecurrenceJson, :CreatedAt, :UpdatedAt)`

	result, err := MainDB.NamedExec(query, entry)
	if err != nil {
		return 0, fmt.Errorf("CreateScheduleEntry: ошибка при вставке записи: %w", err)
	}

	newID, err := result.LastInsertId()
	if err != nil {
		return 0, fmt.Errorf("CreateScheduleEntry: ошибка при получении LastInsertId: %w", err)
	}
	log.Printf("Создана запись ScheduleEntry с ID: %d для DatabaseId: %d", newID, entry.DatabaseId)
	return newID, nil
}

// GetScheduleEntryByID извлекает запись расписания по ее ID и ID совместной БД.
func GetScheduleEntryByID(id int64, sharedDbID int64) (*models.ScheduleEntry, error) {
	entry := &models.ScheduleEntry{}
	query := `SELECT Id, DatabaseId, Time, Date, Note, DynamicFieldsJson, RecurrenceJson, CreatedAt, UpdatedAt
	          FROM ScheduleEntries WHERE Id = ? AND DatabaseId = ?`
	err := MainDB.Get(entry, query, id, sharedDbID)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, nil // Не найдено
		}
		return nil, fmt.Errorf("GetScheduleEntryByID: ошибка при получении записи ID %d, DBID %d: %w", id, sharedDbID, err)
	}
	return entry, nil
}

// UpdateScheduleEntry обновляет существующую запись расписания.
// Поиск осуществляется по entry.Id и entry.DatabaseId.
func UpdateScheduleEntry(entry *models.ScheduleEntry) error {
	entry.UpdatedAt = time.Now()

	query := `UPDATE ScheduleEntries SET 
			  Time = :Time, Date = :Date, Note = :Note, DynamicFieldsJson = :DynamicFieldsJson, 
			  RecurrenceJson = :RecurrenceJson, UpdatedAt = :UpdatedAt
	          WHERE Id = :Id AND DatabaseId = :DatabaseId`

	result, err := MainDB.NamedExec(query, entry)
	if err != nil {
		return fmt.Errorf("UpdateScheduleEntry: ошибка при обновлении записи ID %d, DBID %d: %w", entry.Id, entry.DatabaseId, err)
	}
	rowsAffected, _ := result.RowsAffected()
	if rowsAffected == 0 {
		log.Printf("UpdateScheduleEntry: Запись с ID %d для DatabaseId %d не найдена для обновления.", entry.Id, entry.DatabaseId)
		return sql.ErrNoRows // или nil, если "не найдено для обновления" это не ошибка
	}
	log.Printf("Обновлена запись ScheduleEntry с ID: %d для DatabaseId: %d", entry.Id, entry.DatabaseId)
	return nil
}

// GetScheduleEntriesByDBID извлекает все записи расписания для указанной совместной БД.
func GetScheduleEntriesByDBID(sharedDbID int64) ([]models.ScheduleEntry, error) {
	var entries []models.ScheduleEntry
	query := `SELECT Id, DatabaseId, Time, Date, Note, DynamicFieldsJson, RecurrenceJson, CreatedAt, UpdatedAt
	          FROM ScheduleEntries WHERE DatabaseId = ? ORDER BY Id ASC`
	err := MainDB.Select(&entries, query, sharedDbID)
	if err != nil {
		return nil, fmt.Errorf("GetScheduleEntriesByDBID: ошибка при получении записей для DBID %d: %w", sharedDbID, err)
	}
	return entries, nil
}

// DeleteScheduleEntry удаляет запись расписания по ID и ID совместной БД.
// (Эта функция может понадобиться, если клиент явно помечает записи к удалению)
func DeleteScheduleEntry(id int64, sharedDbID int64, ownerUserID int64) error {
	query := `DELETE FROM ScheduleEntries WHERE Id = ? AND DatabaseId = ?`
	result, err := MainDB.Exec(query, id, sharedDbID)
	if err != nil {
		return fmt.Errorf("DeleteScheduleEntry: ошибка при удалении записи ID %d, DBID %d: %w", id, sharedDbID, err)
	}
	rowsAffected, _ := result.RowsAffected()
	if rowsAffected == 0 {
		log.Printf("DeleteScheduleEntry: Запись с ID %d для DatabaseId %d не найдена для удаления.", id, sharedDbID)
		return sql.ErrNoRows // Не найдено
	}
	log.Printf("Удалена запись ScheduleEntry с ID: %d для DatabaseId: %d", id, sharedDbID)
	return nil
}

// --- Функции, работающие с транзакциями ---

// CreateScheduleEntryWithTx создает новую запись расписания в рамках транзакции.
func CreateScheduleEntryWithTx(tx *sqlx.Tx, entry *models.ScheduleEntry) (int64, error) {
	now := time.Now()
	entry.CreatedAt = now
	entry.UpdatedAt = now

	query := `INSERT INTO ScheduleEntries (DatabaseId, Time, Date, Note, DynamicFieldsJson, RecurrenceJson, CreatedAt, UpdatedAt)
	          VALUES (:DatabaseId, :Time, :Date, :Note, :DynamicFieldsJson, :RecurrenceJson, :CreatedAt, :UpdatedAt)`

	result, err := tx.NamedExec(query, entry)
	if err != nil {
		return 0, fmt.Errorf("CreateScheduleEntryWithTx: ошибка при вставке: %w", err)
	}
	newID, err := result.LastInsertId()
	if err != nil {
		return 0, fmt.Errorf("CreateScheduleEntryWithTx: ошибка LastInsertId: %w", err)
	}
	return newID, nil
}

// GetScheduleEntryByIDWithTx извлекает запись расписания по ID и ID совместной БД в рамках транзакции.
func GetScheduleEntryByIDWithTx(tx *sqlx.Tx, id int64, sharedDbID int64) (*models.ScheduleEntry, error) {
	entry := &models.ScheduleEntry{}
	query := `SELECT Id, DatabaseId, Time, Date, Note, DynamicFieldsJson, RecurrenceJson, CreatedAt, UpdatedAt
	          FROM ScheduleEntries WHERE Id = ? AND DatabaseId = ?`
	err := tx.Get(entry, query, id, sharedDbID)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, nil // Не найдено
		}
		return nil, fmt.Errorf("GetScheduleEntryByIDWithTx: ошибка при получении ID %d, DBID %d: %w", id, sharedDbID, err)
	}
	return entry, nil
}

// UpdateScheduleEntryWithTx обновляет существующую запись расписания в рамках транзакции.
func UpdateScheduleEntryWithTx(tx *sqlx.Tx, entry *models.ScheduleEntry) error {
	entry.UpdatedAt = time.Now()

	query := `UPDATE ScheduleEntries SET 
			  Time = :Time, Date = :Date, Note = :Note, DynamicFieldsJson = :DynamicFieldsJson, 
			  RecurrenceJson = :RecurrenceJson, UpdatedAt = :UpdatedAt
	          WHERE Id = :Id AND DatabaseId = :DatabaseId`
	result, err := tx.NamedExec(query, entry)
	if err != nil {
		return fmt.Errorf("UpdateScheduleEntryWithTx: ошибка при обновлении ID %d, DBID %d: %w", entry.Id, entry.DatabaseId, err)
	}
	rowsAffected, _ := result.RowsAffected()
	if rowsAffected == 0 {
		return sql.ErrNoRows // Не найдено для обновления
	}
	return nil
}

// GetScheduleEntriesByDBIDWithTx извлекает все записи расписания для указанной совместной БД в рамках транзакции.
func GetScheduleEntriesByDBIDWithTx(tx *sqlx.Tx, sharedDbID int64) ([]models.ScheduleEntry, error) {
	var entries []models.ScheduleEntry
	query := `SELECT Id, DatabaseId, Time, Date, Note, DynamicFieldsJson, RecurrenceJson, CreatedAt, UpdatedAt
	          FROM ScheduleEntries WHERE DatabaseId = ? ORDER BY Id ASC`
	err := tx.Select(&entries, query, sharedDbID)
	if err != nil {
		return nil, fmt.Errorf("GetScheduleEntriesByDBIDWithTx: ошибка при получении для DBID %d: %w", sharedDbID, err)
	}
	return entries, nil
}

// DeleteScheduleEntryWithTx удаляет запись расписания по ID и ID совместной БД в рамках транзакции.
func DeleteScheduleEntryWithTx(tx *sqlx.Tx, id int64, sharedDbID int64, ownerUserID int64) error {
	query := `DELETE FROM ScheduleEntries WHERE Id = ? AND DatabaseId = ?`
	result, err := tx.Exec(query, id, sharedDbID)
	if err != nil {
		return fmt.Errorf("DeleteScheduleEntryWithTx: ошибка при удалении ID %d, DBID %d: %w", id, sharedDbID, err)
	}
	rowsAffected, _ := result.RowsAffected()
	if rowsAffected == 0 {
		return sql.ErrNoRows // Не найдено
	}
	return nil
}

// GetAllScheduleEntryIDsForDBWithTx извлекает все ID записей расписания для указанной совместной БД в рамках транзакции.
func GetAllScheduleEntryIDsForDBWithTx(tx *sqlx.Tx, sharedDbID int64) ([]int64, error) {
	var ids []int64
	query := `SELECT Id FROM ScheduleEntries WHERE DatabaseId = ?`
	err := tx.Select(&ids, query, sharedDbID)
	if err != nil {
		if err == sql.ErrNoRows {
			return []int64{}, nil // Возвращаем пустой слайс, если ничего не найдено
		}
		return nil, fmt.Errorf("GetAllScheduleEntryIDsForDBWithTx: ошибка при получении ID для DBID %d: %w", sharedDbID, err)
	}
	return ids, nil
}

// GetScheduleEntriesForDatabase извлекает все записи расписания для указанной ID базы данных.
func GetScheduleEntriesForDatabase(databaseID int64) ([]models.ScheduleEntry, error) {
	var entries []models.ScheduleEntry
	query := `SELECT Id, DatabaseId, Time, Date, Note, DynamicFieldsJson, RecurrenceJson, CreatedAt, UpdatedAt 
	          FROM ScheduleEntries 
	          WHERE DatabaseId = ? 
	          ORDER BY Id ASC`
	err := MainDB.Select(&entries, query, databaseID)
	if err != nil {
		return nil, fmt.Errorf("ошибка получения записей расписания для БД ID %d: %w", databaseID, err)
	}
	return entries, nil
}
