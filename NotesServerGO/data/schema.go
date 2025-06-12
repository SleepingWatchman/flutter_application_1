package data

const usersSchema = `
CREATE TABLE IF NOT EXISTS Users (
    Id INTEGER PRIMARY KEY AUTOINCREMENT,
    Username TEXT NOT NULL UNIQUE, -- В C# было UserName, здесь Username для консистентности с моделью Go (RegisterRequest)
    Email TEXT NOT NULL UNIQUE,
    DisplayName TEXT NOT NULL,
    PhotoUrl TEXT,
    PasswordHash TEXT NOT NULL,
    CreatedAt DATETIME NOT NULL,
    UpdatedAt DATETIME NOT NULL
);
`

const mainSchema = `
CREATE TABLE IF NOT EXISTS Notes (
    Id INTEGER PRIMARY KEY AUTOINCREMENT,
    DatabaseId INTEGER NOT NULL, -- Внешний ключ к SharedDatabases.Id
    Title TEXT NOT NULL,
    Content TEXT,
    FolderId INTEGER,      
    CreatedAt DATETIME NOT NULL,
    UpdatedAt DATETIME NOT NULL,
    ImagesJson TEXT DEFAULT '[]',
    MetadataJson TEXT DEFAULT '{}',
    ContentJson TEXT,
    FOREIGN KEY (DatabaseId) REFERENCES SharedDatabases(Id) ON DELETE CASCADE,
    FOREIGN KEY (FolderId) REFERENCES Folders(Id) ON DELETE SET NULL 
);

CREATE TABLE IF NOT EXISTS Folders (
    Id INTEGER PRIMARY KEY AUTOINCREMENT,
    DatabaseId INTEGER NOT NULL, -- Внешний ключ к SharedDatabases.Id
    Name TEXT NOT NULL,
    ParentId INTEGER,       
    CreatedAt DATETIME NOT NULL,
    UpdatedAt DATETIME NOT NULL,
    Color INTEGER DEFAULT 0,
    IsExpanded BOOLEAN DEFAULT 1,
    FOREIGN KEY (DatabaseId) REFERENCES SharedDatabases(Id) ON DELETE CASCADE,
    FOREIGN KEY (ParentId) REFERENCES Folders(Id) ON DELETE CASCADE 
);

CREATE TABLE IF NOT EXISTS SharedDatabases (
    Id INTEGER PRIMARY KEY AUTOINCREMENT,
    Name TEXT NOT NULL,
    OwnerUserId INTEGER NOT NULL, -- Это будет ссылаться на Users.Id в AuthDB. Прямой FK не ставим между разными файлами БД.
    CreatedAt DATETIME NOT NULL,
    UpdatedAt DATETIME NOT NULL,
    Version TEXT DEFAULT '1.0.0',
    IsActive BOOLEAN DEFAULT 1,
    LastSync DATETIME DEFAULT CURRENT_TIMESTAMP
    -- FOREIGN KEY (OwnerUserId) REFERENCES Users(Id) ON DELETE CASCADE -- Убрано, т.к. Users в другой БД
);

CREATE TABLE IF NOT EXISTS SharedDatabaseUsers (
    SharedDatabaseId INTEGER NOT NULL,
    UserId INTEGER NOT NULL, -- Это будет ссылаться на Users.Id в AuthDB. Прямой FK не ставим.
    Role TEXT NOT NULL, -- "owner", "editor", "viewer"
    JoinedAt DATETIME NOT NULL,
    PRIMARY KEY (SharedDatabaseId, UserId),
    FOREIGN KEY (SharedDatabaseId) REFERENCES SharedDatabases(Id) ON DELETE CASCADE
    -- FOREIGN KEY (UserId) REFERENCES Users(Id) ON DELETE CASCADE -- Убрано, т.к. Users в другой БД
);

CREATE TABLE IF NOT EXISTS ScheduleEntries (
    Id INTEGER PRIMARY KEY AUTOINCREMENT,
    Time TEXT NOT NULL,                  
    Date TEXT NOT NULL,                  
    Note TEXT,
    DynamicFieldsJson TEXT,
    RecurrenceJson TEXT,                 
    TagsJson TEXT,                       
    DatabaseId INTEGER NOT NULL,         
    CreatedAt DATETIME NOT NULL,
    UpdatedAt DATETIME NOT NULL,
    FOREIGN KEY (DatabaseId) REFERENCES SharedDatabases(Id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS PinboardNotes (
    Id INTEGER PRIMARY KEY AUTOINCREMENT,
    Title TEXT NOT NULL,
    Content TEXT NOT NULL,
    PositionX REAL NOT NULL,
    PositionY REAL NOT NULL,
    Width REAL NOT NULL,
    Height REAL NOT NULL,
    BackgroundColor INTEGER NOT NULL,    
    IconCodePoint INTEGER NOT NULL,      
    DatabaseId INTEGER NOT NULL,
    CreatedAt DATETIME NOT NULL,
    UpdatedAt DATETIME NOT NULL,
    FOREIGN KEY (DatabaseId) REFERENCES SharedDatabases(Id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS Connections (
    Id INTEGER PRIMARY KEY AUTOINCREMENT,
    FromNoteId INTEGER NOT NULL,         
    ToNoteId INTEGER NOT NULL,           
    Name TEXT NOT NULL,
    ConnectionColor INTEGER NOT NULL,    
    DatabaseId INTEGER NOT NULL,
    CreatedAt DATETIME NOT NULL,
    UpdatedAt DATETIME NOT NULL,
    FOREIGN KEY (DatabaseId) REFERENCES SharedDatabases(Id) ON DELETE CASCADE,
    FOREIGN KEY (FromNoteId) REFERENCES PinboardNotes(Id) ON DELETE CASCADE, 
    FOREIGN KEY (ToNoteId) REFERENCES PinboardNotes(Id) ON DELETE CASCADE    
);

CREATE TABLE IF NOT EXISTS NoteImages (
    Id INTEGER PRIMARY KEY AUTOINCREMENT,
    NoteId INTEGER NOT NULL,             
    ImagePath TEXT NOT NULL,             
    FileName TEXT NOT NULL,              
    DatabaseId INTEGER NOT NULL,         
    CreatedAt DATETIME NOT NULL,
    UpdatedAt DATETIME NOT NULL,
    FOREIGN KEY (DatabaseId) REFERENCES SharedDatabases(Id) ON DELETE CASCADE,
    FOREIGN KEY (NoteId) REFERENCES Notes(Id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS SharedDatabaseInvitations (
    Id INTEGER PRIMARY KEY AUTOINCREMENT,
    SharedDatabaseId INTEGER NOT NULL,
    InviterUserId INTEGER NOT NULL,
    InviteeEmail TEXT NOT NULL,
    Role TEXT NOT NULL,
    Status TEXT NOT NULL DEFAULT 'pending',
    CreatedAt DATETIME NOT NULL,
    ExpiresAt DATETIME NOT NULL,
    FOREIGN KEY (SharedDatabaseId) REFERENCES SharedDatabases(Id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS SyncChanges (
    Id INTEGER PRIMARY KEY AUTOINCREMENT,
    DatabaseId INTEGER NOT NULL,
    EntityType TEXT NOT NULL,
    EntityId INTEGER NOT NULL,
    Operation TEXT NOT NULL,
    Data TEXT NOT NULL,
    UserId INTEGER NOT NULL,
    CreatedAt DATETIME NOT NULL,
    Version TEXT NOT NULL,
    FOREIGN KEY (DatabaseId) REFERENCES SharedDatabases(Id) ON DELETE CASCADE
);
`

