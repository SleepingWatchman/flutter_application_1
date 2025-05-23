package data

import (
	"database/sql"
	"encoding/base64" // Для декодирования изображений
	"fmt"
	"io/ioutil" // Для ioutil.WriteFile
	"log"
	"os"            // Для os.MkdirAll, os.Remove
	"path/filepath" // Для filepath.Join
	"time"

	"notes_server_go/models"

	"github.com/jmoiron/sqlx"
)

// CreateSharedDatabase создает новую совместную базу данных и добавляет владельца.
func CreateSharedDatabase(db *models.SharedDatabase) (int64, error) {
	now := time.Now()
	db.CreatedAt = now
	db.UpdatedAt = now

	tx, err := MainDB.Beginx() // Начинаем транзакцию
	if err != nil {
		return 0, fmt.Errorf("failed to begin transaction: %w", err)
	}
	defer tx.Rollback() // Откатываем, если что-то пошло не так

	queryDb := `INSERT INTO SharedDatabases (Name, OwnerUserId, CreatedAt, UpdatedAt)
	            VALUES (?, ?, ?, ?)`
	result, err := tx.Exec(queryDb, db.Name, db.OwnerUserId, db.CreatedAt, db.UpdatedAt)
	if err != nil {
		return 0, fmt.Errorf("failed to insert shared database: %w", err)
	}

	sdbID, err := result.LastInsertId()
	if err != nil {
		return 0, fmt.Errorf("failed to get last insert ID for shared database: %w", err)
	}
	db.Id = sdbID

	// Добавляем владельца в таблицу SharedDatabaseUsers
	queryUser := `INSERT INTO SharedDatabaseUsers (SharedDatabaseId, UserId, Role, JoinedAt)
	               VALUES (?, ?, ?, ?)`
	_, err = tx.Exec(queryUser, sdbID, db.OwnerUserId, models.RoleOwner, now)
	if err != nil {
		return 0, fmt.Errorf("failed to add owner to shared database users: %w", err)
	}

	if err = tx.Commit(); err != nil {
		return 0, fmt.Errorf("failed to commit transaction: %w", err)
	}

	return sdbID, nil
}

// GetSharedDatabaseByID извлекает совместную БД по ID, если у пользователя есть доступ.
// Возвращает (nil, nil) если БД не найдена или нет доступа (чтобы не раскрывать существование БД).
func GetSharedDatabaseByID(sdbID int64, userID int64) (*models.SharedDatabase, error) {
	sdb := &models.SharedDatabase{}
	// Сначала проверим, есть ли пользователь в этой БД
	queryCheck := `SELECT COUNT(*) FROM SharedDatabaseUsers WHERE SharedDatabaseId = ? AND UserId = ?`
	var count int
	err := MainDB.Get(&count, queryCheck, sdbID, userID)
	if err != nil {
		return nil, fmt.Errorf("failed to check user access for shared DB ID %d: %w", sdbID, err)
	}
	if count == 0 {
		return nil, nil // Нет доступа или БД не существует для этого пользователя
	}

	queryGet := `SELECT Id, Name, OwnerUserId, CreatedAt, UpdatedAt FROM SharedDatabases WHERE Id = ?`
	err = MainDB.Get(sdb, queryGet, sdbID)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, nil // Не найдено (хотя проверка доступа уже должна была это покрыть)
		}
		return nil, fmt.Errorf("failed to get shared database by ID %d: %w", sdbID, err)
	}
	return sdb, nil
}

// GetSharedDatabasesForUser извлекает все совместные БД, к которым пользователь имеет доступ.
func GetSharedDatabasesForUser(userID int64) ([]models.SharedDatabase, error) {
	var dbs []models.SharedDatabase
	query := `SELECT sd.Id, sd.Name, sd.OwnerUserId, sd.CreatedAt, sd.UpdatedAt
	          FROM SharedDatabases sd
	          JOIN SharedDatabaseUsers sdu ON sd.Id = sdu.SharedDatabaseId
	          WHERE sdu.UserId = ?
	          ORDER BY sd.Name ASC`
	err := MainDB.Select(&dbs, query, userID)
	if err != nil {
		return nil, fmt.Errorf("failed to get shared databases for user ID %d: %w", userID, err)
	}
	return dbs, nil
}

