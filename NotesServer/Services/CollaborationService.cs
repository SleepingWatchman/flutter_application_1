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
        Task DeleteDatabaseAsync(string databaseId, string userId);
        Task SaveDatabaseBackupAsync(string databaseId, string userId, BackupData backupData);
        Task<BackupData> GetDatabaseBackupAsync(string databaseId, string userId);
        Task<CollaborationDatabase?> GetDatabaseAsync(string databaseId, string userId);
        Task ReplaceLocalDatabaseAsync(string databaseId, string userId, BackupData backupData);
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
                var databasePath = Path.Combine(_environment.ContentRootPath, "Data", "Databases", userId, databaseFileName);
                
                // Создаем директорию для баз данных пользователя, если она не существует
                Directory.CreateDirectory(Path.GetDirectoryName(databasePath)!);
                
                var database = new CollaborationDatabase
                {
                    Id = Guid.NewGuid().ToString(),
                    UserId = userId,
                    CreatedAt = DateTime.UtcNow,
                    DatabaseName = $"collab_db_{Path.GetFileNameWithoutExtension(databaseFileName)}",
                    ConnectionString = databasePath
                };

                _context.CollaborationDatabases.Add(database);
                await _context.SaveChangesAsync();

                // Создаем новую базу данных SQLite
                using (var db = new SQLiteConnection(databasePath))
                {
                    // Инициализация таблиц
                    db.CreateTable<Note>();
                    db.CreateTable<Folder>();
                    db.CreateTable<ScheduleEntry>();
                    db.CreateTable<PinboardNote>();
                    db.CreateTable<Connection>();
                    db.CreateTable<NoteImage>();
                }

                _logger.LogInformation("Создана новая база данных {DatabasePath} для пользователя {UserId}", databasePath, userId);
                return database;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Ошибка при создании базы данных для пользователя {UserId}", userId);
                throw;
            }
        }

        public async Task<List<CollaborationDatabase>> GetUserDatabasesAsync(string userId)
        {
            return await _context.CollaborationDatabases
                .Where(db => db.UserId == userId)
                .ToListAsync();
        }

        public async Task DeleteDatabaseAsync(string databaseId, string userId)
        {
            var database = await GetDatabaseAsync(databaseId, userId);
            if (database == null) return;

            // Удаляем файл базы данных
            if (File.Exists(database.ConnectionString))
            {
                File.Delete(database.ConnectionString);
            }

            _context.CollaborationDatabases.Remove(database);
            await _context.SaveChangesAsync();
        }

        public async Task SaveDatabaseBackupAsync(string databaseId, string userId, BackupData backupData)
        {
            var database = await GetDatabaseAsync(databaseId, userId);
            if (database == null) throw new Exception("База данных не найдена");

            var backupPath = Path.Combine(_environment.ContentRootPath, BackupDirectoryName, $"{databaseId}_{DateTime.UtcNow:yyyyMMddHHmmss}.json");
            Directory.CreateDirectory(Path.GetDirectoryName(backupPath)!);

            var json = System.Text.Json.JsonSerializer.Serialize(backupData);
            await File.WriteAllTextAsync(backupPath, json);

            _logger.LogInformation("Сохранена резервная копия базы данных {DatabaseId} для пользователя {UserId}", databaseId, userId);
        }

        public async Task<BackupData> GetDatabaseBackupAsync(string databaseId, string userId)
        {
            var database = await GetDatabaseAsync(databaseId, userId);
            if (database == null) throw new Exception("База данных не найдена");

            var backupFiles = Directory.GetFiles(
                Path.Combine(_environment.ContentRootPath, BackupDirectoryName),
                $"{databaseId}_*.json"
            ).OrderByDescending(f => f).ToList();

            if (!backupFiles.Any()) throw new Exception("Резервная копия не найдена");

            var json = await File.ReadAllTextAsync(backupFiles.First());
            return System.Text.Json.JsonSerializer.Deserialize<BackupData>(json) ?? throw new Exception("Не удалось десериализовать резервную копию");
        }

        public async Task<CollaborationDatabase?> GetDatabaseAsync(string databaseId, string userId)
        {
            return await _context.CollaborationDatabases
                .FirstOrDefaultAsync(db => db.Id == databaseId && db.UserId == userId);
        }

        public async Task ReplaceLocalDatabaseAsync(string databaseId, string userId, BackupData backupData)
        {
            var database = await GetDatabaseAsync(databaseId, userId);
            if (database == null) throw new Exception("База данных не найдена");

            // Удаляем старую базу данных
            if (File.Exists(database.ConnectionString))
            {
                File.Delete(database.ConnectionString);
            }

            // Создаем новую базу данных
            using (var db = new SQLiteConnection(database.ConnectionString))
            {
                // Инициализация таблиц
                db.CreateTable<Note>();
                db.CreateTable<Folder>();
                db.CreateTable<ScheduleEntry>();
                db.CreateTable<PinboardNote>();
                db.CreateTable<Connection>();
                db.CreateTable<NoteImage>();

                // Восстанавливаем данные
                db.InsertAll(backupData.Notes);
                db.InsertAll(backupData.Folders);
                db.InsertAll(backupData.ScheduleEntries);
                db.InsertAll(backupData.PinboardNotes);
                db.InsertAll(backupData.Connections);
                db.InsertAll(backupData.NoteImages);
            }
        }
    }
} 