// GetAuthSchema возвращает SQL-схему для базы данных аутентификации (только таблица Users).
func GetAuthSchema() string {
	return usersSchema
}

// GetMainSchema возвращает SQL-схему для основной базы данных (все таблицы, кроме Users).
func GetMainSchema() string {
	// Сначала таблицы без внешних ключей или с ключами на таблицы, которые точно будут созданы до них
	orderedSchema := SharedDatabasesTable() + FoldersTable() + NotesTable() + ScheduleEntriesTable() + PinboardNotesTable() + ConnectionsTable() + NoteImagesTable() + SharedDatabaseUsersTable() + SharedDatabaseInvitationsTable() + SyncChangesTable()
	return orderedSchema
}

// Вспомогательные функции для генерации схем таблиц в правильном порядке для FK
// Это более надежно, чем одна большая строка, если порядок важен.

func UsersTable() string { // Эта таблица теперь в AuthDB
	return usersSchema
}

func SharedDatabasesTable() string {
	return `
CREATE TABLE IF NOT EXISTS SharedDatabases (
    Id INTEGER PRIMARY KEY AUTOINCREMENT,
    Name TEXT NOT NULL,
    OwnerUserId INTEGER NOT NULL, 
    CreatedAt DATETIME NOT NULL,
    UpdatedAt DATETIME NOT NULL,
    Version TEXT DEFAULT '1.0.0',
    IsActive BOOLEAN DEFAULT 1,
    LastSync DATETIME DEFAULT CURRENT_TIMESTAMP
);
`
}

