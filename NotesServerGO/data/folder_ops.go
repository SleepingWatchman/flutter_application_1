package data

import (
	"database/sql"
	"fmt"
	"log"
	"time"

	"notes_server_go/models"

	"github.com/jmoiron/sqlx"
)

// CreateFolder создает новую папку в указанной совместной БД.
// Поле folder.DatabaseID должно быть установлено на ID совместной БД.
// Возвращает ID созданной папки.
func CreateFolder(folder *models.Folder) (int64, error) {
	now := time.Now()
	folder.CreatedAt = now
	folder.UpdatedAt = now

	query := `INSERT INTO Folders (DatabaseId, Name, ParentId, CreatedAt, UpdatedAt, Color, IsExpanded)
	          VALUES (:DatabaseId, :Name, :ParentId, :CreatedAt, :UpdatedAt, :Color, :IsExpanded)`

	result, err := MainDB.NamedExec(query, folder)
	if err != nil {
		return 0, fmt.Errorf("CreateFolder: ошибка вставки папки: %w", err)
	}
	id, err := result.LastInsertId()
	if err != nil {
		return 0, fmt.Errorf("CreateFolder: ошибка получения LastInsertId: %w", err)
	}
	log.Printf("Создана папка с ID: %d для DatabaseId: %d", id, folder.DatabaseID)
	return id, nil
}

// GetFolderByID извлекает папку по ее ID и ID совместной БД.
func GetFolderByID(id int64, sharedDbID int64) (*models.Folder, error) {
	folder := &models.Folder{}
	query := `SELECT Id, DatabaseId, Name, ParentId, CreatedAt, UpdatedAt, Color, IsExpanded
	          FROM Folders WHERE Id = ? AND DatabaseId = ?`
	err := MainDB.Get(folder, query, id, sharedDbID)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, nil // Папка не найдена
		}
		return nil, fmt.Errorf("GetFolderByID: ошибка получения папки ID %d, SharedDBID %d: %w", id, sharedDbID, err)
	}
	return folder, nil
}

// GetAllFoldersBySharedDBID извлекает все папки для указанной совместной БД.
func GetAllFoldersBySharedDBID(sharedDbID int64) ([]models.Folder, error) {
	var folders []models.Folder
	query := `SELECT Id, DatabaseId, Name, ParentId, CreatedAt, UpdatedAt, Color, IsExpanded
	          FROM Folders WHERE DatabaseId = ? ORDER BY Name ASC`
	err := MainDB.Select(&folders, query, sharedDbID)
	if err != nil {
		return nil, fmt.Errorf("GetAllFoldersBySharedDBID: ошибка получения всех папок для SharedDBID %d: %w", sharedDbID, err)
	}
	return folders, nil
}

// UpdateFolder обновляет существующую папку в указанной совместной БД.
// Поля folder.ID и folder.DatabaseID (ID совместной БД) должны быть установлены.
func UpdateFolder(folder *models.Folder) error {
	folder.UpdatedAt = time.Now()

	query := `UPDATE Folders SET Name = :Name, ParentId = :ParentId, UpdatedAt = :UpdatedAt, Color = :Color, IsExpanded = :IsExpanded
	          WHERE Id = :Id AND DatabaseId = :DatabaseId`

	result, err := MainDB.NamedExec(query, folder)
	if err != nil {
		return fmt.Errorf("UpdateFolder: ошибка обновления папки ID %d, SharedDBID %d: %w", folder.ID, folder.DatabaseID, err)
	}
	rowsAffected, _ := result.RowsAffected()
	if rowsAffected == 0 {
		return sql.ErrNoRows // Не найдено для обновления
	}
	log.Printf("Обновлена папка с ID: %d для DatabaseId: %d", folder.ID, folder.DatabaseID)
	return nil
}

// DeleteFolder удаляет папку из указанной совместной БД.
func DeleteFolder(id int64, sharedDbID int64) error {
	query := `DELETE FROM Folders WHERE Id = ? AND DatabaseId = ?`
	result, err := MainDB.Exec(query, id, sharedDbID)
	if err != nil {
		return fmt.Errorf("DeleteFolder: ошибка удаления папки ID %d, SharedDBID %d: %w", id, sharedDbID, err)
	}
	rowsAffected, _ := result.RowsAffected()
	if rowsAffected == 0 {
		return sql.ErrNoRows // Не найдено для удаления
	}
	log.Printf("Удалена папка с ID: %d для DatabaseId: %d", id, sharedDbID)
	return nil
}

// --- Функции, работающие с транзакциями ---

// CreateFolderWithTx создает новую папку в рамках транзакции.
func CreateFolderWithTx(tx *sqlx.Tx, folder *models.Folder) (int64, error) {
	now := time.Now()
	folder.CreatedAt = now
	folder.UpdatedAt = now

	query := `INSERT INTO Folders (DatabaseId, Name, ParentId, CreatedAt, UpdatedAt, Color, IsExpanded)
	          VALUES (:DatabaseId, :Name, :ParentId, :CreatedAt, :UpdatedAt, :Color, :IsExpanded)`
	result, err := tx.NamedExec(query, folder)
	if err != nil {
		return 0, fmt.Errorf("CreateFolderWithTx: ошибка вставки: %w", err)
	}
	newID, err := result.LastInsertId()
	if err != nil {
		return 0, fmt.Errorf("CreateFolderWithTx: ошибка LastInsertId: %w", err)
	}
	return newID, nil
}

