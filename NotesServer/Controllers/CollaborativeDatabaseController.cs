using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using NotesServer.Data;
using NotesServer.Models;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Authorization;
using System.Security.Claims;

namespace NotesServer.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    [Authorize]
    public class CollaborativeDatabaseController : ControllerBase
    {
        private readonly ApplicationDbContext _context;

        public CollaborativeDatabaseController(ApplicationDbContext context)
        {
            _context = context;
        }

        [HttpGet("databases")]
        public async Task<ActionResult<IEnumerable<CollaborativeDatabase>>> GetDatabases()
        {
            var userId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value 
                      ?? User.FindFirst("sub")?.Value 
                      ?? User.FindFirst("nameid")?.Value;
            Console.WriteLine($"userId: {userId}");
            if (string.IsNullOrEmpty(userId))
                return Unauthorized();

            var databases = await _context.CollaborativeDatabases
                .Include(d => d.Collaborators)
                .Where(d => d.OwnerId == userId || d.Collaborators.Any(c => c.UserId == userId))
                .ToListAsync();

            // Возвращаем lastModified = LastSync для совместимости с клиентом
            var result = databases.Select(db => new {
                id = db.Id,
                name = db.Name,
                ownerId = db.OwnerId,
                createdAt = db.CreatedAt,
                lastModified = db.LastSync, // для совместимости
                collaborators = db.Collaborators.ToDictionary(c => c.UserId, c => c.Role),
                version = db.Version.ToString(),
                isActive = true,
                lastSyncTime = db.LastSync,
                lastSync = db.LastSync
            });

            return Ok(result);
        }

        [HttpPost("databases")]
        public async Task<ActionResult<CollaborativeDatabase>> CreateDatabase([FromBody] CreateCollaborativeDatabaseRequest request)
        {
            var userId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value 
                      ?? User.FindFirst("sub")?.Value 
                      ?? User.FindFirst("nameid")?.Value;
            Console.WriteLine($"userId: {userId}");
            if (string.IsNullOrEmpty(userId))
                return Unauthorized();

            var database = new CollaborativeDatabase
            {
                Name = request.Name,
                OwnerId = userId,
                CreatedAt = DateTime.UtcNow,
                LastSync = DateTime.UtcNow,
                Version = 1
            };

            _context.CollaborativeDatabases.Add(database);
            await _context.SaveChangesAsync();

            return CreatedAtAction(nameof(GetDatabase), new { id = database.Id }, database);
        }

        [HttpGet("databases/{id}")]
        public async Task<ActionResult<CollaborativeDatabase>> GetDatabase(string id)
        {
            var userId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value 
                      ?? User.FindFirst("sub")?.Value 
                      ?? User.FindFirst("nameid")?.Value;
            Console.WriteLine($"userId: {userId}");
            if (string.IsNullOrEmpty(userId))
                return Unauthorized();

            var db = await _context.CollaborativeDatabases
                .Include(d => d.Collaborators)
                .FirstOrDefaultAsync(d => d.Id == id);

            if (db == null)
                return NotFound();

            if (db.OwnerId != userId && !db.Collaborators.Any(c => c.UserId == userId))
                return Forbid();

            var result = new {
                id = db.Id,
                name = db.Name,
                ownerId = db.OwnerId,
                createdAt = db.CreatedAt,
                lastModified = db.LastSync, // для совместимости
                collaborators = db.Collaborators.ToDictionary(c => c.UserId, c => c.Role),
                version = db.Version.ToString(),
                isActive = true,
                lastSyncTime = db.LastSync,
                lastSync = db.LastSync
            };

            return Ok(result);
        }

        [HttpDelete("databases/{id}")]
        public async Task<IActionResult> DeleteDatabase(string id)
        {
            var userId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value 
                      ?? User.FindFirst("sub")?.Value 
                      ?? User.FindFirst("nameid")?.Value;
            Console.WriteLine($"userId: {userId}");
            if (string.IsNullOrEmpty(userId))
                return Unauthorized();

            var database = await _context.CollaborativeDatabases.FindAsync(id);
            if (database == null)
                return NotFound();

            if (database.OwnerId != userId)
                return Forbid();

            _context.CollaborativeDatabases.Remove(database);
            await _context.SaveChangesAsync();

            return NoContent();
        }

        [HttpPost("databases/{id}/leave")]
        public async Task<IActionResult> LeaveDatabase(string id)
        {
            var userId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value 
                      ?? User.FindFirst("sub")?.Value 
                      ?? User.FindFirst("nameid")?.Value;
            Console.WriteLine($"userId: {userId}");
            if (string.IsNullOrEmpty(userId))
                return Unauthorized();

            var collaborator = await _context.DatabaseCollaborators
                .FirstOrDefaultAsync(c => c.DatabaseId == id && c.UserId == userId);

            if (collaborator == null)
                return NotFound();

            _context.DatabaseCollaborators.Remove(collaborator);
            await _context.SaveChangesAsync();

            return NoContent();
        }

        [HttpPost("databases/{id}/collaborators")]
        public async Task<IActionResult> AddCollaborator(string id, [FromBody] AddCollaboratorRequest request)
        {
            var userId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value 
                      ?? User.FindFirst("sub")?.Value 
                      ?? User.FindFirst("nameid")?.Value;
            Console.WriteLine($"userId: {userId}");
            if (string.IsNullOrEmpty(userId))
                return Unauthorized();

            var database = await _context.CollaborativeDatabases.FindAsync(id);
            if (database == null)
                return NotFound();

            if (database.OwnerId != userId)
                return Forbid();

            var collaborator = new DatabaseCollaborator
            {
                DatabaseId = id,
                UserId = request.UserId,
                Role = "collaborator"
            };

            _context.DatabaseCollaborators.Add(collaborator);
            await _context.SaveChangesAsync();

            return Ok();
        }

        [HttpDelete("databases/{id}/collaborators/{userId}")]
        public async Task<IActionResult> RemoveCollaborator(string id, string userId)
        {
            var currentUserId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value 
                              ?? User.FindFirst("sub")?.Value 
                              ?? User.FindFirst("nameid")?.Value;
            Console.WriteLine($"userId: {currentUserId}");
            if (string.IsNullOrEmpty(currentUserId))
                return Unauthorized();

            var database = await _context.CollaborativeDatabases.FindAsync(id);
            if (database == null)
                return NotFound();

            if (database.OwnerId != currentUserId)
                return Forbid();

            var collaborator = await _context.DatabaseCollaborators
                .FirstOrDefaultAsync(c => c.DatabaseId == id && c.UserId == userId);

            if (collaborator == null)
                return NotFound();

            _context.DatabaseCollaborators.Remove(collaborator);
            await _context.SaveChangesAsync();

            return NoContent();
        }

        [HttpPost("databases/{id}/sync")]
        public async Task<IActionResult> SyncDatabase(string id, [FromBody] dynamic requestData)
        {
            var userId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value 
                      ?? User.FindFirst("sub")?.Value 
                      ?? User.FindFirst("nameid")?.Value;
            Console.WriteLine($"userId: {userId}");
            if (string.IsNullOrEmpty(userId))
                return Unauthorized();

            var database = await _context.CollaborativeDatabases
                .Include(d => d.Collaborators)
                .FirstOrDefaultAsync(d => d.Id == id);

            if (database == null)
                return NotFound();

            if (database.OwnerId != userId && !database.Collaborators.Any(c => c.UserId == userId))
                return Forbid();

            try
            {
                // Обновляем версию и время последней синхронизации
                database.Version++;
                database.LastSync = DateTime.UtcNow;
                await _context.SaveChangesAsync();

                // Возвращаем те же данные, которые получили от клиента,
                // чтобы клиент мог их восстановить
                return Ok(requestData);
            }
            catch (Exception ex)
            {
                return BadRequest(new { message = $"Неизвестная ошибка сервера", error = ex.Message });
            }
        }

        [HttpPost("databases/import")]
        public async Task<ActionResult<CollaborativeDatabase>> ImportDatabase([FromBody] ImportDatabaseRequest request)
        {
            var userId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value 
                      ?? User.FindFirst("sub")?.Value 
                      ?? User.FindFirst("nameid")?.Value;
            Console.WriteLine($"userId: {userId}");
            if (string.IsNullOrEmpty(userId))
                return Unauthorized();

            var database = await _context.CollaborativeDatabases
                .Include(d => d.Collaborators)
                .FirstOrDefaultAsync(d => d.Id == request.DatabaseId);

            if (database == null)
                return NotFound();

            if (database.OwnerId != userId && !database.Collaborators.Any(c => c.UserId == userId))
                return Forbid();

            return Ok(database);
        }

        [HttpGet("databases/{id}/export")]
        public async Task<IActionResult> ExportDatabase(string id)
        {
            var userId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value 
                      ?? User.FindFirst("sub")?.Value 
                      ?? User.FindFirst("nameid")?.Value;
            Console.WriteLine($"userId: {userId}");
            if (string.IsNullOrEmpty(userId))
                return Unauthorized();

            var database = await _context.CollaborativeDatabases
                .Include(d => d.Collaborators)
                .FirstOrDefaultAsync(d => d.Id == id);

            if (database == null)
                return NotFound();

            if (database.OwnerId != userId && !database.Collaborators.Any(c => c.UserId == userId))
                return Forbid();

            // Здесь должна быть логика экспорта данных базы
            var exportData = new
            {
                database.Id,
                database.Name,
                database.OwnerId,
                database.CreatedAt,
                database.LastSync,
                database.Version,
                Collaborators = database.Collaborators.Select(c => new { c.UserId, c.Role })
            };

            return Ok(exportData);
        }
    }

    public class CreateCollaborativeDatabaseRequest
    {
        public string Name { get; set; }
    }

    public class AddCollaboratorRequest
    {
        public string UserId { get; set; }
    }

    public class ImportDatabaseRequest
    {
        public string DatabaseId { get; set; }
    }

    public class SyncRequest
    {
        public int Version { get; set; }
        public Dictionary<string, object> Changes { get; set; }
    }
} 