func FoldersTable() string {
	return `
CREATE TABLE IF NOT EXISTS Folders (
    Id INTEGER PRIMARY KEY AUTOINCREMENT,
    DatabaseId INTEGER NOT NULL,
    Name TEXT NOT NULL,
    ParentId INTEGER,
    CreatedAt DATETIME NOT NULL,
    UpdatedAt DATETIME NOT NULL,
    Color INTEGER DEFAULT 0,
    IsExpanded BOOLEAN DEFAULT 1,
    FOREIGN KEY (DatabaseId) REFERENCES SharedDatabases(Id) ON DELETE CASCADE,
    FOREIGN KEY (ParentId) REFERENCES Folders(Id) ON DELETE CASCADE
);
`
}

func NotesTable() string {
	return `
CREATE TABLE IF NOT EXISTS Notes (
    Id INTEGER PRIMARY KEY AUTOINCREMENT,
    DatabaseId INTEGER NOT NULL,
    Title TEXT NOT NULL,
    Content TEXT,
    FolderId INTEGER,
    CreatedAt DATETIME NOT NULL,
    UpdatedAt DATETIME NOT NULL,
    ImagesJson TEXT DEFAULT '[]',
    MetadataJson TEXT DEFAULT '{}',
    ContentJson TEXT,
    FOREIGN KEY (DatabaseId) REFERENCES SharedDatabases(Id) ON DELETE CASCADE,
    FOREIGN KEY (FolderId) REFERENCES Folders(Id) ON DELETE SET NULL
);
`
}

func SharedDatabaseUsersTable() string {
	return `
CREATE TABLE IF NOT EXISTS SharedDatabaseUsers (
    SharedDatabaseId INTEGER NOT NULL,
    UserId INTEGER NOT NULL, 
    Role TEXT NOT NULL, 
    JoinedAt DATETIME NOT NULL,
    PRIMARY KEY (SharedDatabaseId, UserId),
    FOREIGN KEY (SharedDatabaseId) REFERENCES SharedDatabases(Id) ON DELETE CASCADE
);
`
}

func ScheduleEntriesTable() string {
	return `
CREATE TABLE IF NOT EXISTS ScheduleEntries (
    Id INTEGER PRIMARY KEY AUTOINCREMENT,
    Time TEXT NOT NULL,
    Date TEXT NOT NULL,
    Note TEXT,
    DynamicFieldsJson TEXT,
    RecurrenceJson TEXT,
    TagsJson TEXT,
    DatabaseId INTEGER NOT NULL,
    CreatedAt DATETIME NOT NULL,
    UpdatedAt DATETIME NOT NULL,
    FOREIGN KEY (DatabaseId) REFERENCES SharedDatabases(Id) ON DELETE CASCADE
);
`
}

