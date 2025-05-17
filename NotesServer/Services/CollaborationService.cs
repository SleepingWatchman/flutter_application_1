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
using System.Text.Json;

namespace NotesServer.Services
{
    public interface ICollaborationService
    {
        Task<SharedDatabase> CreateDatabaseAsync(string userId, string name);
        Task<List<SharedDatabase>> GetUserDatabasesAsync(string userId);
        Task DeleteDatabaseAsync(string databaseId, string userId);
        Task SaveDatabaseBackupAsync(string databaseId, string userId, BackupData backupData);
        Task<BackupData> GetDatabaseBackupAsync(string databaseId, string userId);
        Task<SharedDatabase?> GetDatabaseAsync(string databaseId, string userId);
        Task ReplaceLocalDatabaseAsync(string databaseId, string userId, BackupData backupData);
        Task<Note?> GetNoteAsync(string databaseId, string noteId);
        Task SaveNoteAsync(string databaseId, Note note);
        Task DeleteNoteAsync(string databaseId, string noteId);
        Task JoinDatabaseAsync(string databaseId, string userId);
        Task LeaveDatabaseAsync(string databaseId, string userId);
        Task TransferOwnershipAsync(string databaseId, string currentOwnerId, string newOwnerId);
    }

    public class CollaborationService : ICollaborationService
    {
        private readonly ILogger<CollaborationService> _logger;
        private readonly string _databasesPath;
        private readonly ApplicationDbContext _context;

        public CollaborationService(
            ILogger<CollaborationService> logger,
            IWebHostEnvironment env,
            ApplicationDbContext context)
        {
            _logger = logger;
            _databasesPath = Path.Combine(env.ContentRootPath, "Databases");
            _context = context;
            
            // Создаем директорию для баз данных, если она не существует
            if (!Directory.Exists(_databasesPath))
            {
                Directory.CreateDirectory(_databasesPath);
            }
        }

        private string GetDatabasePath(string databaseId)
        {
            return Path.Combine(_databasesPath, $"{databaseId}.db");
        }

        public async Task<SharedDatabase> CreateDatabaseAsync(string userId, string name)
        {
            try
            {
                var databaseId = Guid.NewGuid().ToString();
                var dbPath = GetDatabasePath(databaseId);
                
                // Создаем файл базы данных
                using (var connection = new SQLiteConnection(dbPath))
                {
                    _logger.LogInformation("Создаю таблицу для типа: " + typeof(Note).FullName);
                    connection.CreateTable<Note>();
                    _logger.LogInformation("Создаю таблицу для типа: " + typeof(Folder).FullName);
                    connection.CreateTable<Folder>();
                    _logger.LogInformation("Создаю таблицу для типа: " + typeof(ScheduleEntry).FullName);
                    connection.CreateTable<ScheduleEntry>();
                    _logger.LogInformation("Создаю таблицу для типа: " + typeof(PinboardNote).FullName);
                    connection.CreateTable<PinboardNote>();
                    _logger.LogInformation("Создаю таблицу для типа: " + typeof(Connection).FullName);
                    connection.CreateTable<Connection>();
                    _logger.LogInformation("Создаю таблицу для типа: " + typeof(NoteImage).FullName);
                    connection.CreateTable<NoteImage>();
                }
                
                _logger.LogInformation($"Created collaboration database: {dbPath}");

                var database = new SharedDatabase
                {
                    Id = databaseId,
                    Name = name,
                    OwnerId = userId,
                    CreatedAt = DateTime.UtcNow,
                    DatabasePath = dbPath,
                    CollaboratorsJson = JsonSerializer.Serialize(new List<string> { userId })
                };

                _context.SharedDatabases.Add(database);
                await _context.SaveChangesAsync();

                return database;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, $"Error creating collaboration database for user {userId}");
                throw;
            }
        }

