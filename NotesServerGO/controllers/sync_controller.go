package controllers

import (
	"database/sql"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io/ioutil"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"notes_server_go/data"
	"notes_server_go/middleware"
	"notes_server_go/models"

	"github.com/gorilla/mux"
)

// SyncDataRequest определяет структуру для данных синхронизации.
// Все поля ID в моделях должны быть int64 (или *int64 для необязательных ID при создании).
// Клиент должен присылать свои локальные ID. Если ID существует на сервере (для данного DatabaseId),
// запись обновляется. Если ID не существует или равен 0 (или null), запись создается.
// Сервер должен генерировать свои ID для новых записей и возвращать их клиенту (пока не реализовано в ответе).
type SyncDataRequest struct {
	Notes           []models.Note          `json:"notes"`
	Folders         []models.Folder        `json:"folders"`
	ScheduleEntries []models.ScheduleEntry `json:"schedule_entries"`
	PinboardNotes   []models.PinboardNote  `json:"pinboard_notes"`
	Connections     []models.Connection    `json:"connections"`
	NoteImages      []models.NoteImage     `json:"note_images"`
}

// SyncDataResponse определяет структуру ответа для синхронизации, аналогичную BackupData на клиенте.
type SyncDataResponse struct {
	Folders         []models.Folder        `json:"folders"`
	Notes           []models.Note          `json:"notes"`
	ScheduleEntries []models.ScheduleEntry `json:"schedule_entries"`
	PinboardNotes   []models.PinboardNote  `json:"pinboard_notes"`
	Connections     []models.Connection    `json:"connections"`
	Images          []models.NoteImage     `json:"images"` // Клиент ожидает "images"
	LastModified    string                 `json:"lastModified"`
	CreatedAt       string                 `json:"createdAt"`  // Обычно это дата создания самой SharedDatabase
	DatabaseId      string                 `json:"databaseId"` // ID совместной БД как строка
	UserId          string                 `json:"userId"`     // ID владельца БД как строка
}