func PinboardNotesTable() string {
	return `
CREATE TABLE IF NOT EXISTS PinboardNotes (
    Id INTEGER PRIMARY KEY AUTOINCREMENT,
    Title TEXT NOT NULL,
    Content TEXT NOT NULL,
    PositionX REAL NOT NULL,
    PositionY REAL NOT NULL,
    Width REAL NOT NULL,
    Height REAL NOT NULL,
    BackgroundColor INTEGER NOT NULL,
    IconCodePoint INTEGER NOT NULL,
    DatabaseId INTEGER NOT NULL,
    CreatedAt DATETIME NOT NULL,
    UpdatedAt DATETIME NOT NULL,
    FOREIGN KEY (DatabaseId) REFERENCES SharedDatabases(Id) ON DELETE CASCADE
);
`
}

func ConnectionsTable() string {
	return `
CREATE TABLE IF NOT EXISTS Connections (
    Id INTEGER PRIMARY KEY AUTOINCREMENT,
    FromNoteId INTEGER NOT NULL,
    ToNoteId INTEGER NOT NULL,
    Name TEXT NOT NULL,
    ConnectionColor INTEGER NOT NULL,
    DatabaseId INTEGER NOT NULL,
    CreatedAt DATETIME NOT NULL,
    UpdatedAt DATETIME NOT NULL,
    FOREIGN KEY (DatabaseId) REFERENCES SharedDatabases(Id) ON DELETE CASCADE,
    FOREIGN KEY (FromNoteId) REFERENCES PinboardNotes(Id) ON DELETE CASCADE,
    FOREIGN KEY (ToNoteId) REFERENCES PinboardNotes(Id) ON DELETE CASCADE
);
`
}

func NoteImagesTable() string {
	return `
CREATE TABLE IF NOT EXISTS NoteImages (
    Id INTEGER PRIMARY KEY AUTOINCREMENT,
    NoteId INTEGER NOT NULL,
    ImagePath TEXT NOT NULL,
    FileName TEXT NOT NULL,
    DatabaseId INTEGER NOT NULL,
    CreatedAt DATETIME NOT NULL,
    UpdatedAt DATETIME NOT NULL,
    FOREIGN KEY (DatabaseId) REFERENCES SharedDatabases(Id) ON DELETE CASCADE,
    FOREIGN KEY (NoteId) REFERENCES Notes(Id) ON DELETE CASCADE
);
`
}

func SharedDatabaseInvitationsTable() string {
	return `
CREATE TABLE IF NOT EXISTS SharedDatabaseInvitations (
    Id INTEGER PRIMARY KEY AUTOINCREMENT,
    SharedDatabaseId INTEGER NOT NULL,
    InviterUserId INTEGER NOT NULL,
    InviteeEmail TEXT NOT NULL,
    Role TEXT NOT NULL,
    Status TEXT NOT NULL DEFAULT 'pending',
    CreatedAt DATETIME NOT NULL,
    ExpiresAt DATETIME NOT NULL,
    FOREIGN KEY (SharedDatabaseId) REFERENCES SharedDatabases(Id) ON DELETE CASCADE
);
`
}

func SyncChangesTable() string {
	return `
CREATE TABLE IF NOT EXISTS SyncChanges (
    Id INTEGER PRIMARY KEY AUTOINCREMENT,
    DatabaseId INTEGER NOT NULL,
    EntityType TEXT NOT NULL,
    EntityId INTEGER NOT NULL,
    Operation TEXT NOT NULL,
    Data TEXT NOT NULL,
    UserId INTEGER NOT NULL,
    CreatedAt DATETIME NOT NULL,
    Version TEXT NOT NULL,
    FOREIGN KEY (DatabaseId) REFERENCES SharedDatabases(Id) ON DELETE CASCADE
);
`
}

// Старая функция GetSchema, не используется напрямую для Init, но может быть полезна для справки
func GetCombinedSchema_DO_NOT_USE_FOR_INIT() string {
	return usersSchema + mainSchema
}
