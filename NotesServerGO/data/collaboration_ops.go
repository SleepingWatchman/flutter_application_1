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
	err := MainDB.QueryRow("SELECT OwnerUserId FROM SharedDatabases WHERE Id = ?", dbID).Scan(&ownerID)
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
	_, err = MainDB.Exec("DELETE FROM SharedDatabaseUsers WHERE SharedDatabaseId = ? AND UserId = ?", dbID, userID)
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
	log.Printf("ExportSharedDatabase: начало экспорта БД %d для пользователя %d", dbID, userID)

	// 1. Проверить доступ пользователя к базе данных (например, является ли он участником)
	role, err := GetUserRoleInSharedDatabase(dbID, userID)
	if err != nil {
		log.Printf("ExportSharedDatabase: ошибка проверки доступа пользователя %d к БД %d: %v", userID, dbID, err)
		return nil, fmt.Errorf("ошибка проверки доступа пользователя %d к БД %d: %w", userID, dbID, err)
	}
	if role == nil {
		log.Printf("ExportSharedDatabase: пользователь %d не имеет доступа к БД %d", userID, dbID)
		return nil, fmt.Errorf("пользователь %d не имеет доступа к БД %d", userID, dbID)
	}
	log.Printf("ExportSharedDatabase: роль пользователя %d в БД %d: %s", userID, dbID, *role)

	// 2. Собрать данные
	backupData := &models.BackupData{}

	// Получение папок
	log.Printf("ExportSharedDatabase: получение папок для БД %d", dbID)
	folders, err := GetFoldersForDatabase(dbID)
	if err != nil {
		log.Printf("ExportSharedDatabase: ошибка получения папок для БД %d: %v", dbID, err)
		return nil, fmt.Errorf("ошибка получения папок для БД %d: %w", dbID, err)
	}
	backupData.Folders = folders
	log.Printf("ExportSharedDatabase: получено %d папок для БД %d", len(folders), dbID)

	// Получение заметок
	log.Printf("ExportSharedDatabase: получение заметок для БД %d", dbID)
	notes, err := GetNotesForDatabase(dbID)
	if err != nil {
		log.Printf("ExportSharedDatabase: ошибка получения заметок для БД %d: %v", dbID, err)
		return nil, fmt.Errorf("ошибка получения заметок для БД %d: %w", dbID, err)
	}
	backupData.Notes = notes
	log.Printf("ExportSharedDatabase: получено %d заметок для БД %d", len(notes), dbID)

	// Получение записей расписания
	log.Printf("ExportSharedDatabase: получение записей расписания для БД %d", dbID)
	scheduleEntries, err := GetScheduleEntriesForDatabase(dbID)
	if err != nil {
		log.Printf("ExportSharedDatabase: ошибка получения записей расписания для БД %d: %v", dbID, err)
		return nil, fmt.Errorf("ошибка получения записей расписания для БД %d: %w", dbID, err)
	}
	backupData.ScheduleEntries = scheduleEntries
	log.Printf("ExportSharedDatabase: получено %d записей расписания для БД %d", len(scheduleEntries), dbID)

	// Получение заметок с доски
	log.Printf("ExportSharedDatabase: получение заметок с доски для БД %d", dbID)
	pinboardNotes, err := GetPinboardNotesForDatabase(dbID)
	if err != nil {
		log.Printf("ExportSharedDatabase: ошибка получения заметок с доски для БД %d: %v", dbID, err)
		return nil, fmt.Errorf("ошибка получения заметок с доски для БД %d: %w", dbID, err)
	}
	backupData.PinboardNotes = pinboardNotes
	log.Printf("ExportSharedDatabase: получено %d заметок с доски для БД %d", len(pinboardNotes), dbID)

	// Получение соединений (если они привязаны к БД)
	log.Printf("ExportSharedDatabase: получение соединений для БД %d", dbID)
	connections, err := GetConnectionsForDatabase(dbID)
	if err != nil {
		log.Printf("ExportSharedDatabase: ошибка получения соединений для БД %d: %v", dbID, err)
		return nil, fmt.Errorf("ошибка получения соединений для БД %d: %w", dbID, err)
	}
	backupData.Connections = connections
	log.Printf("ExportSharedDatabase: получено %d соединений для БД %d", len(connections), dbID)

	// Получение изображений
	var allNoteImages []models.NoteImage
	if len(notes) > 0 {
		log.Printf("ExportSharedDatabase: получение изображений для %d заметок БД %d", len(notes), dbID)
		noteIDs := make([]int64, len(notes))
		for i, note := range notes {
			noteIDs[i] = note.ID
		}
		images, err := GetImagesForNoteIDs(noteIDs)
		if err != nil {
			log.Printf("ExportSharedDatabase: ошибка получения изображений для заметок БД %d: %v", dbID, err)
			return nil, fmt.Errorf("ошибка получения изображений для заметок БД %d: %w", dbID, err)
		}

		// ✅ КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: Загружаем ImageData с диска для каждого изображения
		for i := range images {
			if images[i].ImagePath != "" {
				fullServerPath := images[i].ImagePath
				// Если ImagePath хранится как относительный от корня проекта
				if !filepath.IsAbs(fullServerPath) {
					wd, _ := os.Getwd()
					fullServerPath = filepath.Join(wd, fullServerPath)
				}

				if _, statErr := os.Stat(fullServerPath); statErr == nil {
					imgBytes, readErr := ioutil.ReadFile(fullServerPath)
					if readErr != nil {
						log.Printf("ExportSharedDatabase Warning: Не удалось прочитать файл изображения %s: %v", fullServerPath, readErr)
						images[i].ImageData = "" // Очищаем, если не удалось прочитать
					} else {
						images[i].ImageData = base64.StdEncoding.EncodeToString(imgBytes)
						log.Printf("ExportSharedDatabase: Загружены данные изображения %s, размер: %d байт", images[i].FileName, len(imgBytes))
					}
				} else {
					log.Printf("ExportSharedDatabase Warning: Файл изображения %s не найден на сервере.", fullServerPath)
					images[i].ImageData = ""
				}
			}
		}

		allNoteImages = images
		log.Printf("ExportSharedDatabase: получено %d изображений для БД %d", len(allNoteImages), dbID)
	} else {
		log.Printf("ExportSharedDatabase: нет заметок, изображения не получаем для БД %d", dbID)
	}
	backupData.NoteImages = allNoteImages

	log.Printf("ExportSharedDatabase: данные для экспорта БД %d собраны для пользователя %d: %d папок, %d заметок, %d записей расписания, %d заметок доски, %d соединений, %d изображений",
		dbID, userID, len(backupData.Folders), len(backupData.Notes), len(backupData.ScheduleEntries),
		len(backupData.PinboardNotes), len(backupData.Connections), len(backupData.NoteImages))
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

		_, err = tx.Exec(query, folder.Name, folder.ParentID, folder.CreatedAt, folder.UpdatedAt, folder.DatabaseID, folder.Color, bool(folder.IsExpanded))
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

