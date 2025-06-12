package data

import (
	"fmt"
	"log"
	"os"
	"path/filepath"

	"github.com/jmoiron/sqlx"
	_ "github.com/mattn/go-sqlite3" // Драйвер SQLite, импортируется для побочных эффектов (регистрации драйвера)
)

var MainDB *sqlx.DB // Глобальная переменная для основного пула подключений к БД
var AuthDB *sqlx.DB // Глобальная переменная для пула подключений к БД аутентификации

const defaultMainDbName = "NotesServer.db"
const defaultAuthDbName = "AuthServer.db"

// getDbPath определяет путь к файлу БД.
func getDbPath(defaultDbName string) (string, error) {
	exePath, err := os.Executable()
	if err != nil {
		log.Printf("Warning: Could not get executable path: %v. Using current directory for DB.", err)
		// Попробуем использовать текущую рабочую директорию, если путь к exe не получен
		wd, wdErr := os.Getwd()
		if wdErr != nil {
			return "", fmt.Errorf("failed to get executable path and working directory: %v, %v", err, wdErr)
		}
		exePath = wd // Используем текущую директорию как базу для пути к БД
	} else {
		exePath = filepath.Dir(exePath) // Директория, где лежит исполняемый файл
	}

	// Базы данных будут лежать в корне проекта (где NotesServerGO.exe)
	// Это изменение относительно предыдущей логики, где была папка 'databases'
	// dataSourceName := filepath.Join(exePath, defaultDbName)

	// Пользователь просил, чтобы база была в корне нового сервера,
	// что означает корневую директорию проекта NotesServerGO.
	// Если os.Executable() вернул C:\\...\\NotesServerGO\\NotesServerGO.exe,
	// то filepath.Dir(exePath) будет C:\\...\\NotesServerGO
	// Если же сервер запускается из корня командой go run main.go,
	// то os.Getwd() даст правильный путь к корню проекта.

	// Для AuthServer.db и NotesServer.db, они должны быть в корневой директории NotesServerGO.
	// Если мы запускаем `go run main.go` из `NotesServerGO`, то `os.Getwd()` вернет путь к `NotesServerGO`.
	// Если собранный .exe лежит в `NotesServerGO`, то `filepath.Dir(exePath)` также укажет на `NotesServerGO`.

	// Мы будем использовать текущую рабочую директорию как корень для БД.
	// Это наиболее предсказуемо при запуске `go run main.go`
	// и если .exe помещается в корень проекта.
	currentWorkDir, err := os.Getwd()
	if err != nil {
		return "", fmt.Errorf("failed to get current working directory: %w", err)
	}
	dataSourceName := filepath.Join(currentWorkDir, defaultDbName)

	log.Printf("Using database file at: %s", dataSourceName)
	return dataSourceName, nil
}

// InitMainDB инициализирует подключение к основной базе данных SQLite (NotesServer.db).
func InitMainDB() error {
	dataSourceName, err := getDbPath(defaultMainDbName)
	if err != nil {
		return err
	}

	MainDB, err = sqlx.Connect("sqlite3", dataSourceName+"?_foreign_keys=on") // Включаем поддержку внешних ключей
	if err != nil {
		return fmt.Errorf("failed to connect to main database: %w", err)
	}

	if err = MainDB.Ping(); err != nil {
		return fmt.Errorf("failed to ping main database: %w", err)
	}
	log.Println("Successfully connected to the main database (NotesServer.db).")

	// Создание таблиц для основной БД (все, кроме Users)
	schema := GetMainSchema() // Новая функция, возвращающая схему без Users
	if _, err = MainDB.Exec(schema); err != nil {
		return fmt.Errorf("failed to execute main schema: %w", err)
	}
	log.Println("Main database schema applied successfully.")

	// Обновляем схему для добавления недостающих полей
	if err = EnsureFolderSchemaUpgrade(); err != nil {
		return fmt.Errorf("failed to upgrade folder schema: %w", err)
	}

	// Обновляем схему для добавления недостающих полей в ScheduleEntries
	if err = EnsureScheduleEntriesSchemaUpgrade(); err != nil {
		return fmt.Errorf("failed to upgrade schedule entries schema: %w", err)
	}

	return nil
}

