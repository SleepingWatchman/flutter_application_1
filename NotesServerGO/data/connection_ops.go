package data

import (
	"database/sql"
	"fmt"
	"log"
	"time"

	"notes_server_go/models"

	"github.com/jmoiron/sqlx"
)

// CreateConnection создает новое соединение между заметками в указанной совместной БД.
// Поле conn.DatabaseId должно быть установлено на ID совместной БД.
// Возвращает ID созданного соединения.
func CreateConnection(conn *models.Connection) (int64, error) {
	now := time.Now()
	conn.CreatedAt = now
	conn.UpdatedAt = now

	query := `INSERT INTO Connections (DatabaseId, FromNoteId, ToNoteId, Name, ConnectionColor, CreatedAt, UpdatedAt)
	          VALUES (:DatabaseId, :FromNoteId, :ToNoteId, :Name, :ConnectionColor, :CreatedAt, :UpdatedAt)`

	result, err := MainDB.NamedExec(query, conn)
	if err != nil {
		return 0, fmt.Errorf("CreateConnection: ошибка вставки: %w", err)
	}
	id, err := result.LastInsertId()
	if err != nil {
		return 0, fmt.Errorf("CreateConnection: ошибка получения LastInsertId: %w", err)
	}
	log.Printf("Создано Connection с ID: %d для DatabaseId: %d", id, conn.DatabaseId)
	return id, nil
}

// GetConnectionByID извлекает соединение по его ID и ID совместной БД.
func GetConnectionByID(id int64, sharedDbID int64) (*models.Connection, error) {
	conn := &models.Connection{}
	query := `SELECT Id, DatabaseId, FromNoteId, ToNoteId, Name, ConnectionColor, CreatedAt, UpdatedAt
	          FROM Connections WHERE Id = ? AND DatabaseId = ?`
	err := MainDB.Get(conn, query, id, sharedDbID)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, nil // Не найдено
		}
		return nil, fmt.Errorf("GetConnectionByID: ошибка получения ID %d, SharedDBID %d: %w", id, sharedDbID, err)
	}
	return conn, nil
}

// GetAllConnectionsBySharedDBID извлекает все соединения для указанной совместной БД.
func GetAllConnectionsBySharedDBID(sharedDbID int64) ([]models.Connection, error) {
	var conns []models.Connection
	query := `SELECT Id, DatabaseId, FromNoteId, ToNoteId, Name, ConnectionColor, CreatedAt, UpdatedAt
              FROM Connections WHERE DatabaseId = ? ORDER BY UpdatedAt DESC`
	err := MainDB.Select(&conns, query, sharedDbID)
	if err != nil {
		return nil, fmt.Errorf("GetAllConnectionsBySharedDBID: ошибка получения всех для SharedDBID %d: %w", sharedDbID, err)
	}
	return conns, nil
}

// UpdateConnection обновляет существующее соединение в указанной совместной БД.
func UpdateConnection(conn *models.Connection) error {
	conn.UpdatedAt = time.Now()

	query := `UPDATE Connections SET 
	            FromNoteId = :FromNoteId, ToNoteId = :ToNoteId, Name = :Name, 
	            ConnectionColor = :ConnectionColor, UpdatedAt = :UpdatedAt
	          WHERE Id = :Id AND DatabaseId = :DatabaseId`
	result, err := MainDB.NamedExec(query, conn)
	if err != nil {
		return fmt.Errorf("UpdateConnection: ошибка обновления ID %d, SharedDBID %d: %w", conn.Id, conn.DatabaseId, err)
	}
	rowsAffected, _ := result.RowsAffected()
	if rowsAffected == 0 {
		return sql.ErrNoRows // Не найдено для обновления
	}
	log.Printf("Обновлено Connection с ID: %d для DatabaseId: %d", conn.Id, conn.DatabaseId)
	return nil
}

// DeleteConnection удаляет соединение по его ID и ID совместной БД.
func DeleteConnection(id int64, sharedDbID int64) error {
	query := `DELETE FROM Connections WHERE Id = ? AND DatabaseId = ?`
	result, err := MainDB.Exec(query, id, sharedDbID)
	if err != nil {
		return fmt.Errorf("DeleteConnection: ошибка удаления ID %d, SharedDBID %d: %w", id, sharedDbID, err)
	}
	rowsAffected, _ := result.RowsAffected()
	if rowsAffected == 0 {
		return sql.ErrNoRows // Не найдено для удаления
	}
	log.Printf("Удалено Connection с ID: %d для DatabaseId: %d", id, sharedDbID)
	return nil
}

// --- Функции, работающие с транзакциями ---

// CreateConnectionWithTx создает новое соединение в рамках транзакции.
func CreateConnectionWithTx(tx *sqlx.Tx, conn *models.Connection) (int64, error) {
	now := time.Now()
	conn.CreatedAt = now
	conn.UpdatedAt = now

	query := `INSERT INTO Connections (DatabaseId, FromNoteId, ToNoteId, Name, ConnectionColor, CreatedAt, UpdatedAt)
	          VALUES (:DatabaseId, :FromNoteId, :ToNoteId, :Name, :ConnectionColor, :CreatedAt, :UpdatedAt)`
	result, err := tx.NamedExec(query, conn)
	if err != nil {
		return 0, fmt.Errorf("CreateConnectionWithTx: ошибка вставки: %w", err)
	}
	newID, err := result.LastInsertId()
	if err != nil {
		return 0, fmt.Errorf("CreateConnectionWithTx: ошибка LastInsertId: %w", err)
	}
	return newID, nil
}