// SharedDatabaseWithUsers представляет совместную базу данных с информацией о пользователях
type SharedDatabaseWithUsers struct {
	models.SharedDatabase
	Users []models.SharedDatabaseUser `json:"users"`
}

// GetSharedDatabasesWithUsersForUser извлекает все совместные БД с информацией о пользователях
func GetSharedDatabasesWithUsersForUser(userID int64) ([]SharedDatabaseWithUsers, error) {
	// Сначала получаем базы данных
	dbs, err := GetSharedDatabasesForUser(userID)
	if err != nil {
		return nil, err
	}

	var result []SharedDatabaseWithUsers
	for _, db := range dbs {
		// Получаем пользователей для каждой базы данных
		users, err := GetUsersInSharedDatabase(db.Id)
		if err != nil {
			log.Printf("Ошибка при получении пользователей для БД %d: %v", db.Id, err)
			// Продолжаем с пустым списком пользователей
			users = []models.SharedDatabaseUser{}
		}

		result = append(result, SharedDatabaseWithUsers{
			SharedDatabase: db,
			Users:          users,
		})
	}

	return result, nil
}

// GetUsersInSharedDatabase возвращает всех пользователей в указанной совместной БД
func GetUsersInSharedDatabase(sdbID int64) ([]models.SharedDatabaseUser, error) {
	var users []models.SharedDatabaseUser
	query := `SELECT SharedDatabaseId, UserId, Role, JoinedAt 
	          FROM SharedDatabaseUsers 
	          WHERE SharedDatabaseId = ? 
	          ORDER BY JoinedAt ASC`
	err := MainDB.Select(&users, query, sdbID)
	if err != nil {
		return nil, fmt.Errorf("failed to get users for shared DB ID %d: %w", sdbID, err)
	}
	return users, nil
}

