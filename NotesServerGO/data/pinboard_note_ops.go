package data

import (
	"database/sql"
	"fmt"
	"log"
	"time"

	"notes_server_go/models"

	"github.com/jmoiron/sqlx"
)

// CreatePinboardNote создает новую заметку на доске в указанной совместной БД.
// Поле note.DatabaseId должно быть установлено на ID совместной БД.
// Возвращает ID созданной заметки.
func CreatePinboardNote(note *models.PinboardNote) (int64, error) {
	now := time.Now()
	note.CreatedAt = now
	note.UpdatedAt = now

	query := `INSERT INTO PinboardNotes (DatabaseId, Title, Content, PositionX, PositionY, Width, Height, BackgroundColor, IconCodePoint, CreatedAt, UpdatedAt)
	          VALUES (:DatabaseId, :Title, :Content, :PositionX, :PositionY, :Width, :Height, :BackgroundColor, :IconCodePoint, :CreatedAt, :UpdatedAt)`

	result, err := MainDB.NamedExec(query, note)
	if err != nil {
		return 0, fmt.Errorf("CreatePinboardNote: ошибка вставки: %w", err)
	}
	id, err := result.LastInsertId()
	if err != nil {
		return 0, fmt.Errorf("CreatePinboardNote: ошибка получения LastInsertId: %w", err)
	}
	log.Printf("Создана PinboardNote с ID: %d для DatabaseId: %d", id, note.DatabaseId)
	return id, nil
}

// GetPinboardNoteByID извлекает заметку с доски по ее ID и ID совместной БД.
func GetPinboardNoteByID(id int64, sharedDbID int64) (*models.PinboardNote, error) {
	note := &models.PinboardNote{}
	query := `SELECT Id, DatabaseId, Title, Content, PositionX, PositionY, Width, Height, BackgroundColor, IconCodePoint, CreatedAt, UpdatedAt
	          FROM PinboardNotes WHERE Id = ? AND DatabaseId = ?`
	err := MainDB.Get(note, query, id, sharedDbID)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, nil // Не найдено
		}
		return nil, fmt.Errorf("GetPinboardNoteByID: ошибка получения ID %d, SharedDBID %d: %w", id, sharedDbID, err)
	}
	return note, nil
}

// GetAllPinboardNotesBySharedDBID извлекает все заметки с доски для указанной совместной БД.
func GetAllPinboardNotesBySharedDBID(sharedDbID int64) ([]models.PinboardNote, error) {
	var notes []models.PinboardNote
	query := `SELECT Id, DatabaseId, Title, Content, PositionX, PositionY, Width, Height, BackgroundColor, IconCodePoint, CreatedAt, UpdatedAt
              FROM PinboardNotes WHERE DatabaseId = ? ORDER BY UpdatedAt DESC`
	err := MainDB.Select(&notes, query, sharedDbID)
	if err != nil {
		return nil, fmt.Errorf("GetAllPinboardNotesBySharedDBID: ошибка получения всех для SharedDBID %d: %w", sharedDbID, err)
	}
	return notes, nil
}

// UpdatePinboardNote обновляет существующую заметку на доске в указанной совместной БД.
func UpdatePinboardNote(note *models.PinboardNote) error {
	note.UpdatedAt = time.Now()

	query := `UPDATE PinboardNotes SET 
	            Title = :Title, Content = :Content, PositionX = :PositionX, PositionY = :PositionY, 
	            Width = :Width, Height = :Height, BackgroundColor = :BackgroundColor, IconCodePoint = :IconCodePoint, UpdatedAt = :UpdatedAt
	          WHERE Id = :Id AND DatabaseId = :DatabaseId`
	result, err := MainDB.NamedExec(query, note)
	if err != nil {
		return fmt.Errorf("UpdatePinboardNote: ошибка обновления ID %d, SharedDBID %d: %w", note.Id, note.DatabaseId, err)
	}
	rowsAffected, _ := result.RowsAffected()
	if rowsAffected == 0 {
		return sql.ErrNoRows // Не найдено для обновления
	}
	log.Printf("Обновлена PinboardNote с ID: %d для DatabaseId: %d", note.Id, note.DatabaseId)
	return nil
}

