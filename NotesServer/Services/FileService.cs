using System;
using System.IO;
using System.Threading.Tasks;
using Microsoft.Extensions.Logging;
using NotesServer.Models;
using SQLite;

namespace NotesServer.Services
{
    public interface IFileService
    {
        Task<string> SaveDatabaseFileAsync(string databaseId);
        Task DeleteDatabaseFileAsync(string databasePath);
    }

    public class FileService : IFileService
    {
        private readonly ILogger<FileService> _logger;
        private readonly string _databasesPath;

        public FileService(ILogger<FileService> logger, IWebHostEnvironment environment)
        {
            _logger = logger;
            _databasesPath = Path.Combine(environment.ContentRootPath, "Databases");
            Directory.CreateDirectory(_databasesPath);
        }

        public async Task<string> SaveDatabaseFileAsync(string databaseId)
        {
            var databasePath = Path.Combine(_databasesPath, $"{databaseId}.db");
            
            // Создаем пустой файл базы данных
            await Task.Run(() =>
            {
                using (var connection = new SQLiteConnection(databasePath))
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
            });

            return databasePath;
        }

        public async Task DeleteDatabaseFileAsync(string databasePath)
        {
            if (File.Exists(databasePath))
            {
                try
                {
                    await Task.Run(() => File.Delete(databasePath));
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "Error deleting database file: {Path}", databasePath);
                    throw;
                }
            }
        }
    }
} 