// GetUsersInSharedDatabaseWithDetails получает пользователей совместной БД с полными данными
func GetUsersInSharedDatabaseWithDetails(sdbID int64) ([]models.SharedDatabaseUserWithDetails, error) {
	var users []models.SharedDatabaseUserWithDetails

	// Сначала получаем пользователей из SharedDatabaseUsers
	var sharedUsers []models.SharedDatabaseUser
	sharedQuery := `
		SELECT SharedDatabaseId, UserId, Role, JoinedAt
		FROM SharedDatabaseUsers 
		WHERE SharedDatabaseId = ?
		ORDER BY JoinedAt ASC`

	err := MainDB.Select(&sharedUsers, sharedQuery, sdbID)
	if err != nil {
		return nil, fmt.Errorf("failed to get shared database users for DB ID %d: %w", sdbID, err)
	}

	// Теперь для каждого пользователя получаем данные из AuthDB
	for _, sharedUser := range sharedUsers {
		var user models.User
		userQuery := `SELECT Id, Email, DisplayName, PhotoUrl FROM Users WHERE Id = ?`
		err := AuthDB.Get(&user, userQuery, sharedUser.UserId)
		if err != nil {
			// Если пользователь не найден в AuthDB, пропускаем его
			if err == sql.ErrNoRows {
				continue
			}
			return nil, fmt.Errorf("failed to get user details for user ID %d: %w", sharedUser.UserId, err)
		}

		// Создаем объект с полными данными
		var displayName *string
		if user.DisplayName != "" {
			displayName = &user.DisplayName
		}

		var photoURL *string
		if user.PhotoUrl != "" {
			photoURL = &user.PhotoUrl
		}

		userWithDetails := models.SharedDatabaseUserWithDetails{
			SharedDatabaseUser: models.SharedDatabaseUser{
				SharedDatabaseId: sharedUser.SharedDatabaseId,
				UserId:           sharedUser.UserId,
				Role:             sharedUser.Role,
				JoinedAt:         sharedUser.JoinedAt,
			},
			Email:       user.Email,
			DisplayName: displayName,
			PhotoURL:    photoURL,
		}
		users = append(users, userWithDetails)
	}

	return users, nil
}

// CreateInvitation создает приглашение в совместную базу данных
func CreateInvitation(sdbID int64, inviterUserID int64, inviteeEmail string, role models.SharedDatabaseUserRole) error {
	// Проверяем, не существует ли уже активное приглашение
	var count int
	checkQuery := `SELECT COUNT(*) FROM SharedDatabaseInvitations 
	               WHERE SharedDatabaseId = ? AND InviteeEmail = ? AND Status = 'pending'`
	err := MainDB.Get(&count, checkQuery, sdbID, inviteeEmail)
	if err != nil {
		return fmt.Errorf("failed to check existing invitations: %w", err)
	}
	if count > 0 {
		return fmt.Errorf("активное приглашение для %s уже существует", inviteeEmail)
	}

	// Проверяем, не является ли пользователь уже участником
	var userID int64
	userQuery := `SELECT Id FROM Users WHERE Email = ?`
	err = AuthDB.Get(&userID, userQuery, inviteeEmail)
	if err == nil {
		// Пользователь существует, проверяем участие
		existingRole, _ := GetUserRoleInSharedDatabase(sdbID, userID)
		if existingRole != nil {
			return fmt.Errorf("пользователь %s уже является участником базы данных", inviteeEmail)
		}
	}

	// Создаем приглашение
	now := time.Now()
	expiresAt := now.Add(7 * 24 * time.Hour) // Приглашение действует 7 дней

	query := `INSERT INTO SharedDatabaseInvitations 
	          (SharedDatabaseId, InviterUserId, InviteeEmail, Role, Status, CreatedAt, ExpiresAt)
	          VALUES (?, ?, ?, ?, 'pending', ?, ?)`

	_, err = MainDB.Exec(query, sdbID, inviterUserID, inviteeEmail, role, now, expiresAt)
	if err != nil {
		return fmt.Errorf("failed to create invitation: %w", err)
	}

	return nil
}

