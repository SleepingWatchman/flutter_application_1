using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using NotesServer.Models;
using System.Linq;
using NotesServer.Data;
using SQLite;
using Microsoft.Extensions.Logging;
using Microsoft.AspNetCore.Hosting;
using System.IO;

namespace NotesServer.Services
{
    public interface ICollaborationService
    {
        Task<CollaborationDatabase> CreateDatabaseAsync(string userId);
        Task<List<CollaborationDatabase>> GetUserDatabasesAsync(string userId);
        Task DeleteDatabaseAsync(int databaseId, string userId);
        Task SaveDatabaseBackupAsync(int databaseId, string userId, BackupData backupData);
        Task<BackupData> GetDatabaseBackupAsync(int databaseId, string userId);
        Task<CollaborationDatabase> GetDatabaseAsync(int databaseId, string userId);
        Task ReplaceLocalDatabaseAsync(int databaseId, string userId, BackupData backupData);
    }

    public class CollaborationService : ICollaborationService
    {
        private readonly ApplicationDbContext _context;
        private readonly ILogger<CollaborationService> _logger;
        private readonly IWebHostEnvironment _environment;
        private const string BackupDirectoryName = "backups";

        public CollaborationService(
            ApplicationDbContext context, 
            ILogger<CollaborationService> logger,
            IWebHostEnvironment environment)
        {
            _context = context;
            _logger = logger;
            _environment = environment;
        }

        public async Task<CollaborationDatabase> CreateDatabaseAsync(string userId)
        {
            try
            {
                var databaseFileName = $"{Guid.NewGuid()}.db";
                var databasePath = Path.Combine(_environment.ContentRootPath, "Databases", databaseFileName);
                
                // Создаем директорию для баз данных, если она не существует
                Directory.CreateDirectory(Path.GetDirectoryName(databasePath)!);
                
                var database = new CollaborationDatabase
                {
                    UserId = userId,
                    CreatedAt = DateTime.UtcNow,
                    DatabaseName = $"collab_db_{Guid.NewGuid()}",
                    ConnectionString = databasePath
                };

                _context.CollaborationDatabases.Add(database);
                await _context.SaveChangesAsync();

                // Создаем новую базу данных SQLite
                using (var db = new SQLiteConnection(databasePath))
                {
                    // Создаем таблицы с явным указанием типов колонок
                    db.Execute(@"
                        CREATE TABLE IF NOT EXISTS folders (
                            id INTEGER PRIMARY KEY AUTOINCREMENT,
                            name TEXT NOT NULL,
                            color INTEGER NOT NULL,
                            is_expanded INTEGER NOT NULL DEFAULT 1
                        );
                        
                        CREATE TABLE IF NOT EXISTS notes (
                            id INTEGER PRIMARY KEY AUTOINCREMENT,
                            title TEXT NOT NULL,
                            content TEXT,
                            folder_id INTEGER,
                            created_at TEXT NOT NULL,
                            updated_at TEXT NOT NULL,
                            images TEXT,
                            metadata TEXT,
                            content_json TEXT,
                            FOREIGN KEY (folder_id) REFERENCES folders (id) ON DELETE SET NULL
                        );
                        
                        CREATE TABLE IF NOT EXISTS schedule_entries(
                            id INTEGER PRIMARY KEY AUTOINCREMENT,
                            time TEXT,
                            date TEXT,
                            note TEXT,
                            dynamic_fields_json TEXT
                        );
                        
                        CREATE TABLE IF NOT EXISTS pinboard_notes(
                            id INTEGER PRIMARY KEY AUTOINCREMENT,
                            title TEXT,
                            content TEXT,
                            position_x REAL,
                            position_y REAL,
                            width REAL,
                            height REAL,
                            background_color INTEGER,
                            icon INTEGER
                        );
                        
                        CREATE TABLE IF NOT EXISTS connections(
                            id INTEGER PRIMARY KEY AUTOINCREMENT,
                            from_note_id INTEGER,
                            to_note_id INTEGER,
                            type TEXT,
                            name TEXT,
                            connection_color INTEGER,
                            FOREIGN KEY (from_note_id) REFERENCES pinboard_notes (id),
                            FOREIGN KEY (to_note_id) REFERENCES pinboard_notes (id)
                        );
                        
                        CREATE TABLE IF NOT EXISTS note_images (
                            id INTEGER PRIMARY KEY AUTOINCREMENT,
                            note_id INTEGER NOT NULL,
                            file_name TEXT NOT NULL,
                            image_data BLOB NOT NULL,
                            FOREIGN KEY (note_id) REFERENCES notes (id) ON DELETE CASCADE
                        );
                    ");
                }

                // Создаем пустую резервную копию
                var backupData = new BackupData
                {
                    Notes = new List<Note>(),
                    Folders = new List<Folder>(),
                    ScheduleEntries = new List<ScheduleEntry>(),
                    PinboardNotes = new List<PinboardNote>(),
                    Connections = new List<Connection>(),
                    NoteImages = new List<NoteImage>(),
                    LastModified = DateTime.UtcNow,
                    DatabaseId = database.Id.ToString(),
                    UserId = userId
                };

                await SaveDatabaseBackupAsync(database.Id, userId, backupData);

                _logger.LogInformation($"Создана новая база данных для пользователя {userId}");
                return database;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, $"Ошибка при создании базы данных для пользователя {userId}");
                throw new Exception($"Ошибка при создании базы данных: {ex.Message}");
            }
        }