        public async Task<List<SharedDatabase>> GetUserDatabasesAsync(string userId)
        {
            try
            {
                _logger.LogInformation($"Getting databases for user {userId}");
                
                // Получаем все базы данных
                var databases = await _context.SharedDatabases.ToListAsync();
                
                // Фильтруем базы, где пользователь является владельцем или коллаборатором
                var filteredDatabases = databases.Where(db => 
                {
                    try
                    {
                        var collaborators = JsonSerializer.Deserialize<List<string>>(db.CollaboratorsJson) ?? new List<string>();
                        return db.OwnerId == userId || collaborators.Contains(userId);
                    }
                    catch (JsonException)
                    {
                        _logger.LogWarning($"Error deserializing collaborators for database {db.Id}. Using empty list.");
                        return db.OwnerId == userId;
                    }
                }).ToList();
                
                _logger.LogInformation($"Found {filteredDatabases.Count} databases for user {userId}");
                return filteredDatabases;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, $"Error getting databases for user {userId}");
                throw;
            }
        }

        public async Task DeleteDatabaseAsync(string databaseId, string userId)
        {
            try
            {
                var database = await _context.SharedDatabases
                    .FirstOrDefaultAsync(db => db.Id == databaseId && db.OwnerId == userId);

                if (database == null)
                {
                    throw new Exception($"Database {databaseId} not found or user {userId} is not the owner");
                }

                // Удаляем файл базы данных
                var dbPath = database.DatabasePath;
                if (File.Exists(dbPath))
                {
                    File.Delete(dbPath);
                }

                _context.SharedDatabases.Remove(database);
                await _context.SaveChangesAsync();
                
                _logger.LogInformation($"Deleted database {databaseId} for user {userId}");
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, $"Error deleting database {databaseId} for user {userId}");
                throw;
            }
        }

        public async Task JoinDatabaseAsync(string databaseId, string userId)
        {
            try
            {
                var database = await _context.SharedDatabases
                    .FirstOrDefaultAsync(db => db.Id == databaseId);

                if (database == null)
                {
                    throw new Exception($"Database {databaseId} not found");
                }

                if (database.OwnerId == userId)
                {
                    throw new Exception($"User {userId} is already the owner of database {databaseId}");
                }

                var collaborators = JsonSerializer.Deserialize<List<string>>(database.CollaboratorsJson) ?? new List<string>();
                
                if (collaborators.Contains(userId))
                {
                    throw new Exception($"User {userId} is already a collaborator of database {databaseId}");
                }

                collaborators.Add(userId);
                database.CollaboratorsJson = JsonSerializer.Serialize(collaborators);
                
                await _context.SaveChangesAsync();
                
                _logger.LogInformation($"User {userId} joined database {databaseId}");
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, $"Error joining database {databaseId} for user {userId}");
                throw;
            }
        }

        public async Task LeaveDatabaseAsync(string databaseId, string userId)
        {
            try
            {
                var database = await _context.SharedDatabases
                    .FirstOrDefaultAsync(db => db.Id == databaseId);

                if (database == null)
                {
                    throw new Exception($"Database {databaseId} not found");
                }

                if (database.OwnerId == userId)
                {
                    throw new Exception($"Owner cannot leave the database. Please transfer ownership first.");
                }

                var collaborators = JsonSerializer.Deserialize<List<string>>(database.CollaboratorsJson) ?? new List<string>();
                
                if (!collaborators.Contains(userId))
                {
                    throw new Exception($"User {userId} is not a collaborator of database {databaseId}");
                }

                collaborators.Remove(userId);
                database.CollaboratorsJson = JsonSerializer.Serialize(collaborators);
                
                await _context.SaveChangesAsync();
                
                _logger.LogInformation($"User {userId} left database {databaseId}");
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, $"Error leaving database {databaseId} for user {userId}");
                throw;
            }
        }

        public async Task SaveDatabaseBackupAsync(string databaseId, string userId, BackupData backupData)
        {
            try
            {
                var database = await GetDatabaseAsync(databaseId, userId);
                if (database == null)
                {
                    throw new Exception($"Database {databaseId} not found or user {userId} does not have access");
                }

                var dbFilePath = database.DatabasePath;
                var db = new SQLiteAsyncConnection(dbFilePath);
                
                // Очищаем существующие данные
                await db.DeleteAllAsync<Note>();
                await db.DeleteAllAsync<Folder>();
                await db.DeleteAllAsync<ScheduleEntry>();
                await db.DeleteAllAsync<PinboardNote>();
                await db.DeleteAllAsync<Connection>();
                await db.DeleteAllAsync<NoteImage>();
                
                // Вставляем новые данные
                await db.InsertAllAsync(backupData.Notes);
                await db.InsertAllAsync(backupData.Folders);
                await db.InsertAllAsync(backupData.ScheduleEntries);
                await db.InsertAllAsync(backupData.PinboardNotes);
                await db.InsertAllAsync(backupData.Connections);
                await db.InsertAllAsync(backupData.NoteImages);
                
                await db.CloseAsync();
                
                _logger.LogInformation($"Saved database backup for {databaseId} for user {userId}");
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, $"Error saving database backup for {databaseId} for user {userId}");
                throw;
            }
        }

        public async Task<BackupData> GetDatabaseBackupAsync(string databaseId, string userId)
        {
            try
            {
                var database = await GetDatabaseAsync(databaseId, userId);
                if (database == null)
                {
                    throw new Exception($"Database {databaseId} not found or user {userId} does not have access");
                }

                var dbFilePath = database.DatabasePath;
                
                // Создаем и инициализируем базу данных, если она не существует
                using (var connection = new SQLiteConnection(dbFilePath))
                {
                    // Создаем таблицы, если их нет
                    connection.CreateTable<Note>();
                    connection.CreateTable<Folder>();
                    connection.CreateTable<ScheduleEntry>();
                    connection.CreateTable<PinboardNote>();
                    connection.CreateTable<Connection>();
                    connection.CreateTable<NoteImage>();
                }
                
                var db = new SQLiteAsyncConnection(dbFilePath);
                
                var notes = await db.Table<Note>().ToListAsync();
                var folders = await db.Table<Folder>().ToListAsync();
                var scheduleEntries = await db.Table<ScheduleEntry>().ToListAsync();
                var pinboardNotes = await db.Table<PinboardNote>().ToListAsync();
                var connections = await db.Table<Connection>().ToListAsync();
                var noteImages = await db.Table<NoteImage>().ToListAsync();
                
                await db.CloseAsync();

                var backupData = new BackupData
                {
                    Notes = notes,
                    Folders = folders,
                    ScheduleEntries = scheduleEntries,
                    PinboardNotes = pinboardNotes,
                    Connections = connections,
                    NoteImages = noteImages
                };

                return backupData;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, $"Error getting database backup for {databaseId} for user {userId}");
                throw;
            }
        }

        public async Task<SharedDatabase?> GetDatabaseAsync(string databaseId, string userId)
        {
            try
            {
                var database = await _context.SharedDatabases
                    .FirstOrDefaultAsync(db => db.Id == databaseId);

                if (database == null)
                {
                    return null;
                }

                // Проверяем, является ли пользователь владельцем или коллаборатором
                var collaborators = JsonSerializer.Deserialize<List<string>>(database.CollaboratorsJson) ?? new List<string>();
                if (database.OwnerId == userId || collaborators.Contains(userId))
                {
                    return database;
                }

                return null;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, $"Error getting database {databaseId} for user {userId}");
                throw;
            }
        }

        public async Task ReplaceLocalDatabaseAsync(string databaseId, string userId, BackupData backupData)
        {
            try
            {
                var database = await GetDatabaseAsync(databaseId, userId);
                if (database == null)
                {
                    throw new Exception($"Database {databaseId} not found or user {userId} does not have access");
                }

                var dbFilePath = database.DatabasePath;
                
                // Удаляем существующую базу данных
                if (File.Exists(dbFilePath))
                {
                    File.Delete(dbFilePath);
                }
                
                // Создаем и инициализируем базу данных
                using (var connection = new SQLiteConnection(dbFilePath))
                {
                    // Создаем таблицы
                    connection.CreateTable<Note>();
                    connection.CreateTable<Folder>();
                    connection.CreateTable<ScheduleEntry>();
                    connection.CreateTable<PinboardNote>();
                    connection.CreateTable<Connection>();
                    connection.CreateTable<NoteImage>();
                }
                
                // Вставляем данные
                var db = new SQLiteAsyncConnection(dbFilePath);
                
                await db.InsertAllAsync(backupData.Notes);
                await db.InsertAllAsync(backupData.Folders);
                await db.InsertAllAsync(backupData.ScheduleEntries);
                await db.InsertAllAsync(backupData.PinboardNotes);
                await db.InsertAllAsync(backupData.Connections);
                await db.InsertAllAsync(backupData.NoteImages);
                
                await db.CloseAsync();
                
                _logger.LogInformation($"Replaced local database {databaseId} for user {userId}");
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, $"Error replacing local database {databaseId} for user {userId}");
                throw;
            }
        }

        public async Task<Note?> GetNoteAsync(string databaseId, string noteId)
        {
            try
            {
                var database = await GetDatabaseAsync(databaseId, string.Empty);
                if (database == null)
                {
                    throw new Exception($"Database {databaseId} not found");
                }

                var dbFilePath = database.DatabasePath;
                var db = new SQLiteAsyncConnection(dbFilePath);
                
                var note = await db.Table<Note>().FirstOrDefaultAsync(n => n.Id.ToString() == noteId);
                
                await db.CloseAsync();
                
                return note;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, $"Error getting note {noteId} from database {databaseId}");
                throw;
            }
        }

        public async Task SaveNoteAsync(string databaseId, Note note)
        {
            try
            {
                var database = await GetDatabaseAsync(databaseId, string.Empty);
                if (database == null)
                {
                    throw new Exception($"Database {databaseId} not found");
                }

                var dbFilePath = database.DatabasePath;
                var db = new SQLiteAsyncConnection(dbFilePath);
                
                await db.InsertOrReplaceAsync(note);
                
                await db.CloseAsync();
                
                _logger.LogInformation($"Saved note {note.Id} to database {databaseId}");
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, $"Error saving note {note.Id} to database {databaseId}");
                throw;
            }
        }

        public async Task DeleteNoteAsync(string databaseId, string noteId)
        {
            try
            {
                var database = await GetDatabaseAsync(databaseId, string.Empty);
                if (database == null)
                {
                    throw new Exception($"Database {databaseId} not found");
                }

                var dbFilePath = database.DatabasePath;
                var db = new SQLiteAsyncConnection(dbFilePath);
                
                await db.DeleteAsync<Note>(noteId);
                
                await db.CloseAsync();
                
                _logger.LogInformation($"Deleted note {noteId} from database {databaseId}");
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, $"Error deleting note {noteId} from database {databaseId}");
                throw;
            }
        }

        public async Task TransferOwnershipAsync(string databaseId, string currentOwnerId, string newOwnerId)
        {
            try
            {
                var database = await _context.SharedDatabases
                    .FirstOrDefaultAsync(db => db.Id == databaseId);

                if (database == null)
                {
                    throw new Exception($"Database {databaseId} not found");
                }

                if (database.OwnerId != currentOwnerId)
                {
                    throw new Exception($"User {currentOwnerId} is not the owner of database {databaseId}");
                }

                var collaborators = JsonSerializer.Deserialize<List<string>>(database.CollaboratorsJson) ?? new List<string>();
                
                if (!collaborators.Contains(newOwnerId))
                {
                    throw new Exception($"User {newOwnerId} is not a collaborator of database {databaseId}");
                }

                database.OwnerId = newOwnerId;
                collaborators.Remove(newOwnerId);
                collaborators.Add(currentOwnerId);
                database.CollaboratorsJson = JsonSerializer.Serialize(collaborators);
                
                await _context.SaveChangesAsync();
                
                _logger.LogInformation($"Ownership of database {databaseId} transferred from {currentOwnerId} to {newOwnerId}");
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, $"Error transferring ownership of database {databaseId} from {currentOwnerId} to {newOwnerId}");
                throw;
            }
        }
    }
} 