// GetPendingInvitations получает ожидающие приглашения для пользователя по email
func GetPendingInvitations(userEmail string) ([]models.SharedDatabaseInvitation, error) {
	var invitations []models.SharedDatabaseInvitation
	query := `SELECT Id, SharedDatabaseId, InviterUserId, InviteeEmail, Role, Status, CreatedAt, ExpiresAt
	          FROM SharedDatabaseInvitations 
	          WHERE InviteeEmail = ? AND Status = 'pending' AND ExpiresAt > ?
	          ORDER BY CreatedAt DESC`

	err := MainDB.Select(&invitations, query, userEmail, time.Now())
	if err != nil {
		return nil, fmt.Errorf("failed to get pending invitations for %s: %w", userEmail, err)
	}
	return invitations, nil
}

// AcceptInvitation принимает приглашение в совместную базу данных
func AcceptInvitation(invitationID int64, userID int64) error {
	tx, err := MainDB.Beginx()
	if err != nil {
		return fmt.Errorf("failed to begin transaction: %w", err)
	}
	defer tx.Rollback()

	// Получаем приглашение
	var invitation models.SharedDatabaseInvitation
	query := `SELECT Id, SharedDatabaseId, InviterUserId, InviteeEmail, Role, Status, CreatedAt, ExpiresAt
	          FROM SharedDatabaseInvitations WHERE Id = ? AND Status = 'pending'`
	err = tx.Get(&invitation, query, invitationID)
	if err != nil {
		if err == sql.ErrNoRows {
			return fmt.Errorf("приглашение не найдено или уже обработано")
		}
		return fmt.Errorf("failed to get invitation: %w", err)
	}

	// Проверяем срок действия
	if time.Now().After(invitation.ExpiresAt) {
		return fmt.Errorf("приглашение истекло")
	}

	// Проверяем email пользователя (используем AuthDB вместо MainDB)
	var userEmail string
	userQuery := `SELECT Email FROM Users WHERE Id = ?`
	err = AuthDB.Get(&userEmail, userQuery, userID)
	if err != nil {
		return fmt.Errorf("failed to get user email: %w", err)
	}
	if userEmail != invitation.InviteeEmail {
		return fmt.Errorf("приглашение предназначено для другого email")
	}

	// Добавляем пользователя в базу данных
	addUserQuery := `INSERT INTO SharedDatabaseUsers (SharedDatabaseId, UserId, Role, JoinedAt)
	                 VALUES (?, ?, ?, ?)`
	_, err = tx.Exec(addUserQuery, invitation.SharedDatabaseId, userID, invitation.Role, time.Now())
	if err != nil {
		return fmt.Errorf("failed to add user to shared database: %w", err)
	}

	// Обновляем статус приглашения
	updateQuery := `UPDATE SharedDatabaseInvitations SET Status = 'accepted' WHERE Id = ?`
	_, err = tx.Exec(updateQuery, invitationID)
	if err != nil {
		return fmt.Errorf("failed to update invitation status: %w", err)
	}

	return tx.Commit()
}

// DeclineInvitation отклоняет приглашение в совместную базу данных
func DeclineInvitation(invitationID int64, userID int64) error {
	// Получаем приглашение для проверки email
	var invitation models.SharedDatabaseInvitation
	query := `SELECT Id, SharedDatabaseId, InviterUserId, InviteeEmail, Role, Status, CreatedAt, ExpiresAt
	          FROM SharedDatabaseInvitations WHERE Id = ? AND Status = 'pending'`
	err := MainDB.Get(&invitation, query, invitationID)
	if err != nil {
		if err == sql.ErrNoRows {
			return fmt.Errorf("приглашение не найдено или уже обработано")
		}
		return fmt.Errorf("failed to get invitation: %w", err)
	}

	// Проверяем email пользователя (используем AuthDB вместо MainDB)
	var userEmail string
	userQuery := `SELECT Email FROM Users WHERE Id = ?`
	err = AuthDB.Get(&userEmail, userQuery, userID)
	if err != nil {
		return fmt.Errorf("failed to get user email: %w", err)
	}
	if userEmail != invitation.InviteeEmail {
		return fmt.Errorf("приглашение предназначено для другого email")
	}

	// Обновляем статус приглашения
	updateQuery := `UPDATE SharedDatabaseInvitations SET Status = 'declined' WHERE Id = ?`
	_, err = MainDB.Exec(updateQuery, invitationID)
	if err != nil {
		return fmt.Errorf("failed to update invitation status: %w", err)
	}

	return nil
}

