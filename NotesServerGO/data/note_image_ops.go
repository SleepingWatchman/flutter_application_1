package data

import (
	"database/sql"
	"fmt"
	"log"
	"time"

	"notes_server_go/models"

	"github.com/jmoiron/sqlx"
)

// CreateNoteImage создает новую запись об изображении заметки в указанной совместной БД.
// Поле image.DatabaseId должно быть установлено на ID совместной БД.
// Поле image.ImagePath должно содержать путь к файлу на сервере.
// Возвращает ID созданной записи.
func CreateNoteImage(image *models.NoteImage) (int64, error) {
	now := time.Now()
	image.CreatedAt = now
	image.UpdatedAt = now

	query := `INSERT INTO NoteImages (DatabaseId, NoteId, ImagePath, FileName, CreatedAt, UpdatedAt)
	          VALUES (:DatabaseId, :NoteId, :ImagePath, :FileName, :CreatedAt, :UpdatedAt)`

	result, err := MainDB.NamedExec(query, image)
	if err != nil {
		return 0, fmt.Errorf("CreateNoteImage: ошибка вставки: %w", err)
	}
	id, err := result.LastInsertId()
	if err != nil {
		return 0, fmt.Errorf("CreateNoteImage: ошибка получения LastInsertId: %w", err)
	}
	log.Printf("Создана NoteImage с ID: %d для DatabaseId: %d, NoteId: %d", id, image.DatabaseId, image.NoteId)
	return id, nil
}

// GetNoteImageByID извлекает изображение заметки по его ID и ID совместной БД.
func GetNoteImageByID(id int64, sharedDbID int64) (*models.NoteImage, error) {
	image := &models.NoteImage{}
	query := `SELECT Id, DatabaseId, NoteId, ImagePath, FileName, CreatedAt, UpdatedAt
	          FROM NoteImages WHERE Id = ? AND DatabaseId = ?`
	err := MainDB.Get(image, query, id, sharedDbID)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, nil // Не найдено
		}
		return nil, fmt.Errorf("GetNoteImageByID: ошибка получения ID %d, SharedDBID %d: %w", id, sharedDbID, err)
	}
	return image, nil
}

// GetNoteImagesByNoteID извлекает все изображения для указанной заметки в совместной БД.
func GetNoteImagesByNoteID(noteId int64, sharedDbID int64) ([]models.NoteImage, error) {
	var images []models.NoteImage
	query := `SELECT Id, DatabaseId, NoteId, ImagePath, FileName, CreatedAt, UpdatedAt
              FROM NoteImages WHERE NoteId = ? AND DatabaseId = ? ORDER BY CreatedAt ASC`
	err := MainDB.Select(&images, query, noteId, sharedDbID)
	if err != nil {
		return nil, fmt.Errorf("GetNoteImagesByNoteID: ошибка получения для NoteID %d, SharedDBID %d: %w", noteId, sharedDbID, err)
	}
	return images, nil
}

// GetAllNoteImagesBySharedDBID извлекает все изображения для указанной совместной БД.
func GetAllNoteImagesBySharedDBID(sharedDbID int64) ([]models.NoteImage, error) {
	var images []models.NoteImage
	query := `SELECT Id, DatabaseId, NoteId, ImagePath, FileName, CreatedAt, UpdatedAt
              FROM NoteImages WHERE DatabaseId = ? ORDER BY CreatedAt ASC`
	err := MainDB.Select(&images, query, sharedDbID)
	if err != nil {
		return nil, fmt.Errorf("GetAllNoteImagesBySharedDBID: ошибка получения всех для SharedDBID %d: %w", sharedDbID, err)
	}
	return images, nil
}

// UpdateNoteImage обновляет существующее изображение заметки (например, имя файла, если ImagePath не меняется).
// Обычно не используется, так как изображение либо создается, либо удаляется.
func UpdateNoteImage(image *models.NoteImage) error {
	image.UpdatedAt = time.Now()

	query := `UPDATE NoteImages SET 
	            NoteId = :NoteId, ImagePath = :ImagePath, FileName = :FileName, UpdatedAt = :UpdatedAt
	          WHERE Id = :Id AND DatabaseId = :DatabaseId`
	result, err := MainDB.NamedExec(query, image)
	if err != nil {
		return fmt.Errorf("UpdateNoteImage: ошибка обновления ID %d, SharedDBID %d: %w", image.Id, image.DatabaseId, err)
	}
	rowsAffected, _ := result.RowsAffected()
	if rowsAffected == 0 {
		return sql.ErrNoRows // Не найдено для обновления
	}
	log.Printf("Обновлена NoteImage с ID: %d для DatabaseId: %d", image.Id, image.DatabaseId)
	return nil
}