// DeletePinboardNote удаляет заметку с доски по ее ID и ID совместной БД.
func DeletePinboardNote(id int64, sharedDbID int64) error {
	query := `DELETE FROM PinboardNotes WHERE Id = ? AND DatabaseId = ?`
	result, err := MainDB.Exec(query, id, sharedDbID)
	if err != nil {
		return fmt.Errorf("DeletePinboardNote: ошибка удаления ID %d, SharedDBID %d: %w", id, sharedDbID, err)
	}
	rowsAffected, _ := result.RowsAffected()
	if rowsAffected == 0 {
		return sql.ErrNoRows // Не найдено для удаления
	}
	log.Printf("Удалена PinboardNote с ID: %d для DatabaseId: %d", id, sharedDbID)
	return nil
}

// --- Функции, работающие с транзакциями ---

// CreatePinboardNoteWithTx создает новую заметку на доске в рамках транзакции.
func CreatePinboardNoteWithTx(tx *sqlx.Tx, note *models.PinboardNote) (int64, error) {
	now := time.Now()
	note.CreatedAt = now
	note.UpdatedAt = now

	query := `INSERT INTO PinboardNotes (DatabaseId, Title, Content, PositionX, PositionY, Width, Height, BackgroundColor, IconCodePoint, CreatedAt, UpdatedAt)
	          VALUES (:DatabaseId, :Title, :Content, :PositionX, :PositionY, :Width, :Height, :BackgroundColor, :IconCodePoint, :CreatedAt, :UpdatedAt)`
	result, err := tx.NamedExec(query, note)
	if err != nil {
		return 0, fmt.Errorf("CreatePinboardNoteWithTx: ошибка вставки: %w", err)
	}
	newID, err := result.LastInsertId()
	if err != nil {
		return 0, fmt.Errorf("CreatePinboardNoteWithTx: ошибка LastInsertId: %w", err)
	}
	return newID, nil
}

// GetPinboardNoteByIDWithTx извлекает заметку с доски по ID и ID совместной БД в рамках транзакции.
func GetPinboardNoteByIDWithTx(tx *sqlx.Tx, id int64, sharedDbID int64) (*models.PinboardNote, error) {
	note := &models.PinboardNote{}
	query := `SELECT Id, DatabaseId, Title, Content, PositionX, PositionY, Width, Height, BackgroundColor, IconCodePoint, CreatedAt, UpdatedAt
	          FROM PinboardNotes WHERE Id = ? AND DatabaseId = ?`
	err := tx.Get(note, query, id, sharedDbID)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, nil // Не найдено
		}
		return nil, fmt.Errorf("GetPinboardNoteByIDWithTx: ошибка получения ID %d, SharedDBID %d: %w", id, sharedDbID, err)
	}
	return note, nil
}

// GetAllPinboardNotesBySharedDBIDWithTx извлекает все заметки с доски для указанной совместной БД в рамках транзакции.
func GetAllPinboardNotesBySharedDBIDWithTx(tx *sqlx.Tx, sharedDbID int64) ([]models.PinboardNote, error) {
	var notes []models.PinboardNote
	query := `SELECT Id, DatabaseId, Title, Content, PositionX, PositionY, Width, Height, BackgroundColor, IconCodePoint, CreatedAt, UpdatedAt
	          FROM PinboardNotes WHERE DatabaseId = ? ORDER BY UpdatedAt DESC`
	err := tx.Select(&notes, query, sharedDbID)
	if err != nil {
		return nil, fmt.Errorf("GetAllPinboardNotesBySharedDBIDWithTx: ошибка получения для SharedDBID %d: %w", sharedDbID, err)
	}
	return notes, nil
}

