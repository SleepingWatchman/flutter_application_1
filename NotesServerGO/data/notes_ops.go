package data

import (
	"database/sql"
	"fmt"
	"log"
	"time"

	"notes_server_go/models"

	"github.com/jmoiron/sqlx"
	_ "github.com/mattn/go-sqlite3" // Используется DB драйвером
)

// CreateNote создает новую заметку в указанной совместной БД.
// Поле note.DatabaseId должно быть установлено на ID совместной БД.
// Возвращает ID созданной заметки.
func CreateNote(note *models.Note) (int64, error) {
	if err := note.UpdateJsonProperties(); err != nil {
		return 0, fmt.Errorf("CreateNote: ошибка обновления JSON свойств: %w", err)
	}
	now := time.Now()
	note.CreatedAt = now
	note.UpdatedAt = now

	// DatabaseId устанавливается перед вызовом этой функции
	query := `INSERT INTO Notes (DatabaseId, Title, Content, FolderId, CreatedAt, UpdatedAt, ImagesJson, MetadataJson, ContentJson)
	          VALUES (:DatabaseId, :Title, :Content, :FolderId, :CreatedAt, :UpdatedAt, :ImagesJson, :MetadataJson, :ContentJson)`

	result, err := MainDB.NamedExec(query, note)
	if err != nil {
		return 0, fmt.Errorf("CreateNote: ошибка вставки заметки: %w", err)
	}
	id, err := result.LastInsertId()
	if err != nil {
		return 0, fmt.Errorf("CreateNote: ошибка получения LastInsertId: %w", err)
	}
	log.Printf("Создана заметка с ID: %d для DatabaseId: %d", id, note.DatabaseID)
	return id, nil
}

// GetNoteByID извлекает заметку по ее ID и ID совместной БД.
func GetNoteByID(id int64, sharedDbID int64) (*models.Note, error) {
	note := &models.Note{}
	query := `SELECT Id, DatabaseId, Title, Content, FolderId, CreatedAt, UpdatedAt, ImagesJson, MetadataJson, ContentJson
	          FROM Notes WHERE Id = ? AND DatabaseId = ?`
	err := MainDB.Get(note, query, id, sharedDbID)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, nil // Не найдено
		}
		return nil, fmt.Errorf("GetNoteByID: ошибка получения заметки ID %d, SharedDBID %d: %w", id, sharedDbID, err)
	}
	if err := note.LoadJsonProperties(); err != nil {
		return nil, fmt.Errorf("GetNoteByID: ошибка загрузки JSON свойств для заметки ID %d: %w", id, err)
	}
	return note, nil
}

// GetAllNotesBySharedDBID извлекает все заметки для указанной совместной БД.
func GetAllNotesBySharedDBID(sharedDbID int64) ([]models.Note, error) {
	var notes []models.Note
	query := `SELECT Id, DatabaseId, Title, Content, FolderId, CreatedAt, UpdatedAt, ImagesJson, MetadataJson, ContentJson
              FROM Notes WHERE DatabaseId = ? ORDER BY UpdatedAt DESC`
	err := MainDB.Select(&notes, query, sharedDbID)
	if err != nil {
		return nil, fmt.Errorf("GetAllNotesBySharedDBID: ошибка получения всех заметок для SharedDBID %d: %w", sharedDbID, err)
	}
	for i := range notes {
		if err := notes[i].LoadJsonProperties(); err != nil {
			log.Printf("GetAllNotesBySharedDBID: ошибка загрузки JSON свойств для заметки ID %d: %v. Заметка будет возвращена без этих свойств.", notes[i].ID, err)
		}
	}
	return notes, nil
}

// UpdateNote обновляет существующую заметку в указанной совместной БД.
// Поля note.Id и note.DatabaseId (ID совместной БД) должны быть установлены.
func UpdateNote(note *models.Note) error {
	if err := note.UpdateJsonProperties(); err != nil {
		return fmt.Errorf("UpdateNote: ошибка обновления JSON свойств для заметки ID %d: %w", note.ID, err)
	}
	note.UpdatedAt = time.Now()

	query := `UPDATE Notes SET
	            Title = :Title, Content = :Content, FolderId = :FolderId, UpdatedAt = :UpdatedAt,
	            ImagesJson = :ImagesJson, MetadataJson = :MetadataJson, ContentJson = :ContentJson
	          WHERE Id = :Id AND DatabaseId = :DatabaseId`
	result, err := MainDB.NamedExec(query, note)
	if err != nil {
		return fmt.Errorf("UpdateNote: ошибка обновления заметки ID %d, SharedDBID %d: %w", note.ID, note.DatabaseID, err)
	}
	rowsAffected, _ := result.RowsAffected()
	if rowsAffected == 0 {
		return sql.ErrNoRows // Не найдено для обновления
	}
	log.Printf("Обновлена заметка с ID: %d для DatabaseId: %d", note.ID, note.DatabaseID)
	return nil
}

