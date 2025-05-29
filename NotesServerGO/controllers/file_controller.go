package controllers

import (
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strings"

	"github.com/google/uuid"
)

const maxUploadSize = 5 * 1024 * 1024 // 5 MB
const profileImagesDir = "./uploads/profile_images/"

// UploadFileHandler обрабатывает загрузку файлов (например, фото профиля).
func UploadFileHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		respondError(w, http.StatusMethodNotAllowed, "Метод не разрешен. Используйте POST.")
		return
	}

	// Устанавливаем максимальный размер тела запроса
	r.Body = http.MaxBytesReader(w, r.Body, maxUploadSize)
	if err := r.ParseMultipartForm(maxUploadSize); err != nil {
		if err.Error() == "http: request body too large" {
			respondError(w, http.StatusRequestEntityTooLarge, fmt.Sprintf("Размер файла не должен превышать %dMB.", maxUploadSize/1024/1024))
		} else {
			respondError(w, http.StatusBadRequest, "Не удалось обработать multipart form: "+err.Error())
		}
		return
	}

	file, handler, err := r.FormFile("file") // "file" - это имя поля, которое ожидает клиент
	if err != nil {
		respondError(w, http.StatusBadRequest, "Не удалось получить файл из запроса: "+err.Error())
		return
	}
	defer file.Close()

	// Проверка расширения файла (пример)
	ext := strings.ToLower(filepath.Ext(handler.Filename))
	allowedExtensions := map[string]bool{".jpg": true, ".jpeg": true, ".png": true, ".gif": true}
	if !allowedExtensions[ext] {
		respondError(w, http.StatusBadRequest, "Недопустимый тип файла. Разрешены: jpg, jpeg, png, gif.")
		return
	}

	// Создаем директорию, если ее нет
	if err := os.MkdirAll(profileImagesDir, os.ModePerm); err != nil {
		log.Printf("Ошибка при создании директории %s: %v", profileImagesDir, err)
		respondError(w, http.StatusInternalServerError, "Не удалось создать директорию для загрузки.")
		return
	}

	// Генерируем уникальное имя файла
	uniqueFileName := uuid.New().String() + ext
	filePath := filepath.Join(profileImagesDir, uniqueFileName)

	dst, err := os.Create(filePath)
	if err != nil {
		log.Printf("Ошибка при создании файла %s: %v", filePath, err)
		respondError(w, http.StatusInternalServerError, "Не удалось создать файл на сервере.")
		return
	}
	defer dst.Close()

	if _, err := io.Copy(dst, file); err != nil {
		log.Printf("Ошибка при копировании файла %s: %v", filePath, err)
		respondError(w, http.StatusInternalServerError, "Не удалось сохранить файл на сервере.")
		return
	}

	// Формируем URL для доступа к файлу. Клиент ожидает полный URL или относительный путь,
	// который он сможет сконвертировать в полный.
	// Мы вернем относительный путь, который будет работать с FileServer.
	// Важно: в клиенте нужно будет корректно формировать полный URL до этого файла.
	// Сейчас FileService в клиенте ожидает полный URL, поэтому нужно его вернуть.
	// Предполагается, что сервер запущен на http://127.0.0.1:8080
	// и файлы будут доступны по /uploads/profile_images/filename
	// Мы должны вернуть URL, который клиент сможет использовать.
	// Сам FileServer будет настроен на /uploads/
	// Клиент FileService ожидает полный URL от этого эндпоинта.
	// Однако, FileService затем передает этот URL в authService.updateProfile,
	// который просто сохраняет его в UserModel. PhotoURL в UserModel должен быть полным.

	// Сделаем так, чтобы URL был относительным от корня сервера,
	// т.к. мы настроим FileServer на /uploads/
	fileAccessURL := "/uploads/profile_images/" + uniqueFileName

	log.Printf("Файл успешно загружен: %s, доступен по URL: %s", filePath, fileAccessURL)

	// Отправляем URL клиенту
	// Клиент FileService ожидает JSON с полем "url"
	response := map[string]string{"url": fileAccessURL}
	respondJSON(w, http.StatusOK, response)
}

// respondError и respondJSON должны быть доступны или скопированы сюда, если они в другом файле
// Для простоты, предположим, что они есть в том же пакете controllers (например, в auth_controller.go)
// Если нет, их нужно будет либо импортировать, либо определить здесь.
// func respondError(w http.ResponseWriter, code int, message string) { ... }
// func respondJSON(w http.ResponseWriter, code int, payload interface{}) { ... }

// Вспомогательные функции (если они не в общем файле)
// func respondJSON(w http.ResponseWriter, statusCode int, data interface{}) {
// 	w.Header().Set("Content-Type", "application/json")
// 	w.WriteHeader(statusCode)
// 	if data != nil {
// 		if err := json.NewEncoder(w).Encode(data); err != nil {
// 			log.Printf("Error encoding JSON response: %v", err)
// 			// Не отправляем http.Error здесь, так как заголовки уже могли быть отправлены
// 		}
// 	}
// }

// func respondError(w http.ResponseWriter, statusCode int, message string) {
// 	log.Printf("HTTP Error %d: %s", statusCode, message)
// 	response := map[string]string{"error": message}
// 	w.Header().Set("Content-Type", "application/json")
// 	w.WriteHeader(statusCode)
// 	if err := json.NewEncoder(w).Encode(response); err != nil {
// 		log.Printf("Error encoding error JSON response: %v", err)
// 	}
// }