// AddUserToSharedDatabase добавляет пользователя в совместную БД.
// Только владелец может добавлять других пользователей.
func AddUserToSharedDatabase(sdbID int64, userToAddID int64, role models.SharedDatabaseUserRole, currentUserID int64) error {
	// 1. Проверить, является ли currentUserID владельцем sdbID
	ownerRole, err := GetUserRoleInSharedDatabase(sdbID, currentUserID)
	if err != nil {
		return fmt.Errorf("failed to verify owner status for shared DB ID %d: %w", sdbID, err)
	}
	if ownerRole == nil || *ownerRole != models.RoleOwner {
		return fmt.Errorf("user %d is not the owner of shared DB ID %d and cannot add users", currentUserID, sdbID)
	}

	// 2. Проверить, не является ли добавляемый пользователь уже в БД
	existingRole, _ := GetUserRoleInSharedDatabase(sdbID, userToAddID)
	if existingRole != nil {
		return fmt.Errorf("user %d is already in shared DB ID %d with role %s", userToAddID, sdbID, *existingRole)
	}

	// 3. Добавить пользователя
	query := `INSERT INTO SharedDatabaseUsers (SharedDatabaseId, UserId, Role, JoinedAt)
	           VALUES (?, ?, ?, ?)`
	_, err = MainDB.Exec(query, sdbID, userToAddID, role, time.Now())
	if err != nil {
		return fmt.Errorf("failed to add user %d to shared DB ID %d: %w", userToAddID, sdbID, err)
	}
	return nil
}

// GetUserRoleInSharedDatabase возвращает роль пользователя в указанной совместной БД.
// Возвращает (nil, nil) если пользователь не состоит в БД.
func GetUserRoleInSharedDatabase(sdbID int64, userID int64) (*models.SharedDatabaseUserRole, error) {
	var sdu models.SharedDatabaseUser
	query := `SELECT Role FROM SharedDatabaseUsers WHERE SharedDatabaseId = ? AND UserId = ?`
	err := MainDB.Get(&sdu, query, sdbID, userID)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, nil // Пользователь не в этой БД
		}
		return nil, fmt.Errorf("failed to get user role for user %d in shared DB ID %d: %w", userID, sdbID, err)
	}
	return &sdu.Role, nil
}

// RemoveUserFromSharedDatabase удаляет пользователя из совместной БД.
// Владелец не может удалить сам себя этим методом, он должен удалить БД.
// Владелец может удалять других. Участники не могут удалять других.
func RemoveUserFromSharedDatabase(sdbID int64, userIDToRemove int64, currentUserID int64) error {
	// 1. Получить информацию о БД, чтобы узнать владельца
	sdb, err := GetSharedDatabaseDetails(sdbID) // Нужна функция, которая просто вернет детали БД без проверки доступа пользователя
	if err != nil || sdb == nil {
		return fmt.Errorf("shared database with ID %d not found or error fetching: %w", sdbID, err)
	}

	// 2. Проверить права currentUserID
	if currentUserID != sdb.OwnerUserId {
		return fmt.Errorf("user %d is not the owner of shared DB ID %d and cannot remove users", currentUserID, sdbID)
	}

	// 3. Владелец не может удалить сам себя этим методом (он должен удалить БД целиком)
	if userIDToRemove == sdb.OwnerUserId {
		return fmt.Errorf("owner %d cannot remove themselves from shared DB ID %d using this method. Delete the database instead.", userIDToRemove, sdbID)
	}

	// 4. Удалить пользователя
	query := `DELETE FROM SharedDatabaseUsers WHERE SharedDatabaseId = ? AND UserId = ?`
	result, err := MainDB.Exec(query, sdbID, userIDToRemove)
	if err != nil {
		return fmt.Errorf("failed to remove user %d from shared DB ID %d: %w", userIDToRemove, sdbID, err)
	}
	rowsAffected, _ := result.RowsAffected()
	if rowsAffected == 0 {
		return fmt.Errorf("user %d not found in shared DB ID %d or already removed", userIDToRemove, sdbID)
	}
	return nil
}