// DeleteNote удаляет заметку по ее ID и ID совместной БД.
func DeleteNote(id int64, sharedDbID int64) error {
	query := `DELETE FROM Notes WHERE Id = ? AND DatabaseId = ?`
	result, err := MainDB.Exec(query, id, sharedDbID)
	if err != nil {
		return fmt.Errorf("DeleteNote: ошибка удаления заметки ID %d, SharedDBID %d: %w", id, sharedDbID, err)
	}
	rowsAffected, _ := result.RowsAffected()
	if rowsAffected == 0 {
		return sql.ErrNoRows // Не найдено для удаления
	}
	log.Printf("Удалена заметка с ID: %d для DatabaseId: %d", id, sharedDbID)
	return nil
}

// --- Функции, работающие с транзакциями ---

// CreateNoteWithTx создает новую заметку в рамках транзакции.
// Поле note.DatabaseId должно быть установлено на ID совместной БД.
func CreateNoteWithTx(tx *sqlx.Tx, note *models.Note) (int64, error) {
	if err := note.UpdateJsonProperties(); err != nil {
		return 0, fmt.Errorf("CreateNoteWithTx: ошибка обновления JSON свойств: %w", err)
	}
	now := time.Now()
	note.CreatedAt = now
	note.UpdatedAt = now

	query := `INSERT INTO Notes (DatabaseId, Title, Content, FolderId, CreatedAt, UpdatedAt, ImagesJson, MetadataJson, ContentJson)
	          VALUES (:DatabaseId, :Title, :Content, :FolderId, :CreatedAt, :UpdatedAt, :ImagesJson, :MetadataJson, :ContentJson)`
	result, err := tx.NamedExec(query, note)
	if err != nil {
		return 0, fmt.Errorf("CreateNoteWithTx: ошибка вставки: %w", err)
	}
	newID, err := result.LastInsertId()
	if err != nil {
		return 0, fmt.Errorf("CreateNoteWithTx: ошибка LastInsertId: %w", err)
	}
	return newID, nil
}

// GetNoteByIDWithTx извлекает заметку по ID и ID совместной БД в рамках транзакции.
func GetNoteByIDWithTx(tx *sqlx.Tx, id int64, sharedDbID int64) (*models.Note, error) {
	note := &models.Note{}
	query := `SELECT Id, DatabaseId, Title, Content, FolderId, CreatedAt, UpdatedAt, ImagesJson, MetadataJson, ContentJson
	          FROM Notes WHERE Id = ? AND DatabaseId = ?`
	err := tx.Get(note, query, id, sharedDbID)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, nil // Не найдено
		}
		return nil, fmt.Errorf("GetNoteByIDWithTx: ошибка получения ID %d, SharedDBID %d: %w", id, sharedDbID, err)
	}
	if err := note.LoadJsonProperties(); err != nil {
		return nil, fmt.Errorf("GetNoteByIDWithTx: ошибка загрузки JSON свойств для ID %d: %w", id, err)
	}
	return note, nil
}

// GetAllNotesBySharedDBIDWithTx извлекает все заметки для указанной совместной БД в рамках транзакции.
func GetAllNotesBySharedDBIDWithTx(tx *sqlx.Tx, sharedDbID int64) ([]models.Note, error) {
	var notes []models.Note
	query := `SELECT Id, DatabaseId, Title, Content, FolderId, CreatedAt, UpdatedAt, ImagesJson, MetadataJson, ContentJson
	          FROM Notes WHERE DatabaseId = ? ORDER BY UpdatedAt DESC`
	err := tx.Select(&notes, query, sharedDbID)
	if err != nil {
		return nil, fmt.Errorf("GetAllNotesBySharedDBIDWithTx: ошибка получения для SharedDBID %d: %w", sharedDbID, err)
	}
	for i := range notes {
		if err := notes[i].LoadJsonProperties(); err != nil {
			log.Printf("GetAllNotesBySharedDBIDWithTx: ошибка загрузки JSON свойств для заметки ID %d: %v. Заметка будет возвращена.", notes[i].ID, err)
		}
	}
	return notes, nil
}

