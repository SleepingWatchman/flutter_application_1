using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Logging;
using NotesServer.Data;
using NotesServer.Models;
using NotesServer.Services;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Security.Claims;
using System.Threading.Tasks;

namespace NotesServer.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    [Authorize]
    public class CollaborationController : ControllerBase
    {
        private readonly ICollaborationService _collaborationService;
        private readonly ILogger<CollaborationController> _logger;

        public CollaborationController(
            ICollaborationService collaborationService,
            ILogger<CollaborationController> logger)
        {
            _collaborationService = collaborationService;
            _logger = logger;
        }

        [HttpGet("databases")]
        public async Task<IActionResult> GetDatabases()
        {
            try
            {
                var userId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
                if (string.IsNullOrEmpty(userId))
                {
                    return Unauthorized("User not authenticated");
                }

                var databases = await _collaborationService.GetUserDatabasesAsync(userId);
                return Ok(databases);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error getting databases");
                return StatusCode(500, "Error getting databases");
            }
        }

        [HttpPost("database")]
        public async Task<IActionResult> CreateDatabase([FromBody] CreateDatabaseRequest request)
        {
            try
            {
                var userId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
                if (string.IsNullOrEmpty(userId))
                {
                    return Unauthorized("User not authenticated");
                }
                
                var database = await _collaborationService.CreateDatabaseAsync(userId, request.Name);
                return Ok(database);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error creating database with name {Name}", request.Name);
                return StatusCode(500, "Error creating database");
            }
        }

        [HttpDelete("database/{databaseId}")]
        public async Task<IActionResult> DeleteDatabase(string databaseId)
        {
            try
            {
                var userId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
                if (string.IsNullOrEmpty(userId))
                {
                    return Unauthorized("User not authenticated");
                }
                
                await _collaborationService.DeleteDatabaseAsync(databaseId, userId);
                return Ok();
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error deleting database {DatabaseId}", databaseId);
                return StatusCode(500, "Error deleting database");
            }
        }

        [HttpPost("databases/{databaseId}/backup")]
        public async Task<IActionResult> SaveDatabaseBackup(string databaseId, [FromBody] BackupData backupData)
        {
            try
            {
                var userId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
                if (string.IsNullOrEmpty(userId))
                {
                    return Unauthorized();
                }

                await _collaborationService.SaveDatabaseBackupAsync(databaseId, userId, backupData);
                return Ok();
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, $"Ошибка при сохранении резервной копии базы данных {databaseId}");
                return BadRequest($"Ошибка при сохранении резервной копии: {ex.Message}");
            }
        }

        [HttpGet("databases/{databaseId}/backup")]
        public async Task<IActionResult> GetDatabaseBackup(string databaseId)
        {
            try
            {
                var userId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
                if (string.IsNullOrEmpty(userId))
                {
                    return Unauthorized();
                }

                var backup = await _collaborationService.GetDatabaseBackupAsync(databaseId, userId);
                if (backup == null)
                {
                    return Ok(new BackupData { DatabaseId = databaseId, UserId = userId });
                }
                return Ok(backup);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, $"Ошибка при получении резервной копии базы данных {databaseId}");
                return BadRequest($"Ошибка при получении резервной копии: {ex.Message}");
            }
        }

        [HttpGet("databases/{databaseId}")]
        public async Task<IActionResult> GetDatabase(string databaseId)
        {
            try
            {
                var userId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
                if (string.IsNullOrEmpty(userId))
                {
                    return Unauthorized();
                }

                try
                {
                    var database = await _collaborationService.GetDatabaseAsync(databaseId, userId);
                    return Ok(database);
                }
                catch (Exception ex) when (ex.Message == "База данных не найдена")
                {
                    return NotFound(ex.Message);
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Ошибка при получении информации о базе данных");
                return StatusCode(500, "Ошибка при получении информации о базе данных");
            }
        }

        [HttpPost("databases/{databaseId}/replace")]
        public async Task<IActionResult> ReplaceLocalDatabase(string databaseId, [FromBody] BackupData backupData)
        {
            try
            {
                var userId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
                if (string.IsNullOrEmpty(userId))
                {
                    return Unauthorized();
                }

                await _collaborationService.ReplaceLocalDatabaseAsync(databaseId, userId, backupData);
                return Ok();
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, $"Ошибка при замене данных в базе данных {databaseId}");
                return BadRequest($"Ошибка при замене данных: {ex.Message}");
            }
        }

        [HttpGet("database/{databaseId}/note/{noteId}")]
        public async Task<ActionResult<Note>> GetNote(string databaseId, string noteId)
        {
            try
            {
                var note = await _collaborationService.GetNoteAsync(databaseId, noteId);
                if (note == null)
                {
                    return NotFound();
                }
                return Ok(note);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error getting note {NoteId} from database {DatabaseId}", noteId, databaseId);
                return StatusCode(500, "Error getting note");
            }
        }

        [HttpPost("database/{databaseId}/note")]
        public async Task<IActionResult> SaveNote(string databaseId, [FromBody] Note note)
        {
            try
            {
                await _collaborationService.SaveNoteAsync(databaseId, note);
                return Ok();
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error saving note {NoteId} to database {DatabaseId}", note.Id, databaseId);
                return StatusCode(500, "Error saving note");
            }
        }

        [HttpDelete("database/{databaseId}/note/{noteId}")]
        public async Task<IActionResult> DeleteNote(string databaseId, string noteId)
        {
            try
            {
                await _collaborationService.DeleteNoteAsync(databaseId, noteId);
                return Ok();
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error deleting note {NoteId} from database {DatabaseId}", noteId, databaseId);
                return StatusCode(500, "Error deleting note");
            }
        }
    }
} 