// GetFolderByIDWithTx извлекает папку по ID и ID совместной БД в рамках транзакции.
func GetFolderByIDWithTx(tx *sqlx.Tx, id int64, sharedDbID int64) (*models.Folder, error) {
	folder := &models.Folder{}
	query := `SELECT Id, DatabaseId, Name, ParentId, CreatedAt, UpdatedAt, Color, IsExpanded
	          FROM Folders WHERE Id = ? AND DatabaseId = ?`
	err := tx.Get(folder, query, id, sharedDbID)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, nil // Не найдено
		}
		return nil, fmt.Errorf("GetFolderByIDWithTx: ошибка получения ID %d, SharedDBID %d: %w", id, sharedDbID, err)
	}
	return folder, nil
}

// GetAllFoldersBySharedDBIDWithTx извлекает все папки для указанной совместной БД в рамках транзакции.
func GetAllFoldersBySharedDBIDWithTx(tx *sqlx.Tx, sharedDbID int64) ([]models.Folder, error) {
	var folders []models.Folder
	query := `SELECT Id, DatabaseId, Name, ParentId, CreatedAt, UpdatedAt, Color, IsExpanded
	          FROM Folders WHERE DatabaseId = ? ORDER BY Name ASC`
	err := tx.Select(&folders, query, sharedDbID)
	if err != nil {
		return nil, fmt.Errorf("GetAllFoldersBySharedDBIDWithTx: ошибка получения для SharedDBID %d: %w", sharedDbID, err)
	}
	return folders, nil
}

// UpdateFolderWithTx обновляет существующую папку в рамках транзакции.
func UpdateFolderWithTx(tx *sqlx.Tx, folder *models.Folder) error {
	folder.UpdatedAt = time.Now()
	query := `UPDATE Folders SET Name = :Name, ParentId = :ParentId, UpdatedAt = :UpdatedAt, Color = :Color, IsExpanded = :IsExpanded
	          WHERE Id = :Id AND DatabaseId = :DatabaseId`
	result, err := tx.NamedExec(query, folder)
	if err != nil {
		return fmt.Errorf("UpdateFolderWithTx: ошибка обновления ID %d, SharedDBID %d: %w", folder.ID, folder.DatabaseID, err)
	}
	rowsAffected, _ := result.RowsAffected()
	if rowsAffected == 0 {
		return sql.ErrNoRows // Не найдено для обновления
	}
	return nil
}

// DeleteFolderWithTx удаляет папку по ID и ID совместной БД в рамках транзакции.
func DeleteFolderWithTx(tx *sqlx.Tx, id int64, sharedDbID int64) error {
	query := `DELETE FROM Folders WHERE Id = ? AND DatabaseId = ?`
	result, err := tx.Exec(query, id, sharedDbID)
	if err != nil {
		return fmt.Errorf("DeleteFolderWithTx: ошибка удаления ID %d, SharedDBID %d: %w", id, sharedDbID, err)
	}
	rowsAffected, _ := result.RowsAffected()
	if rowsAffected == 0 {
		return sql.ErrNoRows // Не найдено
	}
	return nil
}

// GetAllFolderIDsForSharedDBWithTx извлекает все ID папок для указанной совместной БД в рамках транзакции.
func GetAllFolderIDsForSharedDBWithTx(tx *sqlx.Tx, sharedDbID int64) ([]int64, error) {
	var ids []int64
	query := `SELECT Id FROM Folders WHERE DatabaseId = ?`
	err := tx.Select(&ids, query, sharedDbID)
	if err != nil {
		if err == sql.ErrNoRows {
			return []int64{}, nil // Возвращаем пустой слайс, если ничего не найдено
		}
		return nil, fmt.Errorf("GetAllFolderIDsForSharedDBWithTx: ошибка при получении ID для SharedDBID %d: %w", sharedDbID, err)
	}
	return ids, nil
}

// GetFoldersForDatabase извлекает все папки для указанной ID базы данных.
func GetFoldersForDatabase(databaseID int64) ([]models.Folder, error) {
	var folders []models.Folder
	// Примечание: OwnerUserId здесь может быть избыточным, если DatabaseId уже гарантирует принадлежность.
	// Но если структура позволяет папкам иметь другого владельца внутри общей БД, это важно.
	// Пока оставим так, как было в GetFolders, но это место для возможного уточнения логики.
	// Также, если DatabaseId = 0 (личная база), OwnerUserId будет ключевым фильтром.
	// Для совместных БД (DatabaseId != 0), OwnerUserId из таблицы Folders может и не использоваться,
	// так как доступ к БД в целом определяется через SharedDatabaseUsers.
	// Для экспорта совместной БД нам нужны все ее папки, независимо от OwnerUserId в таблице Folders.
	// Поэтому для совместной БД (databaseID != 0) уберем OwnerUserId из WHERE.

	// Владелец папки (OwnerUserId) не имеет значения при экспорте данных конкретной общей базы данных (databaseID)
	// Все папки, принадлежащие databaseID, должны быть включены.
	// Если databaseID == 0, то это личная база, и OwnerUserId должен быть использован (но этот сценарий здесь не рассматривается).

	finalQuery := `SELECT Id, Name, ParentId, CreatedAt, UpdatedAt, DatabaseId, Color, IsExpanded 
	               FROM Folders 
	               WHERE DatabaseId = ? 
	               ORDER BY Name ASC`

	err := MainDB.Select(&folders, finalQuery, databaseID)
	if err != nil {
		return nil, fmt.Errorf("ошибка получения папок для БД ID %d: %w", databaseID, err)
	}
	return folders, nil
}