// InitAuthDB инициализирует подключение к базе данных аутентификации (AuthServer.db).
func InitAuthDB(filePath string) error {
	log.Printf("Using database file at: %s", filePath)
	var err error
	// Добавляем ?_loc=auto для автоматического определения формата времени
	AuthDB, err = sqlx.Connect("sqlite3", filePath+"?_loc=auto")
	if err != nil {
		return fmt.Errorf("failed to connect to auth database: %w", err)
	}

	if err = AuthDB.Ping(); err != nil {
		return fmt.Errorf("failed to ping auth database: %w", err)
	}
	log.Println("Successfully connected to the auth database (AuthServer.db).")

	// Создание таблицы Users для БД аутентификации
	schema := GetAuthSchema() // Новая функция, возвращающая схему только для Users
	if _, err = AuthDB.Exec(schema); err != nil {
		return fmt.Errorf("failed to execute auth schema: %w", err)
	}
	log.Println("Auth database schema (Users table) applied successfully.")
	return nil
}

// GetDB (переименована в GetMainDB) возвращает текущее подключение к основной базе данных.
func GetMainDB() *sqlx.DB {
	return MainDB
}

// GetAuthDB возвращает текущее подключение к базе данных аутентификации.
func GetAuthDB() *sqlx.DB {
	return AuthDB
}

// InitDB (старая функция, теперь вызывает обе инициализации)
// Обеспечивает обратную совместимость для вызова из main.go
// Важно: порядок может иметь значение, если есть зависимости, но у нас их нет между Auth и Main.
func InitDB() error {
	log.Println("Initializing databases...")
	if err := InitAuthDB(defaultAuthDbName); err != nil {
		return fmt.Errorf("failed to initialize AuthDB: %w", err)
	}
	if err := InitMainDB(); err != nil {
		return fmt.Errorf("failed to initialize MainDB: %w", err)
	}
	log.Println("All databases initialized successfully.")
	return nil
}

// EnsureFolderSchemaUpgrade добавляет недостающие поля в таблицу Folders
func EnsureFolderSchemaUpgrade() error {
	// Проверяем, есть ли поле Color
	var colorColumnExists bool
	err := MainDB.Get(&colorColumnExists, `
		SELECT COUNT(*) > 0 
		FROM pragma_table_info('Folders') 
		WHERE name = 'Color'
	`)
	if err != nil {
		log.Printf("Ошибка проверки колонки Color: %v", err)
	} else if !colorColumnExists {
		_, err = MainDB.Exec(`ALTER TABLE Folders ADD COLUMN Color INTEGER DEFAULT 0`)
		if err != nil {
			return fmt.Errorf("failed to add Color column: %w", err)
		}
		log.Printf("Добавлена колонка Color в таблицу Folders")
	}

	// Проверяем, есть ли поле IsExpanded
	var isExpandedColumnExists bool
	err = MainDB.Get(&isExpandedColumnExists, `
		SELECT COUNT(*) > 0 
		FROM pragma_table_info('Folders') 
		WHERE name = 'IsExpanded'
	`)
	if err != nil {
		log.Printf("Ошибка проверки колонки IsExpanded: %v", err)
	} else if !isExpandedColumnExists {
		_, err = MainDB.Exec(`ALTER TABLE Folders ADD COLUMN IsExpanded BOOLEAN DEFAULT 1`)
		if err != nil {
			return fmt.Errorf("failed to add IsExpanded column: %w", err)
		}
		log.Printf("Добавлена колонка IsExpanded в таблицу Folders")
	}

	return nil
}

// EnsureScheduleEntriesSchemaUpgrade добавляет недостающие поля в таблицу ScheduleEntries
func EnsureScheduleEntriesSchemaUpgrade() error {
	// Проверяем, есть ли поле TagsJson
	var tagsJsonColumnExists bool
	err := MainDB.Get(&tagsJsonColumnExists, `
		SELECT COUNT(*) > 0 
		FROM pragma_table_info('ScheduleEntries') 
		WHERE name = 'TagsJson'
	`)
	if err != nil {
		log.Printf("Ошибка проверки колонки TagsJson: %v", err)
	} else if !tagsJsonColumnExists {
		_, err = MainDB.Exec(`ALTER TABLE ScheduleEntries ADD COLUMN TagsJson TEXT`)
		if err != nil {
			return fmt.Errorf("failed to add TagsJson column: %w", err)
		}
		log.Printf("Добавлена колонка TagsJson в таблицу ScheduleEntries")
	}

	return nil
}