// GetConnectionByIDWithTx извлекает соединение по ID и ID совместной БД в рамках транзакции.
func GetConnectionByIDWithTx(tx *sqlx.Tx, id int64, sharedDbID int64) (*models.Connection, error) {
	conn := &models.Connection{}
	query := `SELECT Id, DatabaseId, FromNoteId, ToNoteId, Name, ConnectionColor, CreatedAt, UpdatedAt
	          FROM Connections WHERE Id = ? AND DatabaseId = ?`
	err := tx.Get(conn, query, id, sharedDbID)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, nil // Не найдено
		}
		return nil, fmt.Errorf("GetConnectionByIDWithTx: ошибка получения ID %d, SharedDBID %d: %w", id, sharedDbID, err)
	}
	return conn, nil
}

// GetAllConnectionsBySharedDBIDWithTx извлекает все соединения для указанной совместной БД в рамках транзакции.
func GetAllConnectionsBySharedDBIDWithTx(tx *sqlx.Tx, sharedDbID int64) ([]models.Connection, error) {
	var conns []models.Connection
	query := `SELECT Id, DatabaseId, FromNoteId, ToNoteId, Name, ConnectionColor, CreatedAt, UpdatedAt
	          FROM Connections WHERE DatabaseId = ? ORDER BY UpdatedAt DESC`
	err := tx.Select(&conns, query, sharedDbID)
	if err != nil {
		return nil, fmt.Errorf("GetAllConnectionsBySharedDBIDWithTx: ошибка получения для SharedDBID %d: %w", sharedDbID, err)
	}
	return conns, nil
}

// UpdateConnectionWithTx обновляет существующее соединение в рамках транзакции.
func UpdateConnectionWithTx(tx *sqlx.Tx, conn *models.Connection) error {
	conn.UpdatedAt = time.Now()
	query := `UPDATE Connections SET 
	            FromNoteId = :FromNoteId, ToNoteId = :ToNoteId, Name = :Name, 
	            ConnectionColor = :ConnectionColor, UpdatedAt = :UpdatedAt
	          WHERE Id = :Id AND DatabaseId = :DatabaseId`
	result, err := tx.NamedExec(query, conn)
	if err != nil {
		return fmt.Errorf("UpdateConnectionWithTx: ошибка обновления ID %d, SharedDBID %d: %w", conn.Id, conn.DatabaseId, err)
	}
	rowsAffected, _ := result.RowsAffected()
	if rowsAffected == 0 {
		return sql.ErrNoRows // Не найдено для обновления
	}
	return nil
}

// DeleteConnectionWithTx удаляет соединение по ID и ID совместной БД в рамках транзакции.
func DeleteConnectionWithTx(tx *sqlx.Tx, id int64, sharedDbID int64) error {
	query := `DELETE FROM Connections WHERE Id = ? AND DatabaseId = ?`
	result, err := tx.Exec(query, id, sharedDbID)
	if err != nil {
		return fmt.Errorf("DeleteConnectionWithTx: ошибка удаления ID %d, SharedDBID %d: %w", id, sharedDbID, err)
	}
	rowsAffected, _ := result.RowsAffected()
	if rowsAffected == 0 {
		return sql.ErrNoRows // Не найдено
	}
	return nil
}

// GetAllConnectionIDsForSharedDBWithTx извлекает все ID соединений для указанной совместной БД в рамках транзакции.
func GetAllConnectionIDsForSharedDBWithTx(tx *sqlx.Tx, sharedDbID int64) ([]int64, error) {
	var ids []int64
	query := `SELECT Id FROM Connections WHERE DatabaseId = ?`
	err := tx.Select(&ids, query, sharedDbID)
	if err != nil {
		if err == sql.ErrNoRows {
			return []int64{}, nil // Возвращаем пустой слайс, если ничего не найдено
		}
		return nil, fmt.Errorf("GetAllConnectionIDsForSharedDBWithTx: ошибка при получении ID для SharedDBID %d: %w", sharedDbID, err)
	}
	return ids, nil
}

// GetConnectionsForDatabase извлекает все соединения для указанной ID базы данных.
func GetConnectionsForDatabase(databaseID int64) ([]models.Connection, error) {
	var connections []models.Connection
	// Предполагается, что таблица Connections также имеет поле DatabaseId
	// Если это не так, логику нужно будет адаптировать.
	// Если соединение не привязано напрямую к DatabaseId, а, например, к заметкам,
	// то эту функцию нужно будет реализовывать иначе (например, собирать ID всех заметок БД
	// и затем искать соединения для этих заметок).
	// Пока что предполагаю наличие DatabaseId в таблице Connections.
	query := `SELECT Id, FromNoteId, ToNoteId, Name, CreatedAt, UpdatedAt, DatabaseId, ConnectionColor 
	          FROM Connections 
	          WHERE DatabaseId = ? 
	          ORDER BY CreatedAt ASC`
	err := MainDB.Select(&connections, query, databaseID)
	if err != nil {
		return nil, fmt.Errorf("ошибка получения соединений для БД ID %d: %w", databaseID, err)
	}
	return connections, nil
}
