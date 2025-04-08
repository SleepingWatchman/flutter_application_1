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
                        CREATE TABLE IF NOT EXISTS Notes (
                            Id INTEGER PRIMARY KEY AUTOINCREMENT,
                            Title TEXT NOT NULL,
                            Content TEXT NOT NULL,
                            FolderId INTEGER,
                            CreatedAt TEXT NOT NULL,
                            UpdatedAt TEXT NOT NULL,
                            ImagesJson TEXT DEFAULT '[]',
                            MetadataJson TEXT DEFAULT '{}',
                            ContentJson TEXT,
                            DatabaseId INTEGER NOT NULL
                        );
                        
                        CREATE TABLE IF NOT EXISTS Folders (
                            Id INTEGER PRIMARY KEY AUTOINCREMENT,
                            Name TEXT NOT NULL,
                            ParentId INTEGER,
                            CreatedAt TEXT NOT NULL,
                            UpdatedAt TEXT NOT NULL,
                            DatabaseId INTEGER NOT NULL
                        );
                        
                        CREATE TABLE IF NOT EXISTS ScheduleEntries (
                            Id INTEGER PRIMARY KEY AUTOINCREMENT,
                            Title TEXT NOT NULL,
                            Description TEXT,
                            StartTime TEXT NOT NULL,
                            EndTime TEXT NOT NULL,
                            CreatedAt TEXT NOT NULL,
                            UpdatedAt TEXT NOT NULL,
                            DatabaseId INTEGER NOT NULL
                        );
                        
                        CREATE TABLE IF NOT EXISTS PinboardNotes (
                            Id INTEGER PRIMARY KEY AUTOINCREMENT,
                            Title TEXT NOT NULL,
                            Content TEXT NOT NULL,
                            PositionX REAL NOT NULL,
                            PositionY REAL NOT NULL,
                            CreatedAt TEXT NOT NULL,
                            UpdatedAt TEXT NOT NULL,
                            DatabaseId INTEGER NOT NULL
                        );
                        
                        CREATE TABLE IF NOT EXISTS Connections (
                            Id INTEGER PRIMARY KEY AUTOINCREMENT,
                            SourceId INTEGER NOT NULL,
                            TargetId INTEGER NOT NULL,
                            Type TEXT NOT NULL,
                            CreatedAt TEXT NOT NULL,
                            UpdatedAt TEXT NOT NULL,
                            DatabaseId INTEGER NOT NULL
                        );
                        
                        CREATE TABLE IF NOT EXISTS NoteImages (
                            Id INTEGER PRIMARY KEY AUTOINCREMENT,
                            NoteId INTEGER NOT NULL,
                            ImagePath TEXT NOT NULL,
                            CreatedAt TEXT NOT NULL,
                            UpdatedAt TEXT NOT NULL,
                            DatabaseId INTEGER NOT NULL
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
                var database = await _context.CollaborationDatabases
                    .FirstOrDefaultAsync(db => db.Id == databaseId && db.UserId == userId);

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
                var database = await _context.CollaborationDatabases
                    .FirstOrDefaultAsync(db => db.Id == databaseId && db.UserId == userId);

                if (database == null)
                {
                    throw new Exception("База данных не найдена");
                }

                var backupPath = Path.Combine(_environment.ContentRootPath, BackupDirectoryName, $"{databaseId}.json");
                
                if (!File.Exists(backupPath))
                {
                    // Если резервная копия не существует, создаем пустую
                    var backupData = new BackupData
                    {
                        Notes = new List<Note>(),
                        Folders = new List<Folder>(),
                        ScheduleEntries = new List<ScheduleEntry>(),
                        PinboardNotes = new List<PinboardNote>(),
                        Connections = new List<Connection>(),
                        NoteImages = new List<NoteImage>(),
                        LastModified = DateTime.UtcNow,
                        DatabaseId = databaseId.ToString(),
                        UserId = userId
                    };

                    await SaveDatabaseBackupAsync(databaseId, userId, backupData);
                    return backupData;
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
                    .FirstOrDefaultAsync(db => db.Id == databaseId && db.UserId == userId);

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
    }
} 