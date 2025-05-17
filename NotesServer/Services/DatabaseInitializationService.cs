using SQLite;
using System;
using System.IO;
using NotesServer.Models;
using Microsoft.Extensions.Logging;

namespace NotesServer.Services
{
    public class DatabaseInitializationService
    {
        private readonly ILogger<DatabaseInitializationService> _logger;

        public DatabaseInitializationService(ILogger<DatabaseInitializationService> logger)
        {
            _logger = logger;
        }

        public void InitializeDatabase(string databasePath)
        {
            try
            {
                _logger.LogInformation($"Initializing database at {databasePath}");

                // Создаем директорию для базы данных, если она не существует
                var directory = Path.GetDirectoryName(databasePath);
                if (!string.IsNullOrEmpty(directory))
                {
                    Directory.CreateDirectory(directory);
                }

                // Создаем и инициализируем базу данных
                using var db = new SQLiteConnection(databasePath);
                
                _logger.LogInformation("Creating tables...");

                // Создаем таблицы
                _logger.LogInformation("Создаю таблицу для типа: " + typeof(Note).FullName);
                db.CreateTable<Note>();
                _logger.LogInformation("Создаю таблицу для типа: " + typeof(Folder).FullName);
                db.CreateTable<Folder>();
                _logger.LogInformation("Создаю таблицу для типа: " + typeof(ScheduleEntry).FullName);
                db.CreateTable<ScheduleEntry>();
                _logger.LogInformation("Создаю таблицу для типа: " + typeof(PinboardNote).FullName);
                db.CreateTable<PinboardNote>();
                _logger.LogInformation("Создаю таблицу для типа: " + typeof(Connection).FullName);
                db.CreateTable<Connection>();
                _logger.LogInformation("Создаю таблицу для типа: " + typeof(NoteImage).FullName);
                db.CreateTable<NoteImage>();

                _logger.LogInformation("Database initialized successfully");
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error initializing database");
                throw new Exception("Failed to initialize database", ex);
            }
        }
    }
} 