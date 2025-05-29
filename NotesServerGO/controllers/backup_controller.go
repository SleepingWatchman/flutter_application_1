package controllers

import (
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strconv"

	"notes_server_go/middleware"
)

const personalBackupDir = "user_backups"
const personalBackupFileName = "personal.json"

// UploadPersonalBackupHandler обрабатывает загрузку файла личного бэкапа.
func UploadPersonalBackupHandler(w http.ResponseWriter, r *http.Request) {
	userID, ok := r.Context().Value(middleware.UserIDKey).(int64)
	if !ok {
		http.Error(w, "Unauthorized: User ID not found in token", http.StatusUnauthorized)
		return
	}

	// Создаем директорию для бэкапов пользователя, если она не существует
	userBackupPath := filepath.Join(personalBackupDir, strconv.FormatInt(userID, 10))
	if err := os.MkdirAll(userBackupPath, os.ModePerm); err != nil {
		log.Printf("Error creating backup directory '%s' for user %d: %v", userBackupPath, userID, err)
		http.Error(w, "Failed to prepare backup location", http.StatusInternalServerError)
		return
	}

	// Ограничим максимальный размер файла (например, 50MB)
	r.Body = http.MaxBytesReader(w, r.Body, 50*1024*1024)
	if err := r.ParseMultipartForm(50 << 20); err != nil { // 50MB
		log.Printf("Error parsing multipart form for user %d: %v", userID, err)
		http.Error(w, "Error processing backup file: "+err.Error(), http.StatusBadRequest)
		return
	}

	file, handler, err := r.FormFile("file") // "file" - это имя поля в форме от клиента
	if err != nil {
		log.Printf("Error retrieving 'file' from form for user %d: %v", userID, err)
		http.Error(w, "Backup file is required in 'file' field", http.StatusBadRequest)
		return
	}
	defer file.Close()

	log.Printf("Received personal backup file: %s, size: %d for user %d", handler.Filename, handler.Size, userID)

	targetFilePath := filepath.Join(userBackupPath, personalBackupFileName) // Сохраняем как JSON
	outFile, err := os.Create(targetFilePath)
	if err != nil {
		log.Printf("Error creating backup file '%s' for user %d: %v", targetFilePath, userID, err)
		http.Error(w, "Failed to create backup file", http.StatusInternalServerError)
		return
	}
	defer outFile.Close()

	_, err = io.Copy(outFile, file)
	if err != nil {
		log.Printf("Error writing backup data to file '%s' for user %d: %v", targetFilePath, userID, err)
		http.Error(w, "Failed to write backup data", http.StatusInternalServerError)
		// Попытка удалить частично записанный файл
		os.Remove(targetFilePath)
		return
	}

	log.Printf("Successfully uploaded personal backup for user %d to %s", userID, targetFilePath)
	w.WriteHeader(http.StatusOK)
	fmt.Fprintf(w, "Personal backup '%s' uploaded successfully.", handler.Filename)
}

// DownloadPersonalBackupHandler обрабатывает скачивание файла личного бэкапа.
func DownloadPersonalBackupHandler(w http.ResponseWriter, r *http.Request) {
	userID, ok := r.Context().Value(middleware.UserIDKey).(int64)
	if !ok {
		http.Error(w, "Unauthorized: User ID not found in token", http.StatusUnauthorized)
		return
	}

	userBackupPath := filepath.Join(personalBackupDir, strconv.FormatInt(userID, 10))
	backupFilePath := filepath.Join(userBackupPath, personalBackupFileName)

	if _, err := os.Stat(backupFilePath); os.IsNotExist(err) {
		log.Printf("Personal backup file '%s' not found for user %d", backupFilePath, userID)
		http.Error(w, "Personal backup not found", http.StatusNotFound)
		return
	}

	// Устанавливаем правильные заголовки для JSON
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Header().Set("Content-Disposition", "attachment; filename=\""+personalBackupFileName+"\"")

	http.ServeFile(w, r, backupFilePath)
	log.Printf("Successfully served personal backup '%s' to user %d", backupFilePath, userID)
}