// DeleteNoteImage удаляет запись об изображении заметки по его ID и ID совместной БД.
// Также потребуется логика удаления самого файла с диска.
func DeleteNoteImage(id int64, sharedDbID int64) error {
	query := `DELETE FROM NoteImages WHERE Id = ? AND DatabaseId = ?`
	result, err := MainDB.Exec(query, id, sharedDbID)
	if err != nil {
		return fmt.Errorf("DeleteNoteImage: ошибка удаления ID %d, SharedDBID %d: %w", id, sharedDbID, err)
	}
	rowsAffected, _ := result.RowsAffected()
	if rowsAffected == 0 {
		return sql.ErrNoRows // Не найдено для удаления
	}
	log.Printf("Удалена запись NoteImage с ID: %d для DatabaseId: %d", id, sharedDbID)
	return nil
}

// --- Функции, работающие с транзакциями ---

// CreateNoteImageWithTx создает новую запись об изображении заметки в рамках транзакции.
func CreateNoteImageWithTx(tx *sqlx.Tx, image *models.NoteImage) (int64, error) {
	now := time.Now()
	image.CreatedAt = now
	image.UpdatedAt = now

	query := `INSERT INTO NoteImages (DatabaseId, NoteId, ImagePath, FileName, CreatedAt, UpdatedAt)
	          VALUES (:DatabaseId, :NoteId, :ImagePath, :FileName, :CreatedAt, :UpdatedAt)`
	result, err := tx.NamedExec(query, image)
	if err != nil {
		return 0, fmt.Errorf("CreateNoteImageWithTx: ошибка вставки: %w", err)
	}
	newID, err := result.LastInsertId()
	if err != nil {
		return 0, fmt.Errorf("CreateNoteImageWithTx: ошибка LastInsertId: %w", err)
	}
	return newID, nil
}

// GetNoteImageByIDWithTx извлекает изображение заметки по ID и ID совместной БД в рамках транзакции.
func GetNoteImageByIDWithTx(tx *sqlx.Tx, id int64, sharedDbID int64) (*models.NoteImage, error) {
	image := &models.NoteImage{}
	query := `SELECT Id, DatabaseId, NoteId, ImagePath, FileName, CreatedAt, UpdatedAt
	          FROM NoteImages WHERE Id = ? AND DatabaseId = ?`
	err := tx.Get(image, query, id, sharedDbID)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, nil // Не найдено
		}
		return nil, fmt.Errorf("GetNoteImageByIDWithTx: ошибка получения ID %d, SharedDBID %d: %w", id, sharedDbID, err)
	}
	return image, nil
}

// GetNoteImagesByNoteIDWithTx извлекает все изображения для указанной заметки в совместной БД в рамках транзакции.
func GetNoteImagesByNoteIDWithTx(tx *sqlx.Tx, noteId int64, sharedDbID int64) ([]models.NoteImage, error) {
	var images []models.NoteImage
	query := `SELECT Id, DatabaseId, NoteId, ImagePath, FileName, CreatedAt, UpdatedAt
              FROM NoteImages WHERE NoteId = ? AND DatabaseId = ? ORDER BY CreatedAt ASC`
	err := tx.Select(&images, query, noteId, sharedDbID)
	if err != nil {
		return nil, fmt.Errorf("GetNoteImagesByNoteIDWithTx: ошибка получения для NoteID %d, SharedDBID %d: %w", noteId, sharedDbID, err)
	}
	return images, nil
}

// GetAllNoteImagesBySharedDBIDWithTx извлекает все изображения для указанной совместной БД в рамках транзакции.
func GetAllNoteImagesBySharedDBIDWithTx(tx *sqlx.Tx, sharedDbID int64) ([]models.NoteImage, error) {
	var images []models.NoteImage
	query := `SELECT Id, DatabaseId, NoteId, ImagePath, FileName, CreatedAt, UpdatedAt
	          FROM NoteImages WHERE DatabaseId = ? ORDER BY CreatedAt ASC`
	err := tx.Select(&images, query, sharedDbID)
	if err != nil {
		return nil, fmt.Errorf("GetAllNoteImagesBySharedDBIDWithTx: ошибка получения для SharedDBID %d: %w", sharedDbID, err)
	}
	return images, nil
}

// UpdateNoteImageWithTx обновляет существующее изображение заметки в рамках транзакции.
func UpdateNoteImageWithTx(tx *sqlx.Tx, image *models.NoteImage) error {
	image.UpdatedAt = time.Now()
	query := `UPDATE NoteImages SET 
	            NoteId = :NoteId, ImagePath = :ImagePath, FileName = :FileName, UpdatedAt = :UpdatedAt
	          WHERE Id = :Id AND DatabaseId = :DatabaseId`
	result, err := tx.NamedExec(query, image)
	if err != nil {
		return fmt.Errorf("UpdateNoteImageWithTx: ошибка обновления ID %d, SharedDBID %d: %w", image.Id, image.DatabaseId, err)
	}
	rowsAffected, _ := result.RowsAffected()
	if rowsAffected == 0 {
		return sql.ErrNoRows // Не найдено для обновления
	}
	return nil
}