// GetDatabaseVersion получает текущую версию базы данных
func GetDatabaseVersion(sdbID int64) (string, error) {
	// Сначала проверяем, существует ли колонка Version
	var columnExists bool
	checkColumnQuery := `SELECT COUNT(*) FROM pragma_table_info('SharedDatabases') WHERE name='Version'`
	err := MainDB.Get(&columnExists, checkColumnQuery)
	if err != nil {
		return "", fmt.Errorf("failed to check Version column existence: %w", err)
	}

	// Если колонки нет, добавляем её
	if !columnExists {
		alterQuery := `ALTER TABLE SharedDatabases ADD COLUMN Version TEXT DEFAULT '1.0.0'`
		_, err = MainDB.Exec(alterQuery)
		if err != nil {
			return "", fmt.Errorf("failed to add Version column: %w", err)
		}
		log.Printf("Добавлена колонка Version в таблицу SharedDatabases")
	}

	// Проверяем, существует ли колонка LastSync
	checkLastSyncQuery := `SELECT COUNT(*) FROM pragma_table_info('SharedDatabases') WHERE name='LastSync'`
	err = MainDB.Get(&columnExists, checkLastSyncQuery)
	if err != nil {
		return "", fmt.Errorf("failed to check LastSync column existence: %w", err)
	}

	// Если колонки нет, добавляем её
	if !columnExists {
		// SQLite не поддерживает CURRENT_TIMESTAMP как DEFAULT при ALTER TABLE
		// Добавляем колонку с NULL по умолчанию, затем обновляем существующие записи
		alterQuery := `ALTER TABLE SharedDatabases ADD COLUMN LastSync DATETIME`
		_, err = MainDB.Exec(alterQuery)
		if err != nil {
			return "", fmt.Errorf("failed to add LastSync column: %w", err)
		}

		// Обновляем существующие записи
		updateQuery := `UPDATE SharedDatabases SET LastSync = datetime('now') WHERE LastSync IS NULL`
		_, err = MainDB.Exec(updateQuery)
		if err != nil {
			return "", fmt.Errorf("failed to update LastSync values: %w", err)
		}

		log.Printf("Добавлена колонка LastSync в таблицу SharedDatabases")
	}

	// Теперь получаем версию
	var version string
	query := `SELECT COALESCE(Version, '1.0.0') FROM SharedDatabases WHERE Id = ?`
	err = MainDB.Get(&version, query, sdbID)
	if err != nil {
		if err == sql.ErrNoRows {
			return "", fmt.Errorf("база данных не найдена")
		}
		return "", fmt.Errorf("failed to get database version: %w", err)
	}
	return version, nil
}

// GetDatabaseChanges получает изменения базы данных после указанной версии
func GetDatabaseChanges(sdbID int64, sinceVersion string) ([]models.SyncChange, error) {
	var changes []models.SyncChange
	query := `SELECT Id, DatabaseId, EntityType, EntityId, Operation, Data, UserId, CreatedAt, Version
	          FROM SyncChanges 
	          WHERE DatabaseId = ? AND Version > ?
	          ORDER BY CreatedAt ASC`

	err := MainDB.Select(&changes, query, sdbID, sinceVersion)
	if err != nil {
		return nil, fmt.Errorf("failed to get database changes: %w", err)
	}
	return changes, nil
}

// CreateSyncChange создает запись об изменении для синхронизации
func CreateSyncChange(change *models.SyncChange) error {
	query := `INSERT INTO SyncChanges 
	          (DatabaseId, EntityType, EntityId, Operation, Data, UserId, CreatedAt, Version)
	          VALUES (?, ?, ?, ?, ?, ?, ?, ?)`

	_, err := MainDB.Exec(query,
		change.DatabaseId, change.EntityType, change.EntityId,
		change.Operation, change.Data, change.UserId,
		change.CreatedAt, change.Version)

	if err != nil {
		return fmt.Errorf("failed to create sync change: %w", err)
	}
	return nil
}

// UpdateDatabaseVersion обновляет версию базы данных и время последней синхронизации
func UpdateDatabaseVersion(sdbID int64, version string) error {
	query := `UPDATE SharedDatabases SET Version = ?, LastSync = ? WHERE Id = ?`
	_, err := MainDB.Exec(query, version, time.Now(), sdbID)
	if err != nil {
		return fmt.Errorf("failed to update database version: %w", err)
	}
	return nil
}

// TODO: Добавить функции RemoveUserFromSharedDatabase, UpdateUserRoleInSharedDatabase, DeleteSharedDatabase