        public async Task<List<CollaborationDatabase>> GetUserDatabasesAsync(string userId)
        {
            try
            {
                return await _context.CollaborationDatabases
                    .Where(db => db.UserId == userId)
                    .ToListAsync();
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, $"Ошибка при получении списка баз данных для пользователя {userId}");
                throw;
            }
        }

        public async Task DeleteDatabaseAsync(int databaseId, string userId)
        {
            try
            {
                var database = await _context.CollaborationDatabases
                    .FirstOrDefaultAsync(db => db.Id == databaseId && db.UserId == userId);

                if (database == null)
                {
                    throw new Exception("База данных не найдена");
                }

                // Удаляем файл базы данных
                if (File.Exists(database.ConnectionString))
                {
                    File.Delete(database.ConnectionString);
                }

                _context.CollaborationDatabases.Remove(database);
                await _context.SaveChangesAsync();

                _logger.LogInformation($"Удалена база данных {databaseId} для пользователя {userId}");
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, $"Ошибка при удалении базы данных {databaseId} для пользователя {userId}");
                throw;
            }
        }

        public async Task SaveDatabaseBackupAsync(int databaseId, string userId, BackupData backupData)
        {
            try
            {
                // Проверяем существование базы данных
                var database = await _context.CollaborationDatabases
                    .FirstOrDefaultAsync(db => db.Id == databaseId);

                if (database == null)
                {
                    throw new Exception("База данных не найдена");
                }

                backupData.LastModified = DateTime.UtcNow;
                backupData.DatabaseId = databaseId.ToString();
                backupData.UserId = userId;

                // Создаем директорию для резервных копий, если она не существует
                var backupDir = Path.Combine(_environment.ContentRootPath, BackupDirectoryName);
                Directory.CreateDirectory(backupDir);

                // Создаем файл резервной копии
                var backupPath = Path.Combine(backupDir, $"{databaseId}.json");
                await File.WriteAllTextAsync(backupPath, System.Text.Json.JsonSerializer.Serialize(backupData));

                _logger.LogInformation($"Сохранена резервная копия базы данных {databaseId} для пользователя {userId}");
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, $"Ошибка при сохранении резервной копии базы данных {databaseId} для пользователя {userId}");
                throw;
            }
        }

        public async Task<BackupData> GetDatabaseBackupAsync(int databaseId, string userId)
        {
            try
            {
                // Проверяем существование базы данных
                var database = await _context.CollaborationDatabases
                    .FirstOrDefaultAsync(db => db.Id == databaseId);

                if (database == null)
                {
                    throw new Exception("База данных не найдена");
                }

                var backupPath = Path.Combine(_environment.ContentRootPath, BackupDirectoryName, $"{databaseId}.json");
                
                if (!File.Exists(backupPath))
                {
                    throw new Exception("Резервная копия не найдена");
                }

                var json = await File.ReadAllTextAsync(backupPath);
                var backup = System.Text.Json.JsonSerializer.Deserialize<BackupData>(json);

                if (backup == null)
                {
                    throw new Exception("Ошибка при десериализации резервной копии");
                }

                _logger.LogInformation($"Загружена резервная копия базы данных {databaseId} для пользователя {userId}");
                return backup;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, $"Ошибка при загрузке резервной копии базы данных {databaseId} для пользователя {userId}");
                throw new Exception($"Ошибка при загрузке резервной копии: {ex.Message}");
            }
        }

        public async Task<CollaborationDatabase> GetDatabaseAsync(int databaseId, string userId)
        {
            try
            {
                var database = await _context.CollaborationDatabases
                    .FirstOrDefaultAsync(db => db.Id == databaseId);

                if (database == null)
                {
                    throw new Exception("База данных не найдена");
                }

                return database;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, $"Ошибка при получении базы данных {databaseId} для пользователя {userId}");
                throw;
            }
        }

        public async Task ReplaceLocalDatabaseAsync(int databaseId, string userId, BackupData backupData)
        {
            try
            {
                var database = await _context.CollaborationDatabases
                    .FirstOrDefaultAsync(db => db.Id == databaseId);

                if (database == null)
                {
                    throw new Exception("База данных не найдена");
                }

                // Создаем таблицы, если они не существуют
                using (var db = new SQLiteConnection(database.ConnectionString))
                {
                    // Создаем таблицу папок
                    db.Execute(@"
                        CREATE TABLE IF NOT EXISTS folders (
                            id INTEGER PRIMARY KEY AUTOINCREMENT,
                            name TEXT NOT NULL,
                            color INTEGER NOT NULL,
                            is_expanded INTEGER NOT NULL DEFAULT 1
                        )
                    ");

                    // Создаем таблицу заметок
                    db.Execute(@"
                        CREATE TABLE IF NOT EXISTS notes (
                            id INTEGER PRIMARY KEY AUTOINCREMENT,
                            title TEXT NOT NULL,
                            content TEXT,
                            folder_id INTEGER,
                            created_at TEXT NOT NULL,
                            updated_at TEXT NOT NULL,
                            images TEXT,
                            metadata TEXT,
                            content_json TEXT,
                            FOREIGN KEY (folder_id) REFERENCES folders (id) ON DELETE SET NULL
                        )
                    ");

                    // Создаем таблицу расписания
                    db.Execute(@"
                        CREATE TABLE IF NOT EXISTS schedule_entries(
                            id INTEGER PRIMARY KEY AUTOINCREMENT,
                            time TEXT,
                            date TEXT,
                            note TEXT,
                            dynamic_fields_json TEXT
                        )
                    ");

                    // Создаем таблицу заметок на доске
                    db.Execute(@"
                        CREATE TABLE IF NOT EXISTS pinboard_notes(
                            id INTEGER PRIMARY KEY AUTOINCREMENT,
                            title TEXT,
                            content TEXT,
                            position_x REAL,
                            position_y REAL,
                            width REAL,
                            height REAL,
                            background_color INTEGER,
                            icon INTEGER
                        )
                    ");

                    // Создаем таблицу соединений
                    db.Execute(@"
                        CREATE TABLE IF NOT EXISTS connections(
                            id INTEGER PRIMARY KEY AUTOINCREMENT,
                            from_note_id INTEGER,
                            to_note_id INTEGER,
                            type TEXT,
                            name TEXT,
                            connection_color INTEGER,
                            FOREIGN KEY (from_note_id) REFERENCES pinboard_notes (id),
                            FOREIGN KEY (to_note_id) REFERENCES pinboard_notes (id)
                        )
                    ");

                    // Создаем таблицу изображений
                    db.Execute(@"
                        CREATE TABLE IF NOT EXISTS note_images (
                            id INTEGER PRIMARY KEY AUTOINCREMENT,
                            note_id INTEGER NOT NULL,
                            file_name TEXT NOT NULL,
                            image_data BLOB NOT NULL,
                            FOREIGN KEY (note_id) REFERENCES notes (id) ON DELETE CASCADE
                        )
                    ");
                }

                // Очищаем существующие данные в базе
                using (var db = new SQLiteConnection(database.ConnectionString))
                {
                    db.Execute("DELETE FROM notes");
                    db.Execute("DELETE FROM folders");
                    db.Execute("DELETE FROM schedule_entries");
                    db.Execute("DELETE FROM pinboard_notes");
                    db.Execute("DELETE FROM connections");
                    db.Execute("DELETE FROM note_images");
                }

                // Загружаем новые данные
                using (var db = new SQLiteConnection(database.ConnectionString))
                {
                    // Загружаем папки
                    if (backupData.Folders != null)
                    {
                        foreach (var folder in backupData.Folders)
                        {
                            db.Insert(new Folder
                            {
                                Id = folder.Id,
                                Name = folder.Name,
                                Color = folder.Color,
                                IsExpanded = folder.IsExpanded
                            });
                        }
                    }

                    // Загружаем заметки
                    if (backupData.Notes != null)
                    {
                        foreach (var note in backupData.Notes)
                        {
                            db.Insert(new Note
                            {
                                Id = note.Id,
                                Title = note.Title,
                                Content = note.Content,
                                FolderId = note.FolderId,
                                CreatedAt = note.CreatedAt,
                                UpdatedAt = note.UpdatedAt,
                                Images = note.Images,
                                Metadata = note.Metadata,
                                ContentJson = note.ContentJson
                            });
                        }
                    }

                    // Загружаем записи расписания
                    if (backupData.ScheduleEntries != null)
                    {
                        foreach (var entry in backupData.ScheduleEntries)
                        {
                            db.Insert(new ScheduleEntry
                            {
                                Id = entry.Id,
                                Time = entry.Time,
                                Date = entry.Date,
                                Note = entry.Note,
                                DynamicFieldsJson = entry.DynamicFieldsJson
                            });
                        }
                    }

                    // Загружаем заметки на доске
                    if (backupData.PinboardNotes != null)
                    {
                        foreach (var note in backupData.PinboardNotes)
                        {
                            db.Insert(new PinboardNote
                            {
                                Id = note.Id,
                                Title = note.Title,
                                Content = note.Content,
                                PositionX = note.PositionX,
                                PositionY = note.PositionY,
                                Width = note.Width,
                                Height = note.Height,
                                BackgroundColor = note.BackgroundColor,
                                Icon = note.Icon
                            });
                        }
                    }

                    // Загружаем связи
                    if (backupData.Connections != null)
                    {
                        foreach (var connection in backupData.Connections)
                        {
                            db.Insert(new Connection
                            {
                                Id = connection.Id,
                                FromNoteId = connection.FromNoteId,
                                ToNoteId = connection.ToNoteId,
                                Type = connection.Type,
                                Name = connection.Name,
                                ConnectionColor = connection.ConnectionColor
                            });
                        }
                    }

                    // Загружаем изображения
                    if (backupData.NoteImages != null)
                    {
                        foreach (var image in backupData.NoteImages)
                        {
                            db.Insert(new NoteImage
                            {
                                Id = image.Id,
                                NoteId = image.NoteId,
                                FileName = image.FileName,
                                ImageData = image.ImageData
                            });
                        }
                    }
                }

                _logger.LogInformation($"Данные в базе данных {databaseId} успешно заменены для пользователя {userId}");
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, $"Ошибка при замене данных в базе данных {databaseId} для пользователя {userId}");
                throw;
            }
        }
    }
} 