// UpdateUserRoleInSharedDatabase обновляет роль пользователя в совместной БД.
// Только владелец может изменять роли.
// Владелец не может изменить свою роль этим методом.
func UpdateUserRoleInSharedDatabase(sdbID int64, userIDToUpdate int64, newRole models.SharedDatabaseUserRole, currentUserID int64) error {
	// 1. Получить информацию о БД, чтобы узнать владельца
	sdb, err := GetSharedDatabaseDetails(sdbID) // Нужна функция, которая просто вернет детали БД без проверки доступа пользователя
	if err != nil || sdb == nil {
		return fmt.Errorf("shared database with ID %d not found or error fetching: %w", sdbID, err)
	}

	// 2. Проверить, является ли currentUserID владельцем
	if currentUserID != sdb.OwnerUserId {
		return fmt.Errorf("user %d is not the owner of shared DB ID %d and cannot update roles", currentUserID, sdbID)
	}

	// 3. Владелец не может изменить свою роль (она всегда RoleOwner)
	if userIDToUpdate == sdb.OwnerUserId && newRole != models.RoleOwner {
		return fmt.Errorf("owner's role cannot be changed from 'owner' for shared DB ID %d", sdbID)
	}
	if userIDToUpdate == sdb.OwnerUserId && newRole == models.RoleOwner {
		return nil // Нет изменений для роли владельца
	}

	// 4. Нельзя назначить роль RoleOwner другому пользователю
	if newRole == models.RoleOwner && userIDToUpdate != sdb.OwnerUserId {
		return fmt.Errorf("cannot assign 'owner' role to user %d. Ownership transfer is not supported via this method.", userIDToUpdate)
	}

	// 5. Обновить роль
	query := `UPDATE SharedDatabaseUsers SET Role = ?, JoinedAt = ? WHERE SharedDatabaseId = ? AND UserId = ?`
	// JoinedAt обновляется, чтобы отразить "последнее изменение" участия/роли
	result, err := MainDB.Exec(query, newRole, time.Now(), sdbID, userIDToUpdate)
	if err != nil {
		return fmt.Errorf("failed to update role for user %d in shared DB ID %d: %w", userIDToUpdate, sdbID, err)
	}
	rowsAffected, _ := result.RowsAffected()
	if rowsAffected == 0 {
		return fmt.Errorf("user %d not found in shared DB ID %d to update role", userIDToUpdate, sdbID)
	}
	return nil
}

// DeleteSharedDatabase удаляет совместную БД и все связанные с ней записи.
// Только владелец может удалить БД.
func DeleteSharedDatabase(sdbID int64, currentUserID int64) error {
	tx, err := MainDB.Beginx() // Начинаем транзакцию
	if err != nil {
		return fmt.Errorf("failed to begin transaction for deleting shared DB ID %d: %w", sdbID, err)
	}
	defer tx.Rollback()

	// 1. Проверить, является ли currentUserID владельцем
	var ownerID int64
	queryOwner := `SELECT OwnerUserId FROM SharedDatabases WHERE Id = ?`
	err = tx.Get(&ownerID, queryOwner, sdbID)
	if err != nil {
		if err == sql.ErrNoRows {
			return fmt.Errorf("shared database with ID %d not found", sdbID)
		}
		return fmt.Errorf("failed to get owner for shared DB ID %d: %w", sdbID, err)
	}
	if ownerID != currentUserID {
		return fmt.Errorf("user %d is not the owner of shared DB ID %d and cannot delete it", currentUserID, sdbID)
	}

	// 2. Удалить все заметки, связанные с этой БД
	queryDeleteNotes := `DELETE FROM Notes WHERE DatabaseId = ?`
	_, err = tx.Exec(queryDeleteNotes, sdbID)
	if err != nil {
		return fmt.Errorf("failed to delete notes for shared DB ID %d: %w", sdbID, err)
	}

	// 3. Удалить все папки, связанные с этой БД
	queryDeleteFolders := `DELETE FROM Folders WHERE DatabaseId = ?`
	_, err = tx.Exec(queryDeleteFolders, sdbID)
	if err != nil {
		return fmt.Errorf("failed to delete folders for shared DB ID %d: %w", sdbID, err)
	}

	// 4. Удалить всех пользователей из SharedDatabaseUsers
	queryDeleteUsers := `DELETE FROM SharedDatabaseUsers WHERE SharedDatabaseId = ?`
	_, err = tx.Exec(queryDeleteUsers, sdbID)
	if err != nil {
		return fmt.Errorf("failed to delete users from shared DB ID %d: %w", sdbID, err)
	}

	// 5. Удалить саму SharedDatabase
	queryDeleteDb := `DELETE FROM SharedDatabases WHERE Id = ?`
	result, err := tx.Exec(queryDeleteDb, sdbID)
	if err != nil {
		return fmt.Errorf("failed to delete shared database with ID %d: %w", sdbID, err)
	}
	rowsAffected, _ := result.RowsAffected()
	if rowsAffected == 0 {
		// Это не должно произойти, если проверка владельца прошла успешно
		return fmt.Errorf("shared database with ID %d not found during final delete step", sdbID)
	}

	return tx.Commit()
}

