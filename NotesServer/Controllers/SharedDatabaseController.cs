using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using NotesServer.Models;
using NotesServer.Data;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Authorization;
using System.Security.Claims;
using System.IO;
using SQLite;

namespace NotesServer.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    [Authorize]
    public class SharedDatabaseController : ControllerBase
    {
        private readonly ApplicationDbContext _context;
        private readonly IWebHostEnvironment _environment;
        private readonly ILogger<SharedDatabaseController> _logger;

        public SharedDatabaseController(ApplicationDbContext context, IWebHostEnvironment environment, ILogger<SharedDatabaseController> logger)
        {
            _context = context;
            _environment = environment;
            _logger = logger;
        }

        [HttpGet]
        public async Task<ActionResult<IEnumerable<SharedDatabase>>> GetUserDatabases()
        {
            var userId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            if (userId == null) return Unauthorized();

            var databases = await _context.SharedDatabases
                .Where(db => db.OwnerId == userId)
                .ToListAsync();

            var sharedDatabases = await _context.SharedDatabases
                .Where(db => db.OwnerId != userId)
                .ToListAsync();

            databases.AddRange(sharedDatabases.Where(db => db.Collaborators.Contains(userId)));

            return Ok(databases);
        }

        [HttpPost]
        public async Task<ActionResult<SharedDatabase>> CreateDatabase([FromBody] CreateDatabaseRequest request)
        {
            var userId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            if (userId == null)
            {
                Console.WriteLine("Unauthorized: User ID not found in token");
                return Unauthorized();
            }

            Console.WriteLine($"Creating database for user {userId} with name {request.Name}");

            // Создаем физический файл базы данных
            var databaseId = Guid.NewGuid().ToString();
            var databaseFileName = $"{databaseId}.db";
            var databasePath = Path.Combine(_environment.ContentRootPath, "Databases", databaseFileName);
            
            // Создаем директорию для баз данных, если она не существует
            System.IO.Directory.CreateDirectory(Path.GetDirectoryName(databasePath)!);
            
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

            var database = new SharedDatabase
            {
                Id = databaseId,
                Name = request.Name,
                OwnerId = userId,
                CreatedAt = DateTime.UtcNow,
                Collaborators = new List<string> { userId },
                DatabasePath = databasePath
            };

            _context.SharedDatabases.Add(database);
            await _context.SaveChangesAsync();

            Console.WriteLine($"Database created successfully with ID {database.Id}");
            return CreatedAtAction(nameof(GetDatabase), new { id = database.Id }, database);
        }

        [HttpGet("{id}")]
        public async Task<ActionResult<SharedDatabase>> GetDatabase(string id)
        {
            var userId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            if (userId == null) return Unauthorized();

            var database = await _context.SharedDatabases
                .FirstOrDefaultAsync(db => db.Id == id && 
                    (db.OwnerId == userId || db.Collaborators.Contains(userId)));

            if (database == null) return NotFound();

            return Ok(database);
        }

        [HttpPost("{id}/import")]
        public async Task<ActionResult> ImportDatabase(string id)
        {
            var userId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            if (userId == null) return Unauthorized();

            var database = await _context.SharedDatabases
                .FirstOrDefaultAsync(db => db.Id == id);

            if (database == null) return NotFound();

            try
            {
                if (database.Collaborators.Contains(userId))
                {
                    return Ok(database);
                }

                // Проверяем существование физического файла базы
                if (!System.IO.File.Exists(database.DatabasePath))
                {
                    return NotFound("Физический файл базы данных не найден");
                }

                // Добавляем пользователя в список коллабораторов
                database.Collaborators.Add(userId);
                await _context.SaveChangesAsync();

                return Ok(database);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, $"Ошибка при импорте базы данных {id} для пользователя {userId}");
                return StatusCode(500, $"Ошибка при импорте базы данных: {ex.Message}");
            }
        }

        [HttpDelete("{id}")]
        public async Task<ActionResult> DeleteDatabase(string id)
        {
            var userId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            if (userId == null) return Unauthorized();

            var database = await _context.SharedDatabases
                .FirstOrDefaultAsync(db => db.Id == id && db.OwnerId == userId);

            if (database == null) return NotFound();

            _context.SharedDatabases.Remove(database);
            await _context.SaveChangesAsync();

            return NoContent();
        }

        [HttpPost("{id}/leave")]
        public async Task<ActionResult> LeaveDatabase(string id)
        {
            var userId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            if (userId == null) return Unauthorized();

            var database = await _context.SharedDatabases
                .FirstOrDefaultAsync(db => db.Id == id && db.Collaborators.Contains(userId));

            if (database == null) return NotFound();

            database.Collaborators.Remove(userId);
            await _context.SaveChangesAsync();

            return NoContent();
        }
    }

    public class CreateDatabaseRequest
    {
        public required string Name { get; set; }
    }
} 