// DeleteNoteImageWithTx удаляет запись об изображении заметки по ID и ID совместной БД в рамках транзакции.
func DeleteNoteImageWithTx(tx *sqlx.Tx, id int64, sharedDbID int64) error {
	// Перед удалением записи из БД, нужно получить ImagePath, чтобы потом удалить файл
	// Эту логику лучше реализовать в sync_controller или в сервисном слое, если он будет.
	// Здесь только удаление из БД.
	query := `DELETE FROM NoteImages WHERE Id = ? AND DatabaseId = ?`
	result, err := tx.Exec(query, id, sharedDbID)
	if err != nil {
		return fmt.Errorf("DeleteNoteImageWithTx: ошибка удаления ID %d, SharedDBID %d: %w", id, sharedDbID, err)
	}
	rowsAffected, _ := result.RowsAffected()
	if rowsAffected == 0 {
		return sql.ErrNoRows // Не найдено
	}
	return nil
}

// GetAllNoteImageIDsForSharedDBWithTx извлекает все ID изображений заметок для указанной совместной БД в рамках транзакции.
func GetAllNoteImageIDsForSharedDBWithTx(tx *sqlx.Tx, sharedDbID int64) ([]int64, error) {
	var ids []int64
	query := `SELECT Id FROM NoteImages WHERE DatabaseId = ?`
	err := tx.Select(&ids, query, sharedDbID)
	if err != nil {
		if err == sql.ErrNoRows {
			return []int64{}, nil // Возвращаем пустой слайс, если ничего не найдено
		}
		return nil, fmt.Errorf("GetAllNoteImageIDsForSharedDBWithTx: ошибка при получении ID для SharedDBID %d: %w", sharedDbID, err)
	}
	return ids, nil
}

// GetImagePathsForDeletionWithTx получает пути к файлам изображений, которые должны быть удалены из БД (по ID).
func GetImagePathsForDeletionWithTx(tx *sqlx.Tx, imageIDs []int64, sharedDbID int64) ([]string, error) {
	if len(imageIDs) == 0 {
		return []string{}, nil
	}
	query, args, err := sqlx.In("SELECT ImagePath FROM NoteImages WHERE Id IN (?) AND DatabaseId = ?", imageIDs, sharedDbID)
	if err != nil {
		return nil, fmt.Errorf("GetImagePathsForDeletionWithTx: ошибка при формировании IN запроса: %w", err)
	}
	query = tx.Rebind(query) // Rebind для конкретного драйвера БД

	var paths []string
	err = tx.Select(&paths, query, args...)
	if err != nil {
		if err == sql.ErrNoRows {
			return []string{}, nil
		}
		return nil, fmt.Errorf("GetImagePathsForDeletionWithTx: ошибка при выборе ImagePath: %w", err)
	}
	return paths, nil
}

// GetImagesForNoteIDs извлекает все изображения для списка ID заметок.
func GetImagesForNoteIDs(noteIDs []int64) ([]models.NoteImage, error) {
	if len(noteIDs) == 0 {
		return []models.NoteImage{}, nil
	}

	var images []models.NoteImage
	// Используем sqlx.In для работы со списком ID
	query, args, err := sqlx.In(`SELECT Id, NoteId, FileName, ImagePath, CreatedAt, UpdatedAt, DatabaseId 
	                             FROM NoteImages 
	                             WHERE NoteId IN (?) 
	                             ORDER BY CreatedAt ASC`, noteIDs)
	if err != nil {
		return nil, fmt.Errorf("ошибка при построении запроса для GetImagesForNoteIDs: %w", err)
	}

	// sqlx.In возвращает запрос для текущего драйвера, нужно его перепривязать к MainDB
	query = MainDB.Rebind(query)
	err = MainDB.Select(&images, query, args...)
	if err != nil {
		return nil, fmt.Errorf("ошибка получения изображений для списка ID заметок: %w", err)
	}
	return images, nil
}

// GetNoteImageByFileNameAndNoteIDWithTx ищет изображение по имени файла и ID заметки в рамках транзакции.
// Это более надежный способ поиска существующих изображений при синхронизации.
func GetNoteImageByFileNameAndNoteIDWithTx(tx *sqlx.Tx, fileName string, noteId int64, sharedDbID int64) (*models.NoteImage, error) {
	image := &models.NoteImage{}
	query := `SELECT Id, DatabaseId, NoteId, ImagePath, FileName, CreatedAt, UpdatedAt
	          FROM NoteImages WHERE FileName = ? AND NoteId = ? AND DatabaseId = ? LIMIT 1`
	err := tx.Get(image, query, fileName, noteId, sharedDbID)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, nil // Не найдено
		}
		return nil, fmt.Errorf("GetNoteImageByFileNameAndNoteIDWithTx: ошибка поиска FileName %s, NoteID %d, SharedDBID %d: %w", fileName, noteId, sharedDbID, err)
	}
	return image, nil
}