// GetSharedDatabaseDetails извлекает детали SharedDatabase по ID без проверки доступа пользователя.
// Используется внутри других функций data слоя, где доступ уже проверен или не требуется.
func GetSharedDatabaseDetails(sdbID int64) (*models.SharedDatabase, error) {
	sdb := &models.SharedDatabase{}
	query := `SELECT Id, Name, OwnerUserId, CreatedAt, UpdatedAt FROM SharedDatabases WHERE Id = ?`
	err := MainDB.Get(sdb, query, sdbID)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, nil // Не найдено
		}
		return nil, fmt.Errorf("failed to get shared database details for ID %d: %w", sdbID, err)
	}
	return sdb, nil
}

// LeaveSharedDatabase удаляет пользователя из указанной совместной базы данных.
// Если пользователь является владельцем, операция не допускается.
func LeaveSharedDatabase(dbID int64, userID int64) error {
	// Проверяем, не является ли пользователь владельцем
	var ownerID int64
	err := MainDB.QueryRow("SELECT owner_user_id FROM shared_databases WHERE id = ?", dbID).Scan(&ownerID)
	if err != nil {
		if err == sql.ErrNoRows {
			return fmt.Errorf("база данных с ID %d не найдена", dbID)
		}
		return fmt.Errorf("ошибка при проверке владельца БД %d: %w", dbID, err)
	}

	if ownerID == userID {
		return fmt.Errorf("владелец не может покинуть совместную базу данных. Удалите базу данных или передайте права владения.")
	}

	// Удаляем пользователя из таблицы участников
	_, err = MainDB.Exec("DELETE FROM shared_database_users WHERE database_id = ? AND user_id = ?", dbID, userID)
	if err != nil {
		return fmt.Errorf("ошибка при удалении пользователя %d из совместной БД %d: %w", userID, dbID, err)
	}

	log.Printf("Пользователь %d покинул совместную базу данных %d", userID, dbID)
	return nil
}

// ImportSharedDatabase обрабатывает "импорт" совместной базы данных.
// На данный момент, это означает создание новой совместной БД с указанным именем (externalDbID)
// и назначение текущего пользователя ее владельцем, если БД с таким именем еще не существует.
// Если существует, возвращает информацию о ней, проверяя доступ.
func ImportSharedDatabase(externalDbIDStr string, userID int64) (*models.SharedDatabase, error) {
	db, err := MainDB.Beginx() // Начинаем транзакцию для атомарности операций
	if err != nil {
		return nil, fmt.Errorf("ImportSharedDatabase: failed to begin transaction: %w", err)
	}
	defer db.Rollback() // Откатываем, если что-то пошло не так

	// Попробуем найти существующую БД с таким именем, к которой у пользователя есть доступ
	// Это упрощение, в реальности externalDbID мог бы быть UUID или другой глобальный идентификатор
	// и логика поиска/связывания была бы сложнее.
	existingDBs, err := GetSharedDatabasesForUserByName(userID, externalDbIDStr) // Нужна новая функция
	if err != nil {
		return nil, fmt.Errorf("ошибка при поиске существующей БД '%s' для пользователя %d: %w", externalDbIDStr, userID, err)
	}

	if len(existingDBs) > 0 {
		// Если нашли одну или несколько, вернем первую (предполагая, что имена должны быть уникальны в контексте импорта)
		// или можно вернуть ошибку, если найдено много.
		// Важно: GetSharedDatabasesForUserByName должна вернуть БД, где пользователь уже участник.
		// Но при импорте, возможно, мы хотим подключить его к БД, созданной другим?
		// Текущая логика клиента просто вызывает /import и ожидает получить CollaborativeDatabase.
		// Для упрощения, если есть доступная с таким именем - возвращаем ее.
		// Если такой логики нет, то нужно создавать новую или обрабатывать иначе.
		// ПОКА ПРОСТО: если есть доступная с таким именем - возвращаем ее.
		db.Commit() // Коммитим пустую транзакцию, так как ничего не меняли
		return &existingDBs[0], nil
	}

	// Если не нашли, создаем новую
	now := time.Now()
	newSharedDb := &models.SharedDatabase{
		Name:        externalDbIDStr, // Используем external ID как имя
		OwnerUserId: userID,
		CreatedAt:   now,
		UpdatedAt:   now,
	}

	queryDb := `INSERT INTO SharedDatabases (Name, OwnerUserId, CreatedAt, UpdatedAt)
	            VALUES (?, ?, ?, ?)`
	result, err := db.Exec(queryDb, newSharedDb.Name, newSharedDb.OwnerUserId, newSharedDb.CreatedAt, newSharedDb.UpdatedAt)
	if err != nil {
		return nil, fmt.Errorf("ошибка при создании новой совместной БД '%s': %w", newSharedDb.Name, err)
	}

	sdbID, err := result.LastInsertId()
	if err != nil {
		return nil, fmt.Errorf("ошибка при получении ID для новой совместной БД '%s': %w", newSharedDb.Name, err)
	}
	newSharedDb.Id = sdbID

	// Добавляем владельца в таблицу SharedDatabaseUsers
	queryUser := `INSERT INTO SharedDatabaseUsers (SharedDatabaseId, UserId, Role, JoinedAt)
	               VALUES (?, ?, ?, ?)`
	_, err = db.Exec(queryUser, sdbID, newSharedDb.OwnerUserId, models.RoleOwner, now)
	if err != nil {
		return nil, fmt.Errorf("ошибка при добавлении владельца %d в SharedDatabaseUsers для БД %d: %w", newSharedDb.OwnerUserId, sdbID, err)
	}

	if err = db.Commit(); err != nil {
		return nil, fmt.Errorf("ошибка при коммите транзакции для импорта БД '%s': %w", newSharedDb.Name, err)
	}

	log.Printf("Пользователь %d импортировал/создал совместную базу данных '%s' (ID: %d)", userID, newSharedDb.Name, sdbID)
	return newSharedDb, nil // Возвращаем созданную/найденную БД
}

// GetSharedDatabasesForUserByName (НОВАЯ ВСПОМОГАТЕЛЬНАЯ ФУНКЦИЯ)
// извлекает все совместные БД по имени, к которым пользователь имеет доступ.
func GetSharedDatabasesForUserByName(userID int64, name string) ([]models.SharedDatabase, error) {
	var dbs []models.SharedDatabase
	query := `SELECT sd.Id, sd.Name, sd.OwnerUserId, sd.CreatedAt, sd.UpdatedAt
	          FROM SharedDatabases sd
	          JOIN SharedDatabaseUsers sdu ON sd.Id = sdu.SharedDatabaseId
	          WHERE sdu.UserId = ? AND sd.Name = ?
	          ORDER BY sd.Name ASC`
	err := MainDB.Select(&dbs, query, userID, name)
	if err != nil {
		return nil, fmt.Errorf("failed to get shared databases for user ID %d by name '%s': %w", userID, name, err)
	}
	return dbs, nil
}

// ExportSharedDatabase собирает все данные для указанной совместной БД для экспорта.
func ExportSharedDatabase(dbID int64, userID int64) (*models.BackupData, error) {
	// 1. Проверить доступ пользователя к базе данных (например, является ли он участником)
	role, err := GetUserRoleInSharedDatabase(dbID, userID)
	if err != nil {
		return nil, fmt.Errorf("ошибка проверки доступа пользователя %d к БД %d: %w", userID, dbID, err)
	}
	if role == nil {
		return nil, fmt.Errorf("пользователь %d не имеет доступа к БД %d", userID, dbID)
	}

	// 2. Собрать данные
	backupData := &models.BackupData{}

	// Получение папок
	// Предполагается, что есть функция GetFoldersForDatabase(dbID int64) ([]models.Folder, error)
	// Если ее нет, нужно будет создать или адаптировать существующую GetFolders.
	// Для примера, пока оставим так, но это потребует доработки.
	folders, err := GetFoldersForDatabase(dbID) // ЗАГЛУШКА - НУЖНА РЕАЛИЗАЦИЯ/ПРОВЕРКА
	if err != nil {
		return nil, fmt.Errorf("ошибка получения папок для БД %d: %w", dbID, err)
	}
	backupData.Folders = folders

	// Получение заметок
	// Аналогично, нужна GetNotesForDatabase(dbID int64) ([]models.Note, error)
	notes, err := GetNotesForDatabase(dbID) // ЗАГЛУШКА
	if err != nil {
		return nil, fmt.Errorf("ошибка получения заметок для БД %d: %w", dbID, err)
	}
	backupData.Notes = notes

	// Получение записей расписания
	// Нужна GetScheduleEntriesForDatabase(dbID int64) ([]models.ScheduleEntry, error)
	scheduleEntries, err := GetScheduleEntriesForDatabase(dbID) // ЗАГЛУШКА
	if err != nil {
		return nil, fmt.Errorf("ошибка получения записей расписания для БД %d: %w", dbID, err)
	}
	backupData.ScheduleEntries = scheduleEntries

	// Получение заметок с доски
	// Нужна GetPinboardNotesForDatabase(dbID int64) ([]models.PinboardNote, error)
	pinboardNotes, err := GetPinboardNotesForDatabase(dbID) // ЗАГЛУШКА
	if err != nil {
		return nil, fmt.Errorf("ошибка получения заметок с доски для БД %d: %w", dbID, err)
	}
	backupData.PinboardNotes = pinboardNotes

	// Получение соединений (если они привязаны к БД)
	// Нужна GetConnectionsForDatabase(dbID int64) ([]models.Connection, error)
	connections, err := GetConnectionsForDatabase(dbID) // ЗАГЛУШКА
	if err != nil {
		return nil, fmt.Errorf("ошибка получения соединений для БД %d: %w", dbID, err)
	}
	backupData.Connections = connections

	// Получение изображений
	// Это сложнее, так как изображения связаны с заметками.
	// Нужно будет получить все ID заметок из notes, а затем для них получить изображения.
	// Нужна GetImagesForNoteIDs(noteIDs []int64) ([]models.NoteImage, error)
	var allNoteImages []models.NoteImage
	if len(notes) > 0 {
		noteIDs := make([]int64, len(notes))
		for i, note := range notes {
			noteIDs[i] = note.ID // Убедитесь, что у модели Note есть поле ID
		}
		images, err := GetImagesForNoteIDs(noteIDs) // ЗАГЛУШКА
		if err != nil {
			return nil, fmt.Errorf("ошибка получения изображений для заметок БД %d: %w", dbID, err)
		}
		allNoteImages = images
	}
	backupData.NoteImages = allNoteImages

	log.Printf("Данные для экспорта БД %d собраны для пользователя %d", dbID, userID)
	return backupData, nil
}

