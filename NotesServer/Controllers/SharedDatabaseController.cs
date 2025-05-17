using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using NotesServer.Models;
using NotesServer.Services;
using NotesServer.Data;
using AuthServer.Services;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Authorization;
using System.Security.Claims;
using System.IO;
using SQLite;
using System.Text.Json;

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
        private readonly DatabaseInitializationService _databaseInitService;
        private readonly IUserService _userService;
        private readonly IFileService _fileService;

        public SharedDatabaseController(
            ApplicationDbContext context, 
            IWebHostEnvironment environment, 
            ILogger<SharedDatabaseController> logger,
            DatabaseInitializationService databaseInitService,
            IUserService userService,
            IFileService fileService)
        {
            _context = context;
            _environment = environment;
            _logger = logger;
            _databaseInitService = databaseInitService;
            _userService = userService;
            _fileService = fileService;
        }

        [HttpGet]
        public async Task<ActionResult<IEnumerable<SharedDatabase>>> GetSharedDatabases()
        {
            try
            {
                var userId = _userService.GetUserId(User);
                if (string.IsNullOrEmpty(userId))
                {
                    _logger.LogWarning("Попытка доступа без авторизации");
                    return Unauthorized("Требуется авторизация");
                }

                _logger.LogInformation($"Получение списка баз данных для пользователя {userId}");

                var databases = await _context.SharedDatabases
                    .Where(db => db.OwnerId == userId || db.CollaboratorsJson.Contains($"\"{userId}\""))
                    .ToListAsync();

                _logger.LogInformation($"Найдено {databases.Count} баз данных");
                return Ok(databases);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Ошибка при получении списка баз данных");
                return StatusCode(500, "Внутренняя ошибка сервера при получении списка баз данных");
            }
        }

        [HttpGet("{id}")]
        public async Task<ActionResult<SharedDatabase>> GetSharedDatabase(string id)
        {
            var userId = _userService.GetUserId(User);
            var database = await _context.SharedDatabases.FindAsync(id);

            if (database == null)
            {
                return NotFound();
            }

            if (database.OwnerId != userId && !database.CollaboratorsJson.Contains($"\"{userId}\""))
            {
                return Forbid();
            }

            return database;
        }

        [HttpPost]
        public async Task<ActionResult<SharedDatabase>> CreateSharedDatabase([FromBody] CreateSharedDatabaseRequest request)
        {
            var userId = _userService.GetUserId(User);
            
            var database = new SharedDatabase
            {
                Id = Guid.NewGuid().ToString(),
                Name = request.Name,
                OwnerId = userId,
                CreatedAt = DateTime.UtcNow,
                Collaborators = new List<string> { userId },
                DatabasePath = await _fileService.SaveDatabaseFileAsync(Guid.NewGuid().ToString())
            };

            _context.SharedDatabases.Add(database);
            await _context.SaveChangesAsync();

            return CreatedAtAction(nameof(GetSharedDatabase), new { id = database.Id }, database);
        }

        [HttpPut("{id}")]
        public async Task<IActionResult> UpdateSharedDatabase(string id, SharedDatabase database)
        {
            if (id != database.Id)
            {
                return BadRequest();
            }

            var userId = _userService.GetUserId(User);
            var existingDatabase = await _context.SharedDatabases.FindAsync(id);

            if (existingDatabase == null)
            {
                return NotFound();
            }

            if (existingDatabase.OwnerId != userId)
            {
                return Forbid();
            }

            existingDatabase.Name = database.Name;
            existingDatabase.Collaborators = database.Collaborators ?? new List<string>();

            try
            {
                await _context.SaveChangesAsync();
            }
            catch (DbUpdateConcurrencyException)
            {
                if (!SharedDatabaseExists(id))
                {
                    return NotFound();
                }
                else
                {
                    throw;
                }
            }

            return NoContent();
        }

        [HttpDelete("{id}")]
        public async Task<IActionResult> DeleteSharedDatabase(string id)
        {
            var userId = _userService.GetUserId(User);
            var database = await _context.SharedDatabases.FindAsync(id);
            
            if (database == null)
            {
                return NotFound();
            }

            if (database.OwnerId != userId)
            {
                return Forbid();
            }

            _context.SharedDatabases.Remove(database);
            await _context.SaveChangesAsync();

            await _fileService.DeleteDatabaseFileAsync(database.DatabasePath);

            return NoContent();
        }

        private bool SharedDatabaseExists(string id)
        {
            return _context.SharedDatabases.Any(e => e.Id == id);
        }

        [HttpPost("{id}/collaborators")]
        public async Task<IActionResult> AddCollaborator(string id, [FromBody] string collaboratorId)
        {
            var userId = _userService.GetUserId(User);
            var database = await _context.SharedDatabases.FindAsync(id);

            if (database == null)
            {
                return NotFound();
            }

            if (database.OwnerId != userId)
            {
                return Forbid();
            }

            var collaborators = database.Collaborators;
            if (!collaborators.Contains(collaboratorId))
            {
                collaborators.Add(collaboratorId);
                database.Collaborators = collaborators;
                await _context.SaveChangesAsync();
            }

            return NoContent();
        }

        [HttpDelete("{id}/collaborators/{collaboratorId}")]
        public async Task<IActionResult> RemoveCollaborator(string id, string collaboratorId)
        {
            var userId = _userService.GetUserId(User);
            var database = await _context.SharedDatabases.FindAsync(id);

            if (database == null)
            {
                return NotFound();
            }

            if (database.OwnerId != userId)
            {
                return Forbid();
            }

            var collaborators = database.Collaborators;
            if (collaborators.Contains(collaboratorId))
            {
                collaborators.Remove(collaboratorId);
                database.Collaborators = collaborators;
                await _context.SaveChangesAsync();
            }

            return NoContent();
        }

        [HttpPost("{id}/import")]
        public async Task<IActionResult> ImportDatabase(string id)
        {
            var userId = _userService.GetUserId(User);
            var database = await _context.SharedDatabases.FindAsync(id);

            if (database == null)
            {
                return NotFound();
            }

            if (database.OwnerId == userId)
            {
                return BadRequest("Вы уже являетесь владельцем этой базы данных");
            }

            if (database.CollaboratorsJson.Contains($"\"{userId}\""))
            {
                return BadRequest("Вы уже имеете доступ к этой базе данных");
            }

            try
            {
                var collaborators = database.Collaborators;
                collaborators.Add(userId);
                database.Collaborators = collaborators;
                await _context.SaveChangesAsync();

                return Ok(database);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, $"Ошибка при импорте базы данных {id}");
                return StatusCode(500, "Ошибка при импорте базы данных");
            }
        }
    }

    public class CreateSharedDatabaseRequest
    {
        public required string Name { get; set; }
    }
} 