// UpdatePinboardNoteWithTx обновляет существующую заметку на доске в рамках транзакции.
func UpdatePinboardNoteWithTx(tx *sqlx.Tx, note *models.PinboardNote) error {
	note.UpdatedAt = time.Now()
	query := `UPDATE PinboardNotes SET 
	            Title = :Title, Content = :Content, PositionX = :PositionX, PositionY = :PositionY, 
	            Width = :Width, Height = :Height, BackgroundColor = :BackgroundColor, IconCodePoint = :IconCodePoint, UpdatedAt = :UpdatedAt
	          WHERE Id = :Id AND DatabaseId = :DatabaseId`
	result, err := tx.NamedExec(query, note)
	if err != nil {
		return fmt.Errorf("UpdatePinboardNoteWithTx: ошибка обновления ID %d, SharedDBID %d: %w", note.Id, note.DatabaseId, err)
	}
	rowsAffected, _ := result.RowsAffected()
	if rowsAffected == 0 {
		return sql.ErrNoRows // Не найдено для обновления
	}
	return nil
}

// DeletePinboardNoteWithTx удаляет заметку с доски по ID и ID совместной БД в рамках транзакции.
func DeletePinboardNoteWithTx(tx *sqlx.Tx, id int64, sharedDbID int64) error {
	query := `DELETE FROM PinboardNotes WHERE Id = ? AND DatabaseId = ?`
	result, err := tx.Exec(query, id, sharedDbID)
	if err != nil {
		return fmt.Errorf("DeletePinboardNoteWithTx: ошибка удаления ID %d, SharedDBID %d: %w", id, sharedDbID, err)
	}
	rowsAffected, _ := result.RowsAffected()
	if rowsAffected == 0 {
		return sql.ErrNoRows // Не найдено
	}
	return nil
}

// GetAllPinboardNoteIDsForSharedDBWithTx извлекает все ID заметок с доски для указанной совместной БД в рамках транзакции.
func GetAllPinboardNoteIDsForSharedDBWithTx(tx *sqlx.Tx, sharedDbID int64) ([]int64, error) {
	var ids []int64
	query := `SELECT Id FROM PinboardNotes WHERE DatabaseId = ?`
	err := tx.Select(&ids, query, sharedDbID)
	if err != nil {
		if err == sql.ErrNoRows {
			return []int64{}, nil // Возвращаем пустой слайс, если ничего не найдено
		}
		return nil, fmt.Errorf("GetAllPinboardNoteIDsForSharedDBWithTx: ошибка при получении ID для SharedDBID %d: %w", sharedDbID, err)
	}
	return ids, nil
}

// GetPinboardNotesForDatabase извлекает все заметки с доски для указанной ID базы данных.
func GetPinboardNotesForDatabase(databaseID int64) ([]models.PinboardNote, error) {
	var notes []models.PinboardNote
	query := `SELECT Id, Title, Content, CreatedAt, UpdatedAt, DatabaseId, 
	                 PositionX, PositionY, Width, Height, BackgroundColor, IconCodePoint 
	          FROM PinboardNotes 
	          WHERE DatabaseId = ? 
	          ORDER BY CreatedAt ASC`
	err := MainDB.Select(&notes, query, databaseID)
	if err != nil {
		return nil, fmt.Errorf("ошибка получения заметок с доски для БД ID %d: %w", databaseID, err)
	}
	return notes, nil
}

// CheckPinboardNoteExistsWithTx проверяет существование PinboardNote по ID и ID совместной БД в рамках транзакции.
func CheckPinboardNoteExistsWithTx(tx *sqlx.Tx, id int64, sharedDbID int64) (bool, error) {
	var count int
	query := `SELECT COUNT(*) FROM PinboardNotes WHERE Id = ? AND DatabaseId = ?`
	err := tx.Get(&count, query, id, sharedDbID)
	if err != nil {
		return false, fmt.Errorf("CheckPinboardNoteExistsWithTx: ошибка проверки существования ID %d, SharedDBID %d: %w", id, sharedDbID, err)
	}
	return count > 0, nil
}