// RestoreSharedDatabaseFromBackup перезаписывает данные совместной БД из предоставленного бэкапа.
// Требуются права на запись (владелец или редактор).
func RestoreSharedDatabaseFromBackup(dbID int64, userID int64, backup *models.BackupData) error {
	// 1. Проверить права доступа (владелец или редактор)
	role, err := GetUserRoleInSharedDatabase(dbID, userID)
	if err != nil {
		return fmt.Errorf("ошибка проверки доступа пользователя %d к БД %d: %w", userID, dbID, err)
	}
	if role == nil || (*role != models.RoleOwner && *role != models.RoleEditor) {
		return fmt.Errorf("пользователь %d не имеет прав на запись в БД %d", userID, dbID)
	}

	tx, err := MainDB.Beginx()
	if err != nil {
		return fmt.Errorf("RestoreFromBackup: failed to begin transaction for DB %d: %w", dbID, err)
	}
	defer tx.Rollback()

	// 2. Очистить существующие данные для этой БД
	// TODO: Добавить удаление файлов изображений с диска перед удалением записей из NoteImages

	// 2.1 Удалить изображения, связанные с заметками этой БД
	var noteIDsForDeletion []int64
	queryNoteIDs := `SELECT Id FROM Notes WHERE DatabaseId = ?`
	err = tx.Select(&noteIDsForDeletion, queryNoteIDs, dbID)
	if err != nil && err != sql.ErrNoRows {
		return fmt.Errorf("ошибка получения ID заметок для удаления изображений в БД %d: %w", dbID, err)
	}
	if len(noteIDsForDeletion) > 0 {
		// Здесь хорошо бы получить пути к файлам перед удалением записей, чтобы удалить и файлы
		// Пока оставляем только удаление записей
		queryDeleteImages, args, inErr := sqlx.In(`DELETE FROM NoteImages WHERE NoteId IN (?) AND DatabaseId = ?`, noteIDsForDeletion, dbID) // Добавил DatabaseId для точности
		if inErr != nil {
			return fmt.Errorf("ошибка построения запроса удаления изображений для БД %d: %w", dbID, inErr)
		}
		queryDeleteImages = tx.Rebind(queryDeleteImages)
		if _, execErr := tx.Exec(queryDeleteImages, args...); execErr != nil {
			return fmt.Errorf("ошибка удаления записей изображений для БД %d: %w", dbID, execErr)
		}
	}

	// 2.2 Удалить соединения
	if _, err = tx.Exec(`DELETE FROM Connections WHERE DatabaseId = ?`, dbID); err != nil {
		return fmt.Errorf("ошибка удаления соединений для БД %d: %w", dbID, err)
	}
	// 2.3 Удалить заметки с доски
	if _, err = tx.Exec(`DELETE FROM PinboardNotes WHERE DatabaseId = ?`, dbID); err != nil {
		return fmt.Errorf("ошибка удаления заметок с доски для БД %d: %w", dbID, err)
	}
	// 2.4 Удалить записи расписания
	if _, err = tx.Exec(`DELETE FROM ScheduleEntries WHERE DatabaseId = ?`, dbID); err != nil {
		return fmt.Errorf("ошибка удаления записей расписания для БД %d: %w", dbID, err)
	}
	// 2.5 Удалить заметки
	if _, err = tx.Exec(`DELETE FROM Notes WHERE DatabaseId = ?`, dbID); err != nil {
		return fmt.Errorf("ошибка удаления заметок для БД %d: %w", dbID, err)
	}
	// 2.6 Удалить папки
	if _, err = tx.Exec(`DELETE FROM Folders WHERE DatabaseId = ?`, dbID); err != nil {
		return fmt.Errorf("ошибка удаления папок для БД %d: %w", dbID, err)
	}

	// 3. Вставить новые данные
	// Для каждой категории данных, проходимся по списку и вставляем.
	// Важно: присваиваем userID и dbID каждой записи перед вставкой.
	// Это упрощенная вставка, в реальности нужно обрабатывать ParentId для папок и т.д.

	for _, folder := range backup.Folders {
		folder.DatabaseID = dbID
		query := `INSERT INTO Folders (Name, ParentId, CreatedAt, UpdatedAt, DatabaseId, Color, IsExpanded)
		          VALUES (?, ?, ?, ?, ?, ?, ?)`
		// Убедимся, что CreatedAt и UpdatedAt не нулевые (хотя клиент должен их слать)
		if folder.CreatedAt.IsZero() {
			folder.CreatedAt = time.Now()
		}
		if folder.UpdatedAt.IsZero() {
			folder.UpdatedAt = time.Now()
		}

		_, err = tx.Exec(query, folder.Name, folder.ParentID, folder.CreatedAt, folder.UpdatedAt, folder.DatabaseID, folder.Color, folder.IsExpanded)
		if err != nil {
			return fmt.Errorf("ошибка вставки папки %s: %w", folder.Name, err)
		}
	}

	for _, note := range backup.Notes {
		note.DatabaseID = dbID
		// Убедимся, что CreatedAt и UpdatedAt не нулевые
		if note.CreatedAt.IsZero() {
			note.CreatedAt = time.Now()
		}
		if note.UpdatedAt.IsZero() {
			note.UpdatedAt = time.Now()
		}

		// Вызываем UpdateJsonProperties, чтобы ImagesJson и MetadataJson были заполнены,
		// если клиент прислал данные в полях Images/Metadata, а не в *Json.
		// Хотя по нашей логике, клиент должен слать именно *Json поля (images, metadata в JSON)
		// которые мы переименовали в модели.
		// n.ImagesJson (тег json:"images") и n.MetadataJson (тег json:"metadata") должны заполниться при анмаршалинге.

		query := `INSERT INTO Notes (Title, Content, CreatedAt, UpdatedAt, FolderId, DatabaseId, ImagesJson, MetadataJson, ContentJson)
		          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`
		_, err = tx.Exec(query, note.Title, note.Content, note.CreatedAt, note.UpdatedAt, note.FolderID, note.DatabaseID,
			note.ImagesJson, note.MetadataJson, note.ContentJson)
		if err != nil {
			return fmt.Errorf("ошибка вставки заметки %s: %w", note.Title, err)
		}
	}

	// Восстановление записей расписания
	for _, entry := range backup.ScheduleEntries {
		entry.DatabaseId = dbID
		if entry.CreatedAt.IsZero() {
			entry.CreatedAt = time.Now()
		}
		if entry.UpdatedAt.IsZero() {
			entry.UpdatedAt = time.Now()
		}
		query := `INSERT INTO ScheduleEntries (Time, Date, Note, DynamicFieldsJson, RecurrenceJson, CreatedAt, UpdatedAt, DatabaseId)
		          VALUES (?, ?, ?, ?, ?, ?, ?, ?)`
		_, err = tx.Exec(query, entry.Time, entry.Date, entry.Note, entry.DynamicFieldsJson, entry.RecurrenceJson, entry.CreatedAt, entry.UpdatedAt, entry.DatabaseId)
		if err != nil {
			log.Printf("Ошибка вставки записи расписания: %+v\n", entry)
			return fmt.Errorf("ошибка вставки записи расписания (ID: %d): %w", entry.Id, err)
		}
	}

	for _, pNote := range backup.PinboardNotes {
		pNote.DatabaseId = dbID
		if pNote.CreatedAt.IsZero() {
			pNote.CreatedAt = time.Now()
		}
		if pNote.UpdatedAt.IsZero() {
			pNote.UpdatedAt = time.Now()
		}
		query := `INSERT INTO PinboardNotes (Title, Content, CreatedAt, UpdatedAt, DatabaseId, PositionX, PositionY, Width, Height, BackgroundColor, IconCodePoint)
		          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
		_, err = tx.Exec(query, pNote.Title, pNote.Content, pNote.CreatedAt, pNote.UpdatedAt, pNote.DatabaseId,
			pNote.PositionX, pNote.PositionY, pNote.Width, pNote.Height, pNote.BackgroundColor, pNote.IconCodePoint)
		if err != nil {
			return fmt.Errorf("ошибка вставки заметки с доски %s: %w", pNote.Title, err)
		}
	}

	for _, conn := range backup.Connections {
		conn.DatabaseId = dbID
		if conn.CreatedAt.IsZero() {
			conn.CreatedAt = time.Now()
		}
		if conn.UpdatedAt.IsZero() {
			conn.UpdatedAt = time.Now()
		}
		query := `INSERT INTO Connections (SourceNoteId, TargetNoteId, Label, CreatedAt, UpdatedAt, DatabaseId, ConnectionColor)
		          VALUES (?, ?, ?, ?, ?, ?, ?)`
		_, err = tx.Exec(query, conn.FromNoteId, conn.ToNoteId, conn.Name, conn.CreatedAt, conn.UpdatedAt, conn.DatabaseId, conn.ConnectionColor)
		if err != nil {
			return fmt.Errorf("ошибка вставки соединения для заметки %d: %w", conn.FromNoteId, err)
		}
	}

	// Вставка изображений с сохранением файлов
	for _, image := range backup.NoteImages {
		image.DatabaseId = dbID // Устанавливаем ID текущей БД

		if image.FileName == "" {
			log.Printf("Предупреждение: RestoreBackup: пропуск изображения для NoteId %d из-за отсутствия FileName", image.NoteId)
			continue
		}
		// ImageData может быть пустой, если изображение уже есть на сервере (не наша текущая логика, но для будущего)
		// или если это просто ссылка без данных. Для бэкапа ожидаем ImageData.
		if image.ImageData == "" {
			log.Printf("Предупреждение: RestoreBackup: пропуск изображения '%s' для NoteId %d из-за отсутствия ImageData", image.FileName, image.NoteId)
			continue
		}

		decodedImageData, decErr := base64.StdEncoding.DecodeString(image.ImageData)
		if decErr != nil {
			log.Printf("Ошибка декодирования ImageData для '%s' (NoteId %d): %v. Пропуск.", image.FileName, image.NoteId, decErr)
			continue
		}

		imageDir := filepath.Join("uploads", "shared_db_images", fmt.Sprintf("%d", dbID))
		if mkdirErr := os.MkdirAll(imageDir, 0755); mkdirErr != nil {
			return fmt.Errorf("ошибка создания директории для изображений %s: %w", imageDir, mkdirErr)
		}

		serverImagePath := filepath.Join(imageDir, image.FileName)

		if writeErr := ioutil.WriteFile(serverImagePath, decodedImageData, 0644); writeErr != nil {
			return fmt.Errorf("ошибка сохранения файла изображения %s: %w", serverImagePath, writeErr)
		}

		if image.CreatedAt.IsZero() {
			image.CreatedAt = time.Now()
		}
		image.UpdatedAt = time.Now()

		query := `INSERT INTO NoteImages (NoteId, FileName, ImagePath, CreatedAt, UpdatedAt, DatabaseId)
		          VALUES (?, ?, ?, ?, ?, ?)`
		_, err = tx.Exec(query, image.NoteId, image.FileName, serverImagePath, image.CreatedAt, image.UpdatedAt, image.DatabaseId)
		if err != nil {
			os.Remove(serverImagePath)
			return fmt.Errorf("ошибка вставки записи для изображения %s в БД: %w", image.FileName, err)
		}
	}

	// Обновляем UpdatedAt для самой SharedDatabase
	if _, err = tx.Exec(`UPDATE SharedDatabases SET UpdatedAt = ? WHERE Id = ?`, time.Now(), dbID); err != nil {
		return fmt.Errorf("ошибка обновления UpdatedAt для БД %d: %w", dbID, err)
	}

	if err = tx.Commit(); err != nil {
		return fmt.Errorf("RestoreFromBackup: failed to commit transaction for DB %d: %w", dbID, err)
	}

	log.Printf("Данные для БД %d восстановлены из бэкапа пользователем %d", dbID, userID)
	return nil
}

// TODO: Добавить функции RemoveUserFromSharedDatabase, UpdateUserRoleInSharedDatabase, DeleteSharedDatabase