// SyncSharedDatabaseHandler обрабатывает синхронизацию данных для указанной совместной БД.
// POST /api/sync/{database_id}
func SyncSharedDatabaseHandler(w http.ResponseWriter, r *http.Request) {
	currentUserID, ok := r.Context().Value(middleware.UserIDKey).(int64)
	if !ok {
		respondError(w, http.StatusUnauthorized, "Не удалось получить ID пользователя из токена.")
		return
	}

	vars := mux.Vars(r)
	dbIDStr := vars["database_id"]
	sharedDbID, err := strconv.ParseInt(dbIDStr, 10, 64)
	if err != nil {
		respondError(w, http.StatusBadRequest, "Неверный формат ID совместной базы данных.")
		return
	}

	// 1. Проверить доступ пользователя к sharedDbID
	role, err := data.GetUserRoleInSharedDatabase(sharedDbID, currentUserID)
	if err != nil {
		log.Printf("Ошибка при проверке роли пользователя %d в БД %d: %v", currentUserID, sharedDbID, err)
		respondError(w, http.StatusInternalServerError, "Ошибка сервера при проверке доступа к БД.")
		return
	}
	if role == nil {
		respondError(w, http.StatusForbidden, "Доступ к указанной совместной базе данных запрещен.")
		return
	}
	// Роли 'owner' и 'editor' могут синхронизировать. 'viewer' - нет.
	if *role == models.RoleViewer {
		respondError(w, http.StatusForbidden, "Пользователи с ролью 'viewer' не могут синхронизировать данные.")
		return
	}

	var syncData SyncDataRequest
	if err := json.NewDecoder(r.Body).Decode(&syncData); err != nil {
		respondError(w, http.StatusBadRequest, "Неверный формат данных для синхронизации: "+err.Error())
		return
	}
	defer r.Body.Close()

	// Начинаем транзакцию
	tx, err := data.MainDB.Beginx()
	if err != nil {
		log.Printf("SyncSharedDatabaseHandler: Ошибка начала транзакции для БД %d: %v", sharedDbID, err)
		respondError(w, http.StatusInternalServerError, "Ошибка сервера при начале синхронизации.")
		return
	}
	// Используем defer для отката в случае паники или ошибки до явного Commit
	defer func() {
		if r := recover(); r != nil {
			tx.Rollback()
			panic(r) // снова паникуем
		} else if err != nil { // err из области видимости SyncSharedDatabaseHandler
			tx.Rollback()
		}
	}()

	// Обработка ScheduleEntries
	processedScheduleEntryIDs := make(map[int64]bool) // Для отслеживания обработанных ID

	for _, clientEntry := range syncData.ScheduleEntries {
		clientEntry.DatabaseId = sharedDbID // Убеждаемся, что DatabaseId установлен корректно
		var serverEntryID int64

		if clientEntry.Id == 0 { // Явное указание на новую запись
			log.Printf("Sync: Создание новой ScheduleEntry для БД %d, клиентские данные: %+v", sharedDbID, clientEntry)
			createdID, createErr := data.CreateScheduleEntryWithTx(tx, &clientEntry) // Нужна версия с Tx
			if createErr != nil {
				err = fmt.Errorf("ошибка при создании ScheduleEntry: %w", createErr)
				log.Printf("Sync Error (DB %d, User %d): %v", sharedDbID, currentUserID, err)
				// respondError здесь вызовет tx.Rollback() через defer
				respondError(w, http.StatusInternalServerError, err.Error())
				return
			}
			serverEntryID = createdID
			log.Printf("Sync: Успешно создана ScheduleEntry с ID %d для БД %d", serverEntryID, sharedDbID)
		} else { // Попытка обновить существующую или создать, если ID клиента не найден на сервере
			log.Printf("Sync: Попытка обновления/создания ScheduleEntry с клиентским ID %d для БД %d", clientEntry.Id, sharedDbID)
			// Сначала пытаемся найти по ID, который прислал клиент (предполагая, что это серверный ID)
			existingEntry, getErr := data.GetScheduleEntryByIDWithTx(tx, clientEntry.Id, sharedDbID) // Нужна версия с Tx
			if getErr != nil && getErr != sql.ErrNoRows {
				err = fmt.Errorf("ошибка при поиске ScheduleEntry (ID %d, DB %d): %w", clientEntry.Id, sharedDbID, getErr)
				log.Printf("Sync Error (DB %d, User %d): %v", sharedDbID, currentUserID, err)
				respondError(w, http.StatusInternalServerError, err.Error())
				return
			}

			if existingEntry != nil { // Запись найдена, обновляем
				log.Printf("Sync: Обновление ScheduleEntry ID %d для БД %d", clientEntry.Id, sharedDbID)
				clientEntry.UpdatedAt = time.Now()                            // Обновляем время, т.к. Create/Update в data слое это делают
				updateErr := data.UpdateScheduleEntryWithTx(tx, &clientEntry) // Нужна версия с Tx
				if updateErr != nil {
					err = fmt.Errorf("ошибка при обновлении ScheduleEntry (ID %d, DB %d): %w", clientEntry.Id, sharedDbID, updateErr)
					log.Printf("Sync Error (DB %d, User %d): %v", sharedDbID, currentUserID, err)
					respondError(w, http.StatusInternalServerError, err.Error())
					return
				}
				serverEntryID = clientEntry.Id
				log.Printf("Sync: Успешно обновлена ScheduleEntry с ID %d для БД %d", serverEntryID, sharedDbID)
			} else { // Запись с таким ID не найдена (или getErr == sql.ErrNoRows), создаем новую
				// Важно: клиентский ID (clientEntry.Id) не используется как первичный ключ для новой записи на сервере.
				// Сервер генерирует свой собственный ID.
				log.Printf("Sync: ScheduleEntry с клиентским ID %d не найдена для БД %d. Создание новой.", clientEntry.Id, sharedDbID)
				newEntryToCreate := clientEntry                                               // Копируем, чтобы не менять Id в исходном объекте для логов
				newEntryToCreate.Id = 0                                                       // Сбрасываем ID, чтобы сервер сгенерировал новый
				createdID, createErr := data.CreateScheduleEntryWithTx(tx, &newEntryToCreate) // Нужна версия с Tx
				if createErr != nil {
					err = fmt.Errorf("ошибка при создании ScheduleEntry (клиентский ID %d, БД %d): %w", clientEntry.Id, sharedDbID, createErr)
					log.Printf("Sync Error (DB %d, User %d): %v", sharedDbID, currentUserID, err)
					respondError(w, http.StatusInternalServerError, err.Error())
					return
				}
				serverEntryID = createdID
				log.Printf("Sync: Успешно создана ScheduleEntry с серверным ID %d (клиентский ID %d) для БД %d", serverEntryID, clientEntry.Id, sharedDbID)
			}
		}
		processedScheduleEntryIDs[serverEntryID] = true
	}

	// Обработка Folders
	existingFolderIDs, err := data.GetAllFolderIDsForSharedDBWithTx(tx, sharedDbID)
	if err != nil {
		err = fmt.Errorf("ошибка при получении ID существующих Folders для БД %d: %w", sharedDbID, err)
		log.Printf("Sync Error (DB %d, User %d): %v", sharedDbID, currentUserID, err)
		respondError(w, http.StatusInternalServerError, err.Error())
		return
	}
	processedFolderIDs := make(map[int64]bool)
	for _, clientFolder := range syncData.Folders {
		clientFolder.DatabaseID = sharedDbID // Убеждаемся, что DatabaseID установлен корректно
		var serverFolderID int64

		if clientFolder.ID == 0 {
			log.Printf("Sync: Создание новой Folder для БД %d, клиентские данные: %+v", sharedDbID, clientFolder)
			createdID, createErr := data.CreateFolderWithTx(tx, &clientFolder)
			if createErr != nil {
				err = fmt.Errorf("ошибка при создании Folder: %w", createErr)
				log.Printf("Sync Error (DB %d, User %d): %v", sharedDbID, currentUserID, err)
				respondError(w, http.StatusInternalServerError, err.Error())
				return
			}
			serverFolderID = createdID
			log.Printf("Sync: Успешно создана Folder с ID %d для БД %d", serverFolderID, sharedDbID)
		} else {
			log.Printf("Sync: Попытка обновления/создания Folder с клиентским ID %d для БД %d", clientFolder.ID, sharedDbID)
			existingFolder, getErr := data.GetFolderByIDWithTx(tx, clientFolder.ID, sharedDbID)
			if getErr != nil && getErr != sql.ErrNoRows {
				err = fmt.Errorf("ошибка при поиске Folder (ID %d, DB %d): %w", clientFolder.ID, sharedDbID, getErr)
				log.Printf("Sync Error (DB %d, User %d): %v", sharedDbID, currentUserID, err)
				respondError(w, http.StatusInternalServerError, err.Error())
				return
			}

			if existingFolder != nil {
				log.Printf("Sync: Обновление Folder ID %d для БД %d", clientFolder.ID, sharedDbID)
				clientFolder.UpdatedAt = time.Now()
				updateErr := data.UpdateFolderWithTx(tx, &clientFolder)
				if updateErr != nil {
					err = fmt.Errorf("ошибка при обновлении Folder (ID %d, DB %d): %w", clientFolder.ID, sharedDbID, updateErr)
					log.Printf("Sync Error (DB %d, User %d): %v", sharedDbID, currentUserID, err)
					respondError(w, http.StatusInternalServerError, err.Error())
					return
				}
				serverFolderID = clientFolder.ID
				log.Printf("Sync: Успешно обновлена Folder с ID %d для БД %d", serverFolderID, sharedDbID)
			} else {
				log.Printf("Sync: Folder с клиентским ID %d не найдена для БД %d. Создание новой.", clientFolder.ID, sharedDbID)
				newFolderToCreate := clientFolder
				newFolderToCreate.ID = 0
				createdID, createErr := data.CreateFolderWithTx(tx, &newFolderToCreate)
				if createErr != nil {
					err = fmt.Errorf("ошибка при создании Folder (клиентский ID %d, БД %d): %w", clientFolder.ID, sharedDbID, createErr)
					log.Printf("Sync Error (DB %d, User %d): %v", sharedDbID, currentUserID, err)
					respondError(w, http.StatusInternalServerError, err.Error())
					return
				}
				serverFolderID = createdID
				log.Printf("Sync: Успешно создана Folder с серверным ID %d (клиентский ID %d) для БД %d", serverFolderID, clientFolder.ID, sharedDbID)
			}
		}
		processedFolderIDs[serverFolderID] = true
	}

	// Удаление Folders, которые есть на сервере, но не были обработаны (не пришли от клиента)
	for _, serverID := range existingFolderIDs {
		if _, ok := processedFolderIDs[serverID]; !ok {
			log.Printf("Sync: Удаление Folder с ID %d из БД %d, так как она не пришла от клиента.", serverID, sharedDbID)
			deleteErr := data.DeleteFolderWithTx(tx, serverID, sharedDbID)
			if deleteErr != nil && deleteErr != sql.ErrNoRows { // Игнорируем ошибку, если уже удалена
				err = fmt.Errorf("ошибка при удалении Folder (ID %d, DB %d): %w", serverID, sharedDbID, deleteErr)
				log.Printf("Sync Error (DB %d, User %d): %v", sharedDbID, currentUserID, err)
				respondError(w, http.StatusInternalServerError, err.Error())
				return
			}
			log.Printf("Sync: Успешно удалена Folder с ID %d из БД %d.", serverID, sharedDbID)
		}
	}
	// Конец обработки Folders

	// Обработка Notes
	existingNoteIDs, err := data.GetAllNoteIDsForSharedDBWithTx(tx, sharedDbID)
	if err != nil {
		err = fmt.Errorf("ошибка при получении ID существующих Notes для БД %d: %w", sharedDbID, err)
		log.Printf("Sync Error (DB %d, User %d): %v", sharedDbID, currentUserID, err)
		respondError(w, http.StatusInternalServerError, err.Error())
		return
	}
	processedNoteIDs := make(map[int64]bool)
	for _, clientNote := range syncData.Notes {
		clientNote.DatabaseID = sharedDbID // Убеждаемся, что DatabaseID установлен корректно
		// Обновляем JSON поля перед обработкой, если они есть в модели Note и используются
		if err := clientNote.UpdateJsonProperties(); err != nil {
			err = fmt.Errorf("ошибка при обновлении JSON свойств для Note (клиентский ID %d, БД %d): %w", clientNote.ID, sharedDbID, err)
			log.Printf("Sync Error (DB %d, User %d): %v", sharedDbID, currentUserID, err)
			respondError(w, http.StatusInternalServerError, err.Error())
			return
		}
		var serverNoteID int64

		if clientNote.ID == 0 {
			log.Printf("Sync: Создание новой Note для БД %d, клиентские данные (title): %s", sharedDbID, clientNote.Title)
			createdID, createErr := data.CreateNoteWithTx(tx, &clientNote)
			if createErr != nil {
				err = fmt.Errorf("ошибка при создании Note: %w", createErr)
				log.Printf("Sync Error (DB %d, User %d): %v", sharedDbID, currentUserID, err)
				respondError(w, http.StatusInternalServerError, err.Error())
				return
			}
			serverNoteID = createdID
			log.Printf("Sync: Успешно создана Note с ID %d для БД %d", serverNoteID, sharedDbID)
		} else {
			log.Printf("Sync: Попытка обновления/создания Note с клиентским ID %d для БД %d", clientNote.ID, sharedDbID)
			existingNote, getErr := data.GetNoteByIDWithTx(tx, clientNote.ID, sharedDbID)
			if getErr != nil && getErr != sql.ErrNoRows {
				err = fmt.Errorf("ошибка при поиске Note (ID %d, DB %d): %w", clientNote.ID, sharedDbID, getErr)
				log.Printf("Sync Error (DB %d, User %d): %v", sharedDbID, currentUserID, err)
				respondError(w, http.StatusInternalServerError, err.Error())
				return
			}

			if existingNote != nil {
				log.Printf("Sync: Обновление Note ID %d для БД %d", clientNote.ID, sharedDbID)
				clientNote.UpdatedAt = time.Now()
				updateErr := data.UpdateNoteWithTx(tx, &clientNote)
				if updateErr != nil {
					err = fmt.Errorf("ошибка при обновлении Note (ID %d, DB %d): %w", clientNote.ID, sharedDbID, updateErr)
					log.Printf("Sync Error (DB %d, User %d): %v", sharedDbID, currentUserID, err)
					respondError(w, http.StatusInternalServerError, err.Error())
					return
				}
				serverNoteID = clientNote.ID
				log.Printf("Sync: Успешно обновлена Note с ID %d для БД %d", serverNoteID, sharedDbID)
			} else {
				log.Printf("Sync: Note с клиентским ID %d не найдена для БД %d. Создание новой.", clientNote.ID, sharedDbID)
				newNoteToCreate := clientNote
				newNoteToCreate.ID = 0
				createdID, createErr := data.CreateNoteWithTx(tx, &newNoteToCreate)
				if createErr != nil {
					err = fmt.Errorf("ошибка при создании Note (клиентский ID %d, БД %d): %w", clientNote.ID, sharedDbID, createErr)
					log.Printf("Sync Error (DB %d, User %d): %v", sharedDbID, currentUserID, err)
					respondError(w, http.StatusInternalServerError, err.Error())
					return
				}
				serverNoteID = createdID
				log.Printf("Sync: Успешно создана Note с серверным ID %d (клиентский ID %d) для БД %d", serverNoteID, clientNote.ID, sharedDbID)
			}
		}
		processedNoteIDs[serverNoteID] = true
	}

	// Удаление Notes, которые есть на сервере, но не были обработаны
	for _, serverID := range existingNoteIDs {
		if _, ok := processedNoteIDs[serverID]; !ok {
			log.Printf("Sync: Удаление Note с ID %d из БД %d, так как она не пришла от клиента.", serverID, sharedDbID)
			deleteErr := data.DeleteNoteWithTx(tx, serverID, sharedDbID)
			if deleteErr != nil && deleteErr != sql.ErrNoRows {
				err = fmt.Errorf("ошибка при удалении Note (ID %d, DB %d): %w", serverID, sharedDbID, deleteErr)
				log.Printf("Sync Error (DB %d, User %d): %v", sharedDbID, currentUserID, err)
				respondError(w, http.StatusInternalServerError, err.Error())
				return
			}
			log.Printf("Sync: Успешно удалена Note с ID %d из БД %d.", serverID, sharedDbID)
		}
	}
	// Конец обработки Notes

	// Обработка PinboardNotes
	existingPinboardNoteIDs, err := data.GetAllPinboardNoteIDsForSharedDBWithTx(tx, sharedDbID)
	if err != nil {
		err = fmt.Errorf("ошибка при получении ID существующих PinboardNotes для БД %d: %w", sharedDbID, err)
		log.Printf("Sync Error (DB %d, User %d): %v", sharedDbID, currentUserID, err)
		respondError(w, http.StatusInternalServerError, err.Error())
		return
	}
	processedPinboardNoteIDs := make(map[int64]bool)
	for _, clientPinboardNote := range syncData.PinboardNotes {
		clientPinboardNote.DatabaseId = sharedDbID
		var serverPinboardNoteID int64

		if clientPinboardNote.Id == 0 {
			log.Printf("Sync: Создание новой PinboardNote для БД %d, клиентские данные (title): %s", sharedDbID, clientPinboardNote.Title)
			createdID, createErr := data.CreatePinboardNoteWithTx(tx, &clientPinboardNote)
			if createErr != nil {
				err = fmt.Errorf("ошибка при создании PinboardNote: %w", createErr)
				log.Printf("Sync Error (DB %d, User %d): %v", sharedDbID, currentUserID, err)
				respondError(w, http.StatusInternalServerError, err.Error())
				return
			}
			serverPinboardNoteID = createdID
			log.Printf("Sync: Успешно создана PinboardNote с ID %d для БД %d", serverPinboardNoteID, sharedDbID)
		} else {
			log.Printf("Sync: Попытка обновления/создания PinboardNote с клиентским ID %d для БД %d", clientPinboardNote.Id, sharedDbID)
			existingPinboardNote, getErr := data.GetPinboardNoteByIDWithTx(tx, clientPinboardNote.Id, sharedDbID)
			if getErr != nil && getErr != sql.ErrNoRows {
				err = fmt.Errorf("ошибка при поиске PinboardNote (ID %d, DB %d): %w", clientPinboardNote.Id, sharedDbID, getErr)
				log.Printf("Sync Error (DB %d, User %d): %v", sharedDbID, currentUserID, err)
				respondError(w, http.StatusInternalServerError, err.Error())
				return
			}

			if existingPinboardNote != nil {
				log.Printf("Sync: Обновление PinboardNote ID %d для БД %d", clientPinboardNote.Id, sharedDbID)
				clientPinboardNote.UpdatedAt = time.Now()
				updateErr := data.UpdatePinboardNoteWithTx(tx, &clientPinboardNote)
				if updateErr != nil {
					err = fmt.Errorf("ошибка при обновлении PinboardNote (ID %d, DB %d): %w", clientPinboardNote.Id, sharedDbID, updateErr)
					log.Printf("Sync Error (DB %d, User %d): %v", sharedDbID, currentUserID, err)
					respondError(w, http.StatusInternalServerError, err.Error())
					return
				}
				serverPinboardNoteID = clientPinboardNote.Id
				log.Printf("Sync: Успешно обновлена PinboardNote с ID %d для БД %d", serverPinboardNoteID, sharedDbID)
			} else {
				log.Printf("Sync: PinboardNote с клиентским ID %d не найдена для БД %d. Создание новой.", clientPinboardNote.Id, sharedDbID)
				newPinboardNoteToCreate := clientPinboardNote
				newPinboardNoteToCreate.Id = 0
				createdID, createErr := data.CreatePinboardNoteWithTx(tx, &newPinboardNoteToCreate)
				if createErr != nil {
					err = fmt.Errorf("ошибка при создании PinboardNote (клиентский ID %d, БД %d): %w", clientPinboardNote.Id, sharedDbID, createErr)
					log.Printf("Sync Error (DB %d, User %d): %v", sharedDbID, currentUserID, err)
					respondError(w, http.StatusInternalServerError, err.Error())
					return
				}
				serverPinboardNoteID = createdID
				log.Printf("Sync: Успешно создана PinboardNote с серверным ID %d (клиентский ID %d) для БД %d", serverPinboardNoteID, clientPinboardNote.Id, sharedDbID)
			}
		}
		processedPinboardNoteIDs[serverPinboardNoteID] = true
	}

	// Удаление PinboardNotes, которые есть на сервере, но не были обработаны
	for _, serverID := range existingPinboardNoteIDs {
		if _, ok := processedPinboardNoteIDs[serverID]; !ok {
			log.Printf("Sync: Удаление PinboardNote с ID %d из БД %d, так как она не пришла от клиента.", serverID, sharedDbID)
			deleteErr := data.DeletePinboardNoteWithTx(tx, serverID, sharedDbID)
			if deleteErr != nil && deleteErr != sql.ErrNoRows {
				err = fmt.Errorf("ошибка при удалении PinboardNote (ID %d, DB %d): %w", serverID, sharedDbID, deleteErr)
				log.Printf("Sync Error (DB %d, User %d): %v", sharedDbID, currentUserID, err)
				respondError(w, http.StatusInternalServerError, err.Error())
				return
			}
			log.Printf("Sync: Успешно удалена PinboardNote с ID %d из БД %d.", serverID, sharedDbID)
		}
	}
	// Конец обработки PinboardNotes

	// Обработка Connections
	existingConnectionIDs, err := data.GetAllConnectionIDsForSharedDBWithTx(tx, sharedDbID)
	if err != nil {
		err = fmt.Errorf("ошибка при получении ID существующих Connections для БД %d: %w", sharedDbID, err)
		log.Printf("Sync Error (DB %d, User %d): %v", sharedDbID, currentUserID, err)
		respondError(w, http.StatusInternalServerError, err.Error())
		return
	}
	processedConnectionIDs := make(map[int64]bool)
	for _, clientConnection := range syncData.Connections {
		clientConnection.DatabaseId = sharedDbID
		var serverConnectionID int64

		if clientConnection.Id == 0 {
			log.Printf("Sync: Создание новой Connection для БД %d, клиентские данные: %+v", sharedDbID, clientConnection)
			createdID, createErr := data.CreateConnectionWithTx(tx, &clientConnection)
			if createErr != nil {
				err = fmt.Errorf("ошибка при создании Connection: %w", createErr)
				log.Printf("Sync Error (DB %d, User %d): %v", sharedDbID, currentUserID, err)
				respondError(w, http.StatusInternalServerError, err.Error())
				return
			}
			serverConnectionID = createdID
			log.Printf("Sync: Успешно создана Connection с ID %d для БД %d", serverConnectionID, sharedDbID)
		} else {
			log.Printf("Sync: Попытка обновления/создания Connection с клиентским ID %d для БД %d", clientConnection.Id, sharedDbID)
			existingConnection, getErr := data.GetConnectionByIDWithTx(tx, clientConnection.Id, sharedDbID)
			if getErr != nil && getErr != sql.ErrNoRows {
				err = fmt.Errorf("ошибка при поиске Connection (ID %d, DB %d): %w", clientConnection.Id, sharedDbID, getErr)
				log.Printf("Sync Error (DB %d, User %d): %v", sharedDbID, currentUserID, err)
				respondError(w, http.StatusInternalServerError, err.Error())
				return
			}

			if existingConnection != nil {
				log.Printf("Sync: Обновление Connection ID %d для БД %d", clientConnection.Id, sharedDbID)
				clientConnection.UpdatedAt = time.Now()
				updateErr := data.UpdateConnectionWithTx(tx, &clientConnection)
				if updateErr != nil {
					err = fmt.Errorf("ошибка при обновлении Connection (ID %d, DB %d): %w", clientConnection.Id, sharedDbID, updateErr)
					log.Printf("Sync Error (DB %d, User %d): %v", sharedDbID, currentUserID, err)
					respondError(w, http.StatusInternalServerError, err.Error())
					return
				}
				serverConnectionID = clientConnection.Id
				log.Printf("Sync: Успешно обновлена Connection с ID %d для БД %d", serverConnectionID, sharedDbID)
			} else {
				log.Printf("Sync: Connection с клиентским ID %d не найдена для БД %d. Создание новой.", clientConnection.Id, sharedDbID)
				newConnectionToCreate := clientConnection
				newConnectionToCreate.Id = 0
				createdID, createErr := data.CreateConnectionWithTx(tx, &newConnectionToCreate)
				if createErr != nil {
					err = fmt.Errorf("ошибка при создании Connection (клиентский ID %d, БД %d): %w", clientConnection.Id, sharedDbID, createErr)
					log.Printf("Sync Error (DB %d, User %d): %v", sharedDbID, currentUserID, err)
					respondError(w, http.StatusInternalServerError, err.Error())
					return
				}
				serverConnectionID = createdID
				log.Printf("Sync: Успешно создана Connection с серверным ID %d (клиентский ID %d) для БД %d", serverConnectionID, clientConnection.Id, sharedDbID)
			}
		}
		processedConnectionIDs[serverConnectionID] = true
	}

	// Удаление Connections, которые есть на сервере, но не были обработаны
	for _, serverID := range existingConnectionIDs {
		if _, ok := processedConnectionIDs[serverID]; !ok {
			log.Printf("Sync: Удаление Connection с ID %d из БД %d, так как она не пришла от клиента.", serverID, sharedDbID)
			deleteErr := data.DeleteConnectionWithTx(tx, serverID, sharedDbID)
			if deleteErr != nil && deleteErr != sql.ErrNoRows {
				err = fmt.Errorf("ошибка при удалении Connection (ID %d, DB %d): %w", serverID, sharedDbID, deleteErr)
				log.Printf("Sync Error (DB %d, User %d): %v", sharedDbID, currentUserID, err)
				respondError(w, http.StatusInternalServerError, err.Error())
				return
			}
			log.Printf("Sync: Успешно удалена Connection с ID %d из БД %d.", serverID, sharedDbID)
		}
	}
	// Конец обработки Connections

	// Обработка NoteImages
	// Определяем базовую директорию для изображений этой БД
	baseImageDir := filepath.Join("uploads", "shared_db_"+strconv.FormatInt(sharedDbID, 10), "images")
	if err := os.MkdirAll(baseImageDir, os.ModePerm); err != nil {
		err = fmt.Errorf("ошибка при создании директории для изображений БД %d: %w", sharedDbID, err)
		log.Printf("Sync Error (DB %d, User %d): %v", sharedDbID, currentUserID, err)
		respondError(w, http.StatusInternalServerError, err.Error())
		return
	}

	existingNoteImageIDs, err := data.GetAllNoteImageIDsForSharedDBWithTx(tx, sharedDbID)
	if err != nil {
		err = fmt.Errorf("ошибка при получении ID существующих NoteImages для БД %d: %w", sharedDbID, err)
		log.Printf("Sync Error (DB %d, User %d): %v", sharedDbID, currentUserID, err)
		respondError(w, http.StatusInternalServerError, err.Error())
		return
	}
	processedNoteImageIDs := make(map[int64]bool)
	var imagePathsToDeleteAfterCommit []string

	for _, clientImage := range syncData.NoteImages {
		clientImage.DatabaseId = sharedDbID
		var serverImageID int64
		var serverImagePath string // Путь к файлу на сервере

		// Логика сохранения файла, если есть ImageData
		if clientImage.ImageData != "" {
			imageDataBytes, decodeErr := base64.StdEncoding.DecodeString(clientImage.ImageData)
			if decodeErr != nil {
				err = fmt.Errorf("ошибка декодирования ImageData для NoteImage (клиент FileName %s, БД %d): %w", clientImage.FileName, sharedDbID, decodeErr)
				log.Printf("Sync Error (DB %d, User %d): %v", sharedDbID, currentUserID, err)
				respondError(w, http.StatusBadRequest, "Ошибка декодирования данных изображения.")
				return
			}
			// Генерируем уникальное имя файла или используем клиентское с проверкой
			// Для простоты пока используем clientImage.FileName, но добавляем временную метку для уникальности, если Id = 0
			fileNameOnServer := clientImage.FileName
			if clientImage.Id == 0 { // Новое изображение
				fileNameOnServer = fmt.Sprintf("%d_%s", time.Now().UnixNano(), clientImage.FileName)
			}

			// Очистка имени файла от недопустимых символов (очень базовая)
			fileNameOnServer = strings.ReplaceAll(fileNameOnServer, "..", "")
			fileNameOnServer = strings.ReplaceAll(fileNameOnServer, "/", "_")
			fileNameOnServer = strings.ReplaceAll(fileNameOnServer, "\\\\", "_")

			serverImagePath = filepath.Join(baseImageDir, fileNameOnServer)

			// Перед записью нового файла, если это обновление существующего изображения,
			// и имя файла изменилось, или это новое изображение с ID клиента,
			// нужно удалить старый файл, если он был.
			if clientImage.Id != 0 {
				existingImg, getImgErr := data.GetNoteImageByIDWithTx(tx, clientImage.Id, sharedDbID)
				if getImgErr != nil && getImgErr != sql.ErrNoRows {
					err = fmt.Errorf("ошибка получения существующего NoteImage (ID %d) перед обновлением файла: %w", clientImage.Id, getImgErr)
					log.Printf("Sync Error (DB %d, User %d): %v", sharedDbID, currentUserID, err)
					respondError(w, http.StatusInternalServerError, err.Error())
					return
				}
				if existingImg != nil && existingImg.ImagePath != "" && existingImg.ImagePath != serverImagePath { // Если путь изменился
					// Добавляем старый путь в список на удаление после коммита
					// Полный путь к старому файлу
					oldFullPath := existingImg.ImagePath // Предполагаем, что ImagePath уже содержит полный путь или путь относительно корня приложения
					if !filepath.IsAbs(oldFullPath) {    // Если путь относительный, делаем его абсолютным от корня
						wd, _ := os.Getwd() // Получаем текущую рабочую директорию (корень сервера)
						oldFullPath = filepath.Join(wd, oldFullPath)
					}
					// Проверка, что мы не пытаемся удалить что-то за пределами uploads
					if strings.HasPrefix(oldFullPath, filepath.Join(baseImageDir, "..")) { // Простая проверка на выход из baseImageDir
						imagePathsToDeleteAfterCommit = append(imagePathsToDeleteAfterCommit, oldFullPath)
					} else {
						log.Printf("Предупреждение: Попытка запланировать удаление файла за пределами разрешенной директории: %s", oldFullPath)
					}
				}
			}

			writeErr := ioutil.WriteFile(serverImagePath, imageDataBytes, 0644)
			if writeErr != nil {
				err = fmt.Errorf("ошибка сохранения файла изображения %s для БД %d: %w", serverImagePath, sharedDbID, writeErr)
				log.Printf("Sync Error (DB %d, User %d): %v", sharedDbID, currentUserID, err)
				respondError(w, http.StatusInternalServerError, "Ошибка сохранения файла изображения.")
				return
			}
			clientImage.ImagePath = filepath.ToSlash(serverImagePath) // Сохраняем путь в формате Unix
			log.Printf("Sync: Файл изображения сохранен: %s", clientImage.ImagePath)
		}

		if clientImage.Id == 0 {
			log.Printf("Sync: Создание новой NoteImage для БД %d, FileName: %s", sharedDbID, clientImage.FileName)
			createdID, createErr := data.CreateNoteImageWithTx(tx, &clientImage)
			if createErr != nil {
				err = fmt.Errorf("ошибка при создании NoteImage: %w", createErr)
				log.Printf("Sync Error (DB %d, User %d): %v", sharedDbID, currentUserID, err)
				respondError(w, http.StatusInternalServerError, err.Error())
				return
			}
			serverImageID = createdID
			log.Printf("Sync: Успешно создана NoteImage с ID %d для БД %d", serverImageID, sharedDbID)
		} else {
			log.Printf("Sync: Попытка обновления/создания NoteImage с клиентским ID %d для БД %d", clientImage.Id, sharedDbID)
			existingImage, getErr := data.GetNoteImageByIDWithTx(tx, clientImage.Id, sharedDbID)
			if getErr != nil && getErr != sql.ErrNoRows {
				err = fmt.Errorf("ошибка при поиске NoteImage (ID %d, DB %d): %w", clientImage.Id, sharedDbID, getErr)
				log.Printf("Sync Error (DB %d, User %d): %v", sharedDbID, currentUserID, err)
				respondError(w, http.StatusInternalServerError, err.Error())
				return
			}

			if existingImage != nil {
				log.Printf("Sync: Обновление NoteImage ID %d для БД %d", clientImage.Id, sharedDbID)
				// Если ImageData не пришел, но ImagePath есть у клиента, используем его.
				// Иначе, ImagePath уже установлен выше из сохраненного файла.
				if clientImage.ImageData == "" && clientImage.ImagePath != "" {
					// Это условие может быть опасным, если клиент присылает произвольный ImagePath
					// Для безопасности, если ImageData нет, ImagePath не должен меняться или должен быть очищен,
					// если только это не специальный случай (например, перемещение файла на клиенте).
					// Пока что, если ImageData нет, мы НЕ будем обновлять ImagePath из clientImage,
					// он обновится только если был новый ImageData.
					// Если ImagePath изменился на клиенте БЕЗ ImageData, это не будет отражено.
					// Чтобы это поддержать, нужна более сложная логика.
					// Оставляем старый ImagePath, если не было новой загрузки.
					clientImage.ImagePath = existingImage.ImagePath
				} else if clientImage.ImagePath == "" && clientImage.ImageData != "" {
					// ImagePath уже установлен из нового файла
				} else if clientImage.ImagePath == "" && clientImage.ImageData == "" {
					clientImage.ImagePath = existingImage.ImagePath // не было данных, не было пути, оставляем как есть
				}

				clientImage.UpdatedAt = time.Now()
				updateErr := data.UpdateNoteImageWithTx(tx, &clientImage)
				if updateErr != nil {
					err = fmt.Errorf("ошибка при обновлении NoteImage (ID %d, DB %d): %w", clientImage.Id, sharedDbID, updateErr)
					log.Printf("Sync Error (DB %d, User %d): %v", sharedDbID, currentUserID, err)
					respondError(w, http.StatusInternalServerError, err.Error())
					return
				}
				serverImageID = clientImage.Id
				log.Printf("Sync: Успешно обновлена NoteImage с ID %d для БД %d", serverImageID, sharedDbID)
			} else {
				log.Printf("Sync: NoteImage с клиентским ID %d не найдена для БД %d. Создание новой.", clientImage.Id, sharedDbID)
				if clientImage.ImagePath == "" { // Если это новая запись и файл не был загружен (что странно, но возможно)
					err = fmt.Errorf("попытка создать новую NoteImage без ImageData или ImagePath (клиентский ID %d)", clientImage.Id)
					log.Printf("Sync Error (DB %d, User %d): %v", sharedDbID, currentUserID, err)
					respondError(w, http.StatusBadRequest, err.Error())
					return
				}
				newImageToCreate := clientImage
				newImageToCreate.Id = 0
				createdID, createErr := data.CreateNoteImageWithTx(tx, &newImageToCreate)
				if createErr != nil {
					err = fmt.Errorf("ошибка при создании NoteImage (клиентский ID %d, БД %d): %w", clientImage.Id, sharedDbID, createErr)
					log.Printf("Sync Error (DB %d, User %d): %v", sharedDbID, currentUserID, err)
					respondError(w, http.StatusInternalServerError, err.Error())
					return
				}
				serverImageID = createdID
				log.Printf("Sync: Успешно создана NoteImage с серверным ID %d (клиентский ID %d) для БД %d", serverImageID, clientImage.Id, sharedDbID)
			}
		}
		processedNoteImageIDs[serverImageID] = true
	}

	// Удаление NoteImages, которые есть на сервере, но не были обработаны
	var serverImagePathsToDelete []string
	imageIDsToDeleteFromDB := []int64{}
	for _, serverID := range existingNoteImageIDs {
		if _, ok := processedNoteImageIDs[serverID]; !ok {
			imageIDsToDeleteFromDB = append(imageIDsToDeleteFromDB, serverID)
		}
	}

	if len(imageIDsToDeleteFromDB) > 0 {
		paths, pathErr := data.GetImagePathsForDeletionWithTx(tx, imageIDsToDeleteFromDB, sharedDbID)
		if pathErr != nil {
			err = fmt.Errorf("ошибка при получении ImagePath для удаляемых NoteImages (БД %d): %w", sharedDbID, pathErr)
			log.Printf("Sync Error (DB %d, User %d): %v", sharedDbID, currentUserID, err)
			respondError(w, http.StatusInternalServerError, err.Error())
			return
		}
		serverImagePathsToDelete = append(serverImagePathsToDelete, paths...)

		for _, serverID := range imageIDsToDeleteFromDB {
			log.Printf("Sync: Удаление NoteImage с ID %d из БД %d, так как она не пришла от клиента.", serverID, sharedDbID)
			deleteErr := data.DeleteNoteImageWithTx(tx, serverID, sharedDbID)
			if deleteErr != nil && deleteErr != sql.ErrNoRows {
				err = fmt.Errorf("ошибка при удалении NoteImage (ID %d, DB %d): %w", serverID, sharedDbID, deleteErr)
				log.Printf("Sync Error (DB %d, User %d): %v", sharedDbID, currentUserID, err)
				respondError(w, http.StatusInternalServerError, err.Error())
				return
			}
			log.Printf("Sync: Успешно удалена запись NoteImage с ID %d из БД %d.", serverID, sharedDbID)
		}
	}
	imagePathsToDeleteAfterCommit = append(imagePathsToDeleteAfterCommit, serverImagePathsToDelete...)
	// Конец обработки NoteImages

	// Получаем все актуальные ScheduleEntries для ответа
	actualScheduleEntries, getErr := data.GetScheduleEntriesByDBIDWithTx(tx, sharedDbID) // Нужна версия с Tx
	if getErr != nil {
		err = fmt.Errorf("ошибка при получении актуальных ScheduleEntries для БД %d: %w", sharedDbID, getErr)
		log.Printf("Sync Error (DB %d, User %d): %v", sharedDbID, currentUserID, err)
		respondError(w, http.StatusInternalServerError, err.Error())
		return
	}

	// Завершаем транзакцию
	if err = tx.Commit(); err != nil {
		log.Printf("SyncSharedDatabaseHandler: Ошибка Commit транзакции для БД %d: %v", sharedDbID, err)
		// err уже будет установлен, defer вызовет Rollback
		respondError(w, http.StatusInternalServerError, "Ошибка сервера при завершении синхронизации.")
		return
	}

	log.Printf("Синхронизация для БД %d успешно завершена. ScheduleEntries: %d, Folders: %d, Notes: %d, PinboardNotes: %d, Connections: %d, NoteImages: %d",
		sharedDbID, len(actualScheduleEntries), len(processedFolderIDs), len(processedNoteIDs), len(processedPinboardNoteIDs), len(processedConnectionIDs), len(processedNoteImageIDs))

	// Формируем ответ
	// Пока в ответе только ScheduleEntries. Позже добавим остальные сущности.
	// Также нужно получить данные для LastModified, CreatedAt (для SharedDatabase), DatabaseId (как string), UserId (owner)

	actualFolders, err := data.GetAllFoldersBySharedDBIDWithTx(tx, sharedDbID)
	if err != nil {
		// Эта ошибка возникает после основного цикла синхронизации и потенциального коммита,
		// поэтому не откатываем транзакцию, а просто логируем и возвращаем ошибку клиенту.
		log.Printf("Sync Error (DB %d, User %d): ошибка при получении актуальных Folders для ответа: %v", sharedDbID, currentUserID, err)
		// Если tx.Commit() еще не был вызван из-за предыдущей ошибки, defer tx.Rollback() сработает.
		// Если tx.Commit() был успешен, эта ошибка только повлияет на ответ клиенту.
		respondError(w, http.StatusInternalServerError, "Ошибка сервера при подготовке ответа синхронизации (folders).")
		return
	}
	log.Printf("Sync: Получено %d актуальных папок для ответа БД %d", len(actualFolders), sharedDbID)

	actualNotes, err := data.GetAllNotesBySharedDBIDWithTx(tx, sharedDbID)
	if err != nil {
		log.Printf("Sync Error (DB %d, User %d): ошибка при получении актуальных Notes для ответа: %v", sharedDbID, currentUserID, err)
		respondError(w, http.StatusInternalServerError, "Ошибка сервера при подготовке ответа синхронизации (notes).")
		return
	}
	log.Printf("Sync: Получено %d актуальных заметок для ответа БД %d", len(actualNotes), sharedDbID)

	actualPinboardNotes, err := data.GetAllPinboardNotesBySharedDBIDWithTx(tx, sharedDbID)
	if err != nil {
		log.Printf("Sync Error (DB %d, User %d): ошибка при получении актуальных PinboardNotes для ответа: %v", sharedDbID, currentUserID, err)
		respondError(w, http.StatusInternalServerError, "Ошибка сервера при подготовке ответа синхронизации (pinboard_notes).")
		return
	}
	log.Printf("Sync: Получено %d актуальных заметок с доски для ответа БД %d", len(actualPinboardNotes), sharedDbID)

	actualConnections, err := data.GetAllConnectionsBySharedDBIDWithTx(tx, sharedDbID)
	if err != nil {
		log.Printf("Sync Error (DB %d, User %d): ошибка при получении актуальных Connections для ответа: %v", sharedDbID, currentUserID, err)
		respondError(w, http.StatusInternalServerError, "Ошибка сервера при подготовке ответа синхронизации (connections).")
		return
	}
	log.Printf("Sync: Получено %d актуальных соединений для ответа БД %d", len(actualConnections), sharedDbID)

	actualNoteImages, err := data.GetAllNoteImagesBySharedDBIDWithTx(tx, sharedDbID)
	if err != nil {
		log.Printf("Sync Error (DB %d, User %d): ошибка при получении актуальных NoteImages для ответа: %v", sharedDbID, currentUserID, err)
		respondError(w, http.StatusInternalServerError, "Ошибка сервера при подготовке ответа синхронизации (note_images).")
		return
	}
	log.Printf("Sync: Получено %d актуальных изображений для ответа БД %d", len(actualNoteImages), sharedDbID)

	sharedDBInfo, err := data.GetSharedDatabaseDetails(sharedDbID) // Эта функция уже есть
	if err != nil || sharedDBInfo == nil {
		log.Printf("Sync Error: Не удалось получить детали SharedDatabase %d для ответа: %v", sharedDbID, err)
		// Если не можем получить детали, это критично для формирования корректного ответа BackupData
		// err уже будет установлен из GetSharedDatabaseDetails или tx.Commit, defer отработает
		// Если tx.Commit() был успешен, но здесь ошибка, то err не установлен, нужно установить
		if err == nil { // Устанавливаем err, чтобы defer сделал Rollback, если tx еще не закоммичен
			err = fmt.Errorf("не удалось получить детали SharedDatabase %d", sharedDbID)
			// tx.Rollback() будет вызван defer-ом, если err != nil.
			// Если Commit уже прошел, эта ошибка только повлияет на ответ клиенту.
		}
		respondError(w, http.StatusInternalServerError, "Ошибка сервера при подготовке ответа синхронизации.")
		return
	}

	// Загружаем ImageData для ответа
	for i := range actualNoteImages {
		if actualNoteImages[i].ImagePath != "" {
			fullServerPath := actualNoteImages[i].ImagePath
			// Если ImagePath хранится как относительный от корня проекта
			if !filepath.IsAbs(fullServerPath) {
				wd, _ := os.Getwd()
				fullServerPath = filepath.Join(wd, fullServerPath)
			}

			if _, statErr := os.Stat(fullServerPath); statErr == nil {
				imgBytes, readErr := ioutil.ReadFile(fullServerPath)
				if readErr != nil {
					log.Printf("Sync Warning: Не удалось прочитать файл изображения %s для ответа: %v", fullServerPath, readErr)
					actualNoteImages[i].ImageData = "" // Очищаем, если не удалось прочитать
				} else {
					actualNoteImages[i].ImageData = base64.StdEncoding.EncodeToString(imgBytes)
				}
			} else {
				log.Printf("Sync Warning: Файл изображения %s не найден на сервере для ответа.", fullServerPath)
				actualNoteImages[i].ImageData = ""
			}
		}
	}

	response := SyncDataResponse{
		ScheduleEntries: actualScheduleEntries,
		Folders:         actualFolders,
		Notes:           actualNotes,
		PinboardNotes:   actualPinboardNotes,
		Connections:     actualConnections,
		Images:          actualNoteImages, // Клиент ожидает "images"
		LastModified:    sharedDBInfo.UpdatedAt.Format(time.RFC3339Nano),
		CreatedAt:       sharedDBInfo.CreatedAt.Format(time.RFC3339Nano),
		DatabaseId:      strconv.FormatInt(sharedDBInfo.Id, 10),
		UserId:          strconv.FormatInt(sharedDBInfo.OwnerUserId, 10),
	}

	// Если err == nil (транзакция может быть закоммичена), удаляем файлы
	if err == nil && len(imagePathsToDeleteAfterCommit) > 0 {
		log.Printf("Sync: Удаление %d файлов изображений после коммита транзакции...", len(imagePathsToDeleteAfterCommit))
		for _, pathToDelete := range imagePathsToDeleteAfterCommit {
			// Еще раз проверяем, что путь безопасен (хотя уже должны были проверить)
			// Это базовая проверка, можно улучшить
			resolvedPath, resolveErr := filepath.Abs(pathToDelete)
			if resolveErr != nil {
				log.Printf("Sync Error: не удалось разрешить путь к файлу для удаления: %s, ошибка: %v", pathToDelete, resolveErr)
				continue
			}

			uploadsDir, _ := filepath.Abs("uploads") // Абсолютный путь к папке uploads
			if !strings.HasPrefix(resolvedPath, uploadsDir) {
				log.Printf("Sync Error: Попытка удаления файла вне директории 'uploads': %s (разрешенный: %s)", pathToDelete, resolvedPath)
				continue
			}

			deleteFileErr := os.Remove(pathToDelete)
			if deleteFileErr != nil {
				// Логируем ошибку, но не прерываем процесс, так как данные в БД уже консистентны
				log.Printf("Sync Warning: Ошибка при удалении файла изображения %s: %v", pathToDelete, deleteFileErr)
			} else {
				log.Printf("Sync: Успешно удален файл изображения: %s", pathToDelete)
			}
		}
	}

	respondJSON(w, http.StatusOK, response)
}