// UpdateNoteWithTx обновляет существующую заметку в рамках транзакции.
// Поля note.Id и note.DatabaseId (ID совместной БД) должны быть установлены.
func UpdateNoteWithTx(tx *sqlx.Tx, note *models.Note) error {
	if err := note.UpdateJsonProperties(); err != nil {
		return fmt.Errorf("UpdateNoteWithTx: ошибка обновления JSON свойств для заметки ID %d: %w", note.ID, err)
	}
	note.UpdatedAt = time.Now()

	query := `UPDATE Notes SET
	            Title = :Title, Content = :Content, FolderId = :FolderId, UpdatedAt = :UpdatedAt,
	            ImagesJson = :ImagesJson, MetadataJson = :MetadataJson, ContentJson = :ContentJson
	          WHERE Id = :Id AND DatabaseId = :DatabaseId`
	result, err := tx.NamedExec(query, note)
	if err != nil {
		return fmt.Errorf("UpdateNoteWithTx: ошибка обновления ID %d, SharedDBID %d: %w", note.ID, note.DatabaseID, err)
	}
	rowsAffected, _ := result.RowsAffected()
	if rowsAffected == 0 {
		return sql.ErrNoRows // Не найдено для обновления
	}
	return nil
}

// DeleteNoteWithTx удаляет заметку по ID и ID совместной БД в рамках транзакции.
func DeleteNoteWithTx(tx *sqlx.Tx, id int64, sharedDbID int64) error {
	query := `DELETE FROM Notes WHERE Id = ? AND DatabaseId = ?`
	result, err := tx.Exec(query, id, sharedDbID)
	if err != nil {
		return fmt.Errorf("DeleteNoteWithTx: ошибка удаления ID %d, SharedDBID %d: %w", id, sharedDbID, err)
	}
	rowsAffected, _ := result.RowsAffected()
	if rowsAffected == 0 {
		return sql.ErrNoRows // Не найдено
	}
	return nil
}

// GetAllNoteIDsForSharedDBWithTx извлекает все ID заметок для указанной совместной БД в рамках транзакции.
func GetAllNoteIDsForSharedDBWithTx(tx *sqlx.Tx, sharedDbID int64) ([]int64, error) {
	var ids []int64
	query := `SELECT Id FROM Notes WHERE DatabaseId = ?`
	err := tx.Select(&ids, query, sharedDbID)
	if err != nil {
		if err == sql.ErrNoRows {
			return []int64{}, nil // Возвращаем пустой слайс, если ничего не найдено
		}
		return nil, fmt.Errorf("GetAllNoteIDsForSharedDBWithTx: ошибка при получении ID для SharedDBID %d: %w", sharedDbID, err)
	}
	return ids, nil
}

// GetNotesForDatabase извлекает все заметки для указанной ID базы данных.
func GetNotesForDatabase(databaseID int64) ([]models.Note, error) {
	var notes []models.Note
	// Аналогично GetFoldersForDatabase, для экспорта совместной БД (databaseID != 0)
	// нам нужны все ее заметки, независимо от OwnerUserId в таблице Notes.
	query := `SELECT Id, Title, Content, CreatedAt, UpdatedAt, FolderId, DatabaseId, ImagesJson, MetadataJson, ContentJson 
	          FROM Notes 
	          WHERE DatabaseId = ? 
	          ORDER BY UpdatedAt DESC`
	err := MainDB.Select(&notes, query, databaseID)
	if err != nil {
		return nil, fmt.Errorf("ошибка получения заметок для БД ID %d: %w", databaseID, err)
	}

	// Загружаем JSON свойства для каждой заметки
	for i := range notes {
		if err := notes[i].LoadJsonProperties(); err != nil {
			log.Printf("GetNotesForDatabase: ошибка загрузки JSON свойств для заметки ID %d: %v", notes[i].ID, err)
		}
	}

	return